%ifndef GUARD_STORAGE_UXFS_DRIVERS_NVME_ZNS_ASM
%define GUARD_STORAGE_UXFS_DRIVERS_NVME_ZNS_ASM
; =============================================================================
; Tattva OS — storage/uxfs/drivers/nvme_zns.asm
; =============================================================================
; NVMe Zoned Namespaces (ZNS) Driver.
;
; Implements:
;   - Zone Append with device-assigned placement (`uxfs_nvme_zns_zone_append`)
;   - Zone management: open, close, finish, reset (`uxfs_nvme_zns_*_zone`)
;   - Zone report and write-pointer tracking (`uxfs_nvme_zns_report_zones`)
;   - Host-side zone state validation (`uxfs_nvme_zns_check_writable`)
;
; A zoned namespace divides the device into large zones that must be written
; SEQUENTIALLY. There is no in-place overwrite: a zone is written front to
; back, then reset as a whole before reuse. In exchange the drive needs almost
; no over-provisioning or garbage collection, because the host has already
; arranged writes the way the flash wants them.
;
; Zone Append (opcode 0x7D) is the important primitive. An ordinary write must
; target the exact current write pointer, so two concurrent writers race and
; one fails. Append instead says "put this somewhere in this zone" and the
; device returns the LBA it chose, so many writers can share a zone with no
; host-side locking at all.
;
; Zone state machine, per the ZNS specification:
;
;   EMPTY -> IMPLICITLY OPEN -> CLOSED -> FULL
;              \-> EXPLICITLY OPEN -/
;   any state -> EMPTY (via RESET)
;
; Writes are only legal in EMPTY, IMPLICITLY OPEN or EXPLICITLY OPEN. Issuing
; one against a FULL or OFFLINE zone is rejected by the device, so the host
; check here exists to catch it before burning a queue slot.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define NVME_ZNS_OPCODE_ZONE_APPEND 0x7D
%define NVME_ZNS_OPCODE_ZONE_MGMT   0x79
%define NVME_ZNS_OPCODE_ZONE_RECV   0x7A

%define NVME_ZNS_ACTION_CLOSE       0x01
%define NVME_ZNS_ACTION_FINISH      0x02
%define NVME_ZNS_ACTION_OPEN        0x03
%define NVME_ZNS_ACTION_RESET       0x04
%define NVME_ZNS_ACTION_OFFLINE     0x05

; Zone states as reported in the zone descriptor.
%define NVME_ZNS_STATE_EMPTY        0x01
%define NVME_ZNS_STATE_IMP_OPEN     0x02
%define NVME_ZNS_STATE_EXP_OPEN     0x03
%define NVME_ZNS_STATE_CLOSED       0x04
%define NVME_ZNS_STATE_READONLY     0x0D
%define NVME_ZNS_STATE_FULL         0x0E
%define NVME_ZNS_STATE_OFFLINE      0x0F

%define NVME_ZNS_SELECT_ALL         0x01    ; CDW13 bit 8: apply to every zone

struc uxfs_nvme_zns_desc_t
    .zt:                resb 1      ; Zone Type (1 = Sequential Write Required)
    .zs:                resb 1      ; Zone State (see NVME_ZNS_STATE_*)
    .za:                resb 1      ; Zone Attributes
    .reserved:          resb 5
    .zcap:              resq 1      ; Zone Capacity in LBAs
    .zslba:             resq 1      ; Zone Start Logical Block Address
    .wp:                resq 1      ; Current Write Pointer LBA
endstruc

section .data
align 8
uxfs_zns_appends:       dq 0
uxfs_zns_resets:        dq 0
uxfs_zns_rejected:      dq 0        ; Writes refused by the host-side check

section .text

global uxfs_nvme_zns_zone_append
global uxfs_nvme_zns_reset_zone
global uxfs_nvme_zns_open_zone
global uxfs_nvme_zns_close_zone
global uxfs_nvme_zns_finish_zone
global uxfs_nvme_zns_report_zones
global uxfs_nvme_zns_check_writable
global uxfs_nvme_zns_zone_mgmt_send

; -----------------------------------------------------------------------------
; uxfs_nvme_zns_check_writable
;
; Validates a zone descriptor before a write is issued.
;
; Inputs:
;   RDI = Pointer to a uxfs_nvme_zns_desc_t
;   RSI = Number of blocks the caller intends to write
;
; Returns:
;   EAX = 0 when the write is legal
;         POSIX_EACCES when the zone state forbids writing
;         POSIX_ENOSPC when the write would run past the zone capacity
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_zns_check_writable:
    push rbx

    test rdi, rdi
    jz .cw_inval

    movzx eax, byte [rdi + uxfs_nvme_zns_desc_t.zs]

    ; Only these three states accept writes.
    cmp eax, NVME_ZNS_STATE_EMPTY
    je .cw_state_ok
    cmp eax, NVME_ZNS_STATE_IMP_OPEN
    je .cw_state_ok
    cmp eax, NVME_ZNS_STATE_EXP_OPEN
    je .cw_state_ok

    inc qword [uxfs_zns_rejected]
    mov eax, POSIX_EACCES
    pop rbx
    ret

.cw_state_ok:
    ; Write pointer plus this write must stay inside the zone capacity.
    mov rbx, [rdi + uxfs_nvme_zns_desc_t.wp]
    sub rbx, [rdi + uxfs_nvme_zns_desc_t.zslba]     ; Blocks already written
    add rbx, rsi
    cmp rbx, [rdi + uxfs_nvme_zns_desc_t.zcap]
    ja .cw_nospc

    xor eax, eax
    pop rbx
    ret

.cw_nospc:
    inc qword [uxfs_zns_rejected]
    mov eax, POSIX_ENOSPC
    pop rbx
    ret

.cw_inval:
    mov eax, POSIX_EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_zns_zone_append
;
; Appends blocks to a zone and lets the device choose the placement.
;
; SLBA carries the ZONE START, not the write pointer — that is what makes
; append race-free. The device returns the assigned LBA in the completion.
;
; Inputs:
;   RDI = Pointer to uxfs_nvme_zns_ctrl (a uxfs_nvme_ctrl_t)
;   RSI = Zone Start LBA
;   RDX = Block count
;   RCX = Physical DMA source buffer
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on submission failure
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_zns_zone_append:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Controller
    mov r12, rsi                    ; Zone start LBA
    mov r13, rdx                    ; Block count
    mov r14, rcx                    ; Buffer

    test rbx, rbx
    jz .za_inval
    test r13, r13
    jz .za_inval

    sub rsp, uxfs_nvme_sqe_t_size

    ; Zero first: stale stack bytes land in fields the controller reads.
    mov rdi, rsp
    mov rcx, uxfs_nvme_sqe_t_size
    xor al, al
    rep stosb

    mov eax, [uxfs_nvme_global_cid]
    inc dword [uxfs_nvme_global_cid]
    shl eax, 16
    or eax, NVME_ZNS_OPCODE_ZONE_APPEND
    mov dword [rsp + uxfs_nvme_sqe_t.cdw0_opcode], eax

    mov eax, [rbx + uxfs_nvme_ctrl_t.nsid]
    mov dword [rsp + uxfs_nvme_sqe_t.nsid], eax
    mov [rsp + uxfs_nvme_sqe_t.prp1], r14
    mov [rsp + uxfs_nvme_sqe_t.slba], r12       ; Zone start, not write pointer

    mov rax, r13
    dec rax                                     ; NLB is 0-based
    mov word [rsp + uxfs_nvme_sqe_t.nlb], ax

    mov rdi, rbx
    mov rsi, rsp
    call uxfs_nvme_submit_cmd

    add rsp, uxfs_nvme_sqe_t_size

    inc qword [uxfs_zns_appends]
    xor eax, eax
    jmp .za_return

.za_inval:
    mov eax, POSIX_EINVAL

.za_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_zns_zone_mgmt_send
;
; Issues a Zone Management Send command. All four state transitions share this
; path; only the action code in CDW13 differs.
;
; Inputs:
;   RDI = Pointer to uxfs_nvme_ctrl_t
;   RSI = Zone Start LBA
;   EDX = NVME_ZNS_ACTION_*
;   ECX = Non-zero to apply to every zone, ignoring SLBA
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on submission failure
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_zns_zone_mgmt_send:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Controller
    mov r12, rsi                    ; Zone start LBA
    mov r13d, edx                   ; Action
    mov r14d, ecx                   ; Select-all flag

    test rbx, rbx
    jz .zm_inval

    sub rsp, uxfs_nvme_sqe_t_size

    mov rdi, rsp
    mov rcx, uxfs_nvme_sqe_t_size
    xor al, al
    rep stosb

    mov eax, [uxfs_nvme_global_cid]
    inc dword [uxfs_nvme_global_cid]
    shl eax, 16
    or eax, NVME_ZNS_OPCODE_ZONE_MGMT
    mov dword [rsp + uxfs_nvme_sqe_t.cdw0_opcode], eax

    mov eax, [rbx + uxfs_nvme_ctrl_t.nsid]
    mov dword [rsp + uxfs_nvme_sqe_t.nsid], eax
    mov [rsp + uxfs_nvme_sqe_t.slba], r12

    ; CDW13: action in the low byte, select-all in bit 8.
    mov eax, r13d
    and eax, 0xFF
    test r14d, r14d
    jz .zm_no_all
    or eax, (NVME_ZNS_SELECT_ALL << 8)

.zm_no_all:
    mov dword [rsp + uxfs_nvme_sqe_t.dspec], eax

    mov rdi, rbx
    mov rsi, rsp
    call uxfs_nvme_submit_cmd

    add rsp, uxfs_nvme_sqe_t_size

    xor eax, eax
    jmp .zm_return

.zm_inval:
    mov eax, POSIX_EINVAL

.zm_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_zns_reset_zone
;
; Returns a zone to EMPTY and rewinds its write pointer. This is the only way
; to reuse written space — there is no overwrite in a sequential zone.
;
; Inputs:
;   RDI = Pointer to uxfs_nvme_ctrl_t
;   RSI = Zone Start LBA
;
; Returns:
;   EAX = 0 on success
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_zns_reset_zone:
    mov edx, NVME_ZNS_ACTION_RESET
    xor ecx, ecx
    call uxfs_nvme_zns_zone_mgmt_send
    inc qword [uxfs_zns_resets]
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_zns_open_zone
;
; Explicitly opens a zone, reserving device resources for it. Explicit opens
; are bounded by the controller's active-zone limit, so a host that opens
; without closing will eventually be refused.
;
; Inputs:
;   RDI = Pointer to uxfs_nvme_ctrl_t
;   RSI = Zone Start LBA
;
; Returns:
;   EAX = 0 on success
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_zns_open_zone:
    mov edx, NVME_ZNS_ACTION_OPEN
    xor ecx, ecx
    jmp uxfs_nvme_zns_zone_mgmt_send

; -----------------------------------------------------------------------------
; uxfs_nvme_zns_close_zone
;
; Closes a zone, releasing device resources while keeping the write pointer.
; The zone can be written again later without being reset.
;
; Inputs:
;   RDI = Pointer to uxfs_nvme_ctrl_t
;   RSI = Zone Start LBA
;
; Returns:
;   EAX = 0 on success
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_zns_close_zone:
    mov edx, NVME_ZNS_ACTION_CLOSE
    xor ecx, ecx
    jmp uxfs_nvme_zns_zone_mgmt_send

; -----------------------------------------------------------------------------
; uxfs_nvme_zns_finish_zone
;
; Forces a zone to FULL regardless of how much was written. Used to retire a
; partially-filled zone so it stops consuming an active-zone slot.
;
; Inputs:
;   RDI = Pointer to uxfs_nvme_ctrl_t
;   RSI = Zone Start LBA
;
; Returns:
;   EAX = 0 on success
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_zns_finish_zone:
    mov edx, NVME_ZNS_ACTION_FINISH
    xor ecx, ecx
    jmp uxfs_nvme_zns_zone_mgmt_send

; -----------------------------------------------------------------------------
; uxfs_nvme_zns_report_zones
;
; Requests zone descriptors into a host buffer via Zone Management Receive.
; The reply begins with an 8-byte zone count followed by 64-byte descriptors.
;
; Inputs:
;   RDI = Pointer to uxfs_nvme_ctrl_t
;   RSI = Starting Zone LBA
;   RDX = Physical DMA destination buffer
;   ECX = Buffer size in bytes
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on submission failure
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_zns_report_zones:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx

    test rbx, rbx
    jz .rz_inval
    test r13, r13
    jz .rz_inval
    cmp r14d, 64
    jb .rz_inval                    ; Cannot hold even one descriptor

    sub rsp, uxfs_nvme_sqe_t_size

    mov rdi, rsp
    mov rcx, uxfs_nvme_sqe_t_size
    xor al, al
    rep stosb

    mov eax, [uxfs_nvme_global_cid]
    inc dword [uxfs_nvme_global_cid]
    shl eax, 16
    or eax, NVME_ZNS_OPCODE_ZONE_RECV
    mov dword [rsp + uxfs_nvme_sqe_t.cdw0_opcode], eax

    mov eax, [rbx + uxfs_nvme_ctrl_t.nsid]
    mov dword [rsp + uxfs_nvme_sqe_t.nsid], eax
    mov [rsp + uxfs_nvme_sqe_t.prp1], r13
    mov [rsp + uxfs_nvme_sqe_t.slba], r12

    ; NUMD is a 0-based dword count of the transfer.
    mov eax, r14d
    shr eax, 2
    dec eax
    mov dword [rsp + uxfs_nvme_sqe_t.cdw14], eax

    mov rdi, rbx
    mov rsi, rsp
    call uxfs_nvme_submit_cmd

    add rsp, uxfs_nvme_sqe_t_size

    xor eax, eax
    jmp .rz_return

.rz_inval:
    mov eax, POSIX_EINVAL

.rz_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_DRIVERS_NVME_ZNS_ASM
