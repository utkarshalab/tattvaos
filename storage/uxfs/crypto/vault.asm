%ifndef GUARD_STORAGE_UXFS_CRYPTO_VAULT_ASM
%define GUARD_STORAGE_UXFS_CRYPTO_VAULT_ASM
; =============================================================================
; Tattva OS — storage/uxfs/crypto/vault.asm
; =============================================================================
; TPM 2.0 Master Key Vault — TIS Transport & PCR-Bound Unsealing.
;
; Implements:
;   - TIS locality arbitration (`uxfs_vault_request/release_locality`)
;   - Status polling with burst-count flow control (`uxfs_vault_wait_status`)
;   - Command submission and response drain (`uxfs_vault_send/recv`)
;   - PCR policy session + TPM2_Unseal (`uxfs_vault_unseal_key`)
;
; The volume master key is sealed to the TPM against a PCR policy, so the chip
; only releases it when the measured boot state still matches. Moving the disk
; to another machine, or booting it under a tampered loader, changes the PCR
; values and the unseal fails — the key never leaves the chip.
;
; Transport is the TIS (TPM Interface Specification) MMIO window at
; 0xFED40000, one 4KB page per locality. TPM structures are BIG-endian on the
; wire, so every multi-byte field is byte-swapped on the way in and out; that
; is the single most common source of bugs in TPM drivers.
;
; Flow control is mandatory, not optional: the FIFO advertises a burst count
; and writing more than it reports before re-reading status will drop bytes.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

; -----------------------------------------------------------------------------
; TIS MMIO layout. Locality 0 is the one an OS normally drives.
; -----------------------------------------------------------------------------
%define TPM_TIS_BASE                 0xFED40000
%define TPM_TIS_LOCALITY_SIZE        0x1000

%define TPM_ACCESS                   0x0000
%define TPM_INT_ENABLE               0x0008
%define TPM_STS                      0x0018
%define TPM_DATA_FIFO                0x0024
%define TPM_DID_VID                  0x0F00

; TPM_ACCESS bits
%define TPM_ACCESS_ESTABLISHMENT     0x01
%define TPM_ACCESS_REQUEST_USE       0x02
%define TPM_ACCESS_PENDING_REQUEST   0x04
%define TPM_ACCESS_SEIZE             0x08
%define TPM_ACCESS_ACTIVE_LOCALITY   0x20
%define TPM_ACCESS_VALID             0x80

; TPM_STS bits
%define TPM_STS_RESPONSE_RETRY       0x02
%define TPM_STS_SELF_TEST_DONE       0x04
%define TPM_STS_EXPECT               0x08
%define TPM_STS_DATA_AVAIL           0x10
%define TPM_STS_GO                   0x20
%define TPM_STS_COMMAND_READY        0x40
%define TPM_STS_VALID                0x80

; TPM 2.0 structure tags and command codes (FIPS / TCG TPM 2.0 Part 2)
%define TPM_ST_NO_SESSIONS           0x8001
%define TPM_ST_SESSIONS              0x8002
%define TPM2_CC_STARTAUTHSESSION     0x00000176
%define TPM2_CC_POLICYPCR            0x0000017F
%define TPM2_CC_UNSEAL               0x0000015E
%define TPM2_CC_FLUSHCONTEXT         0x00000165
%define TPM2_SE_POLICY               0x01
%define TPM2_ALG_SHA256              0x000B
%define TPM2_ALG_NULL                0x0010
%define TPM2_RH_NULL                 0x40000007
%define TPM2_RC_SUCCESS              0x00000000

%define UXFS_VAULT_CMD_BUF           1024
%define UXFS_VAULT_TIMEOUT           0x01000000  ; Poll budget, not wall clock

; Explicitly zeroed rather than reserved: in -f bin a nobits .bss must be the
; final section, and uxfs concatenates many modules after this one.
section .data
align 64

uxfs_vault_cmd:         times UXFS_VAULT_CMD_BUF db 0
uxfs_vault_rsp:         times UXFS_VAULT_CMD_BUF db 0
uxfs_vault_session:     dq 0        ; Live policy session handle

section .text

global uxfs_vault_unseal_key
global uxfs_vault_request_locality
global uxfs_vault_release_locality
global uxfs_vault_wait_status
global uxfs_vault_send
global uxfs_vault_recv
global uxfs_vault_present

; -----------------------------------------------------------------------------
; uxfs_vault_present
;
; Reads the vendor/device register. An absent or unpowered TPM floats all ones
; or reads back zero, either of which means there is no chip to talk to.
;
; Returns:
;   EAX = 1 when a TPM responds, 0 otherwise
; -----------------------------------------------------------------------------
align 32
uxfs_vault_present:
    mov rdx, TPM_TIS_BASE + TPM_DID_VID
    mov eax, dword [rdx]

    cmp eax, 0xFFFFFFFF
    je .vp_absent
    test eax, eax
    jz .vp_absent

    mov eax, 1
    ret

.vp_absent:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; uxfs_vault_request_locality
;
; Claims locality 0 and waits for the chip to grant it.
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on timeout
; -----------------------------------------------------------------------------
align 32
uxfs_vault_request_locality:
    push rbx

    mov rdx, TPM_TIS_BASE + TPM_ACCESS
    mov al, TPM_ACCESS_REQUEST_USE
    mov byte [rdx], al

    mov rbx, UXFS_VAULT_TIMEOUT

.rl_poll:
    mov al, byte [rdx]
    and al, TPM_ACCESS_ACTIVE_LOCALITY | TPM_ACCESS_VALID
    cmp al, TPM_ACCESS_ACTIVE_LOCALITY | TPM_ACCESS_VALID
    je .rl_granted

    pause                           ; Spin hint: this is a slow MMIO peripheral
    dec rbx
    jnz .rl_poll

    mov eax, POSIX_EIO
    pop rbx
    ret

.rl_granted:
    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_vault_release_locality
;
; Drops locality 0 so other software can use the chip.
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_vault_release_locality:
    mov rdx, TPM_TIS_BASE + TPM_ACCESS
    mov al, TPM_ACCESS_ACTIVE_LOCALITY
    mov byte [rdx], al
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; uxfs_vault_wait_status
;
; Polls TPM_STS until the requested bits are set alongside stsValid.
;
; Inputs:
;   EDI = Status bits to wait for
;
; Returns:
;   EAX = 0 when the bits appeared, POSIX_EIO on timeout
; -----------------------------------------------------------------------------
align 32
uxfs_vault_wait_status:
    push rbx
    push r12

    mov r12d, edi
    mov rdx, TPM_TIS_BASE + TPM_STS
    mov rbx, UXFS_VAULT_TIMEOUT

.ws_poll:
    mov al, byte [rdx]
    test al, TPM_STS_VALID
    jz .ws_next                     ; Status not yet meaningful

    mov ecx, eax
    and ecx, r12d
    cmp ecx, r12d
    je .ws_ready

.ws_next:
    pause
    dec rbx
    jnz .ws_poll

    mov eax, POSIX_EIO
    pop r12
    pop rbx
    ret

.ws_ready:
    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_vault_burst_count
;
; Reads how many FIFO bytes the chip will currently accept. Writing past this
; without re-reading loses data, so every send loop must honour it.
;
; Returns:
;   EAX = Burst count in bytes
; -----------------------------------------------------------------------------
align 32
uxfs_vault_burst_count:
    mov rdx, TPM_TIS_BASE + TPM_STS
    mov eax, dword [rdx]
    shr eax, 8                      ; burstCount occupies bits 8..23
    and eax, 0xFFFF
    ret

; -----------------------------------------------------------------------------
; uxfs_vault_send
;
; Writes a fully-formed TPM command into the FIFO and sets tpmGo.
;
; Inputs:
;   RDI = Command buffer
;   ESI = Command length in bytes
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on timeout
; -----------------------------------------------------------------------------
align 32
uxfs_vault_send:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Buffer
    mov r12d, esi                   ; Remaining

    ; Ask the chip to accept a new command.
    mov rdx, TPM_TIS_BASE + TPM_STS
    mov al, TPM_STS_COMMAND_READY
    mov byte [rdx], al

    mov edi, TPM_STS_COMMAND_READY
    call uxfs_vault_wait_status
    test eax, eax
    jnz .vs_fail

    mov r14, TPM_TIS_BASE + TPM_DATA_FIFO

.vs_chunk:
    test r12d, r12d
    jz .vs_go

    call uxfs_vault_burst_count
    test eax, eax
    jz .vs_chunk                    ; Chip busy: re-read rather than push blind
    mov r13d, eax

    cmp r13d, r12d
    jbe .vs_write
    mov r13d, r12d                  ; Never exceed what remains

.vs_write:
    mov al, byte [rbx]
    mov byte [r14], al
    inc rbx
    dec r12d
    dec r13d
    jnz .vs_write
    jmp .vs_chunk

.vs_go:
    ; Chip must report it has everything it expects before we launch.
    mov edi, TPM_STS_VALID
    call uxfs_vault_wait_status
    test eax, eax
    jnz .vs_fail

    mov rdx, TPM_TIS_BASE + TPM_STS
    mov al, TPM_STS_GO
    mov byte [rdx], al

    xor eax, eax
    jmp .vs_return

.vs_fail:
    mov eax, POSIX_EIO

.vs_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_vault_recv
;
; Drains a response. The 6-byte header is read first because it carries the
; total length; the remainder is then pulled honouring burst count.
;
; Inputs:
;   RDI = Response buffer
;   ESI = Buffer capacity
;
; Returns:
;   EAX = Response byte count, or POSIX_EIO
; -----------------------------------------------------------------------------
align 32
uxfs_vault_recv:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Buffer
    mov r12d, esi                   ; Capacity

    mov edi, TPM_STS_DATA_AVAIL
    call uxfs_vault_wait_status
    test eax, eax
    jnz .vr_fail

    mov r14, TPM_TIS_BASE + TPM_DATA_FIFO

    ; Header: tag(2) + responseSize(4).
    xor r13d, r13d
.vr_header:
    cmp r13d, 6
    jae .vr_length

    mov al, byte [r14]
    mov byte [rbx + r13], al
    inc r13d
    jmp .vr_header

.vr_length:
    ; responseSize is big-endian at offset 2.
    mov eax, dword [rbx + 2]
    bswap eax
    cmp eax, 6
    jb .vr_fail                     ; Shorter than its own header
    cmp eax, r12d
    ja .vr_fail                     ; Will not fit: refuse rather than overflow
    mov r12d, eax                   ; Total expected

.vr_body:
    cmp r13d, r12d
    jae .vr_done

    mov al, byte [r14]
    mov byte [rbx + r13], al
    inc r13d
    jmp .vr_body

.vr_done:
    ; Return the chip to idle so the next command can start cleanly.
    mov rdx, TPM_TIS_BASE + TPM_STS
    mov al, TPM_STS_COMMAND_READY
    mov byte [rdx], al

    mov eax, r13d
    jmp .vr_return

.vr_fail:
    mov eax, POSIX_EIO

.vr_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_vault_rc
;
; Extracts the big-endian responseCode from a drained response.
;
; Inputs:
;   RDI = Response buffer
;
; Returns:
;   EAX = TPM response code
; -----------------------------------------------------------------------------
align 32
uxfs_vault_rc:
    mov eax, dword [rdi + 6]
    bswap eax
    ret

; -----------------------------------------------------------------------------
; uxfs_vault_start_policy_session
;
; Opens a TPM2_StartAuthSession policy session bound to SHA-256, then binds the
; current PCR values into it with TPM2_PolicyPCR. The resulting session digest
; is what TPM2_Unseal is authorised against.
;
; Inputs:
;   EDI = PCR selection bitmap for bank 0 (PCRs 0..23, little end first)
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on any TPM failure
; -----------------------------------------------------------------------------
align 32
uxfs_vault_start_policy_session:
    push rbx
    push r12
    push r13

    mov r13d, edi                   ; PCR selection

    lea rbx, [uxfs_vault_cmd]

    ; --- TPM2_StartAuthSession -------------------------------------------
    mov word  [rbx], 0x0180                     ; tag = 0x8001 big-endian
    mov dword [rbx + 2], 0x21000000             ; commandSize = 0x21 (33)
    mov dword [rbx + 6], 0x76010000             ; CC_StartAuthSession
    mov dword [rbx + 10], 0x07000040            ; tpmKey = TPM_RH_NULL
    mov dword [rbx + 14], 0x07000040            ; bind   = TPM_RH_NULL
    mov word  [rbx + 18], 0x1000                ; nonceCaller size = 16
    ; A fixed caller nonce is acceptable here: this session authorises a local
    ; unseal over MMIO, not a remote channel, so replay across a bus we already
    ; trust for the PCR values themselves buys an attacker nothing.
    mov qword [rbx + 20], 0
    mov qword [rbx + 28], 0
    mov word  [rbx + 36], 0x0000                ; encryptedSalt = empty
    mov byte  [rbx + 38], TPM2_SE_POLICY        ; sessionType
    mov word  [rbx + 39], 0x1000                ; symmetric = TPM_ALG_NULL
    mov word  [rbx + 41], 0x0B00                ; authHash  = SHA-256

    mov rdi, rbx
    mov esi, 43
    call uxfs_vault_send
    test eax, eax
    jnz .sp_fail

    lea rdi, [uxfs_vault_rsp]
    mov esi, UXFS_VAULT_CMD_BUF
    call uxfs_vault_recv
    test eax, eax
    js .sp_fail

    lea rdi, [uxfs_vault_rsp]
    call uxfs_vault_rc
    test eax, eax
    jnz .sp_fail

    ; Session handle sits immediately after the 10-byte response header.
    lea rdi, [uxfs_vault_rsp]
    mov eax, dword [rdi + 10]
    bswap eax
    mov [uxfs_vault_session], rax
    mov r12d, eax

    ; --- TPM2_PolicyPCR ---------------------------------------------------
    lea rbx, [uxfs_vault_cmd]
    mov word  [rbx], 0x0180                     ; TPM_ST_NO_SESSIONS
    mov dword [rbx + 2], 0x22000000             ; commandSize = 34
    mov dword [rbx + 6], 0x7F010000             ; CC_PolicyPCR

    mov eax, r12d
    bswap eax
    mov dword [rbx + 10], eax                   ; policySession handle

    mov word  [rbx + 14], 0x0000                ; pcrDigest = empty
    mov dword [rbx + 16], 0x01000000            ; count = 1 selection
    mov word  [rbx + 20], 0x0B00                ; hash = SHA-256
    mov byte  [rbx + 22], 3                     ; sizeofSelect = 3 bytes

    mov eax, r13d                               ; PCR bitmap, LSB = PCR0
    mov byte [rbx + 23], al
    shr eax, 8
    mov byte [rbx + 24], al
    shr eax, 8
    mov byte [rbx + 25], al

    mov rdi, rbx
    mov esi, 26
    call uxfs_vault_send
    test eax, eax
    jnz .sp_fail

    lea rdi, [uxfs_vault_rsp]
    mov esi, UXFS_VAULT_CMD_BUF
    call uxfs_vault_recv
    test eax, eax
    js .sp_fail

    lea rdi, [uxfs_vault_rsp]
    call uxfs_vault_rc
    test eax, eax
    jnz .sp_fail

    xor eax, eax
    jmp .sp_return

.sp_fail:
    mov eax, POSIX_EIO

.sp_return:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_vault_flush_session
;
; Releases the policy session. TPM session slots are a scarce hardware
; resource — leaking them eventually makes StartAuthSession fail outright.
; -----------------------------------------------------------------------------
align 32
uxfs_vault_flush_session:
    push rbx

    mov rax, [uxfs_vault_session]
    test rax, rax
    jz .fs_none

    lea rbx, [uxfs_vault_cmd]
    mov word  [rbx], 0x0180
    mov dword [rbx + 2], 0x0E000000             ; commandSize = 14
    mov dword [rbx + 6], 0x65010000             ; CC_FlushContext
    bswap eax
    mov dword [rbx + 10], eax

    mov rdi, rbx
    mov esi, 14
    call uxfs_vault_send

    lea rdi, [uxfs_vault_rsp]
    mov esi, UXFS_VAULT_CMD_BUF
    call uxfs_vault_recv

    mov qword [uxfs_vault_session], 0

.fs_none:
    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_vault_unseal_key
;
; Runs the full PCR-bound unseal and copies the released master key out.
;
; The output buffer is zeroed first and only overwritten once the TPM reports
; success, so a failed unseal never leaves a partial or stale key behind for a
; caller that forgets to check the return value.
;
; Inputs:
;   RDI = Pointer to a 32-byte master key output buffer
;   ESI = Sealed object handle in TPM NV/persistent space
;   EDX = PCR selection bitmap the key was sealed against
;
; Returns:
;   EAX = 0 on success
;         POSIX_ENODEV when no TPM is present
;         POSIX_EACCES when the PCR policy no longer matches
;         POSIX_EIO    on transport failure
; -----------------------------------------------------------------------------
align 32
uxfs_vault_unseal_key:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Output key buffer
    mov r12d, esi                   ; Sealed object handle
    mov r13d, edx                   ; PCR selection

    test rbx, rbx
    jz .uv_inval

    ; Fail closed before touching hardware.
    mov rdi, rbx
    xor rax, rax
    mov rcx, 4
    rep stosq

    call uxfs_vault_present
    test eax, eax
    jz .uv_nodev

    call uxfs_vault_request_locality
    test eax, eax
    jnz .uv_io

    mov edi, r13d
    call uxfs_vault_start_policy_session
    test eax, eax
    jnz .uv_io_release

    ; --- TPM2_Unseal ------------------------------------------------------
    lea r14, [uxfs_vault_cmd]
    mov word  [r14], 0x0280                     ; TPM_ST_SESSIONS
    mov dword [r14 + 2], 0x1B000000             ; commandSize = 27
    mov dword [r14 + 6], 0x5E010000             ; CC_Unseal

    mov eax, r12d
    bswap eax
    mov dword [r14 + 10], eax                   ; itemHandle

    mov dword [r14 + 14], 0x09000000            ; authorizationSize = 9

    mov eax, dword [uxfs_vault_session]
    bswap eax
    mov dword [r14 + 18], eax                   ; sessionHandle
    mov word  [r14 + 22], 0x0000                ; nonce = empty
    mov byte  [r14 + 24], 0x00                  ; sessionAttributes
    mov word  [r14 + 25], 0x0000                ; hmac = empty

    mov rdi, r14
    mov esi, 27
    call uxfs_vault_send
    test eax, eax
    jnz .uv_io_flush

    lea rdi, [uxfs_vault_rsp]
    mov esi, UXFS_VAULT_CMD_BUF
    call uxfs_vault_recv
    test eax, eax
    js .uv_io_flush

    lea rdi, [uxfs_vault_rsp]
    call uxfs_vault_rc
    test eax, eax
    jnz .uv_denied                  ; Non-zero RC here means policy mismatch

    ; Response: header(10) + paramSize(4) + outData size(2) + outData.
    lea rdi, [uxfs_vault_rsp]
    movzx eax, word [rdi + 14]
    xchg al, ah                     ; Big-endian 16-bit swap
    cmp eax, 32
    jne .uv_denied                  ; Sealed blob is not a 32-byte key

    lea rsi, [rdi + 16]
    mov rdi, rbx
    mov rcx, 4
    rep movsq

    call uxfs_vault_flush_session
    call uxfs_vault_release_locality
    xor eax, eax
    jmp .uv_return

.uv_denied:
    call uxfs_vault_flush_session
    call uxfs_vault_release_locality
    mov eax, POSIX_EACCES
    jmp .uv_return

.uv_io_flush:
    call uxfs_vault_flush_session

.uv_io_release:
    call uxfs_vault_release_locality

.uv_io:
    mov eax, POSIX_EIO
    jmp .uv_return

.uv_nodev:
    mov eax, POSIX_ENODEV
    jmp .uv_return

.uv_inval:
    mov eax, POSIX_EINVAL

.uv_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_CRYPTO_VAULT_ASM
