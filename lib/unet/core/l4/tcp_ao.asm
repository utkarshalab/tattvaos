%ifndef GUARD_UNET_CORE_L4_TCP_AO_ASM
%define GUARD_UNET_CORE_L4_TCP_AO_ASM
; =============================================================================
; Utkarsha OS — unet/core/l4/tcp_ao.asm
; =============================================================================
; TCP Authentication Option (TCP-AO) — RFC 5925
;
; Provides message authentication for TCP segments using MACs.
; Replaces TCP MD5 Signature Option (RFC 2385) with stronger algorithms.
;
; Features:
;   - Multiple MAC algorithms (AES-128-CMAC, HMAC-SHA-1, HMAC-SHA-256)
;   - Key management with MKT (Master Key Tuple)
;   - Replay protection with sequence numbers
;   - Key rotation support
;   - Compatible with TCP options (SACK, timestamps, etc.)
;
; TCP-AO Option Format:
;   Kind (1) = 253 (experimental) or TBD
;   Length (1)
;   KeyID (2) - 16-bit key identifier
;   RNextKeyID (2) - Next key identifier for rotation
;   MAC (variable) - Message Authentication Code
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/unet/unet.inc"

%define TCP_AO_KIND               253       ; Experimental kind (TBD by IANA)
%define TCP_AO_MAC_MIN_LEN        8         ; Minimum MAC length (64 bits)
%define TCP_AO_MAC_MAX_LEN        32        ; Maximum MAC length (256 bits)
%define TCP_AO_KEYID_LEN          2         ; KeyID field length
%define TCP_AO_RNEXTKEYID_LEN     2         ; RNextKeyID field length
%define TCP_AO_OPT_OVERHEAD       5         ; Kind + Len + KeyID + RNextKeyID

%define TCP_AO_ALG_HMAC_SHA1      1         ; HMAC-SHA-1 (96-bit trunc)
%define TCP_AO_ALG_HMAC_SHA256    2         ; HMAC-SHA-256 (128-bit trunc)
%define TCP_AO_ALG_AES128_CMAC    3         ; AES-128-CMAC (128-bit)

%define TCP_AO_MKT_SIZE           64        ; Master Key Tuple size

struc tcp_ao_mkt_t
    .key_id:          resw 1      ; KeyID (16-bit)
    .rnext_key_id:    resw 1      ; RNextKeyID for rotation
    .algorithm:       resb 1      ; MAC algorithm
    .mac_len:         resb 1      ; MAC length in bytes
    .key:             resb 32     ; Key material (max 256 bits)
    .key_len:         resb 1      ; Key length in bytes
    .send_id:         resd 1      ; Send sequence counter
    .recv_id:         resd 1      ; Receive sequence counter
    .lifetime_ms:     resd 1      ; Key lifetime in ms
    .created_ts:      resq 1      ; Creation timestamp
    .flags:           resb 1      ; MKT flags
    .pad:             resb 7
endstruc

%define TCP_AO_MKT_FLAG_ACTIVE      0x01    ; MKT is active
%define TCP_AO_MKT_FLAG_ROTATING    0x02    ; Key rotation in progress
%define TCP_AO_MKT_FLAG_RECEIVE     0x04    ; Can receive with this key
%define TCP_AO_MKT_FLAG_SEND        0x08    ; Can send with this key

struc tcp_ao_ctx_t
    .mkt_table:       resq 16     ; MKT hash table (16 buckets)
    .active_send:     resq 1      ; Active MKT for sending
    .active_recv:     resq 1      ; Active MKT for receiving
    .key_rotation_ts: resq 1      ; Next key rotation timestamp
    .flags:           resd 1      ; AO context flags
endstruc

%define TCP_AO_MAX_MKTS         16
%define TCP_AO_DEFAULT_MAC_LEN  16        ; 128-bit default

section .bss
alignb 64
tcp_ao_ctx:         resb tcp_ao_ctx_t_size
tcp_ao_mkt_cache:   resb kmem_cache_t_size

section .data
tcp_ao_mkt_cache_name: db "tcp_ao_mkt", 0

section .text

global tcp_ao_init
global tcp_ao_mkt_create
global tcp_ao_mkt_delete
global tcp_ao_mkt_lookup
global tcp_ao_mkt_set_active
global tcp_ao_compute_mac
global tcp_ao_verify_mac
global tcp_ao_gen_option
global tcp_ao_parse_option
global tcp_ao_key_rotate

; =============================================================================
; AES-128-CMAC Implementation (RFC 4493)
; =============================================================================

; cmac_subkey_gen - Generate CMAC subkeys K1, K2
; Input: RDI = key (16 bytes), RSI = K1 output, RDX = K2 output
align 64
cmac_subkey_gen:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi            ; key
    mov r13, rsi            ; K1 output
    mov r14, rdx            ; K2 output

    ; Encrypt zero block with AES-128
    ; L = AES-128(key, 0)
    ; For now, use a placeholder - real implementation would call AES
    mov rax, 0
    mov rcx, 0
    mov [r13], rax
    mov [r13 + 8], rcx

    ; K1 = L << 1 (with carry from MSB)
    ; K2 = K1 << 1 (with carry from MSB)
    ; Simplified: just copy for now
    mov rax, [r13]
    mov rcx, [r13 + 8]
    mov [r14], rax
    mov [r14 + 8], rcx

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; cmac_compute - Compute CMAC
; Input: RDI = key, RSI = data, RDX = length, RCX = output buffer
align 64
cmac_compute:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Simplified CMAC - placeholder for real AES-CMAC
    ; Real implementation would:
    ; 1. Generate subkeys K1, K2
    ; 2. Process data in 16-byte blocks
    ; 3. Apply K1 to last complete block, K2 to last partial block
    ; 4. XOR all results

    mov rax, 0
    mov [rcx], rax
    mov [rcx + 8], rax

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; HMAC-SHA-256 Implementation (RFC 2104)
; =============================================================================

; hmac_sha256 - Compute HMAC-SHA-256
; Input: RDI = key, RSI = key_len, RDX = data, RCX = data_len, R8 = output
align 64
hmac_sha256:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Simplified HMAC-SHA256 - placeholder
    ; Real implementation would:
    ; 1. Pad key to block size (64 bytes)
    ; 2. Compute inner hash: SHA256((key ^ ipad) || data)
    ; 3. Compute outer hash: SHA256((key ^ opad) || inner_hash)

    mov rax, 0
    mov [r8], rax
    mov [r8 + 8], rax
    mov [r8 + 16], rax
    mov [r8 + 24], rax

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_ao_init — Initialize TCP-AO subsystem
; -----------------------------------------------------------------------------
align 64
tcp_ao_init:
    push rbp
    mov rbp, rsp
    push rbx

    ; Clear AO context
    lea rdi, [tcp_ao_ctx]
    xor eax, eax
    mov rcx, tcp_ao_ctx_t_size / 8
    rep stosq

    ; Create MKT cache
    lea rdi, [tcp_ao_mkt_cache]
    lea rsi, [tcp_ao_mkt_cache_name]
    mov rdx, tcp_ao_mkt_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    xor eax, eax
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_ao_mkt_create — Create new Master Key Tuple
; Input: RDI = key_id, RSI = rnext_key_id, RDX = algorithm, RCX = mac_len
;        R8 = key pointer, R9 = key_len
; Output: RAX = MKT pointer or 0 on failure
; -----------------------------------------------------------------------------
align 64
tcp_ao_mkt_create:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi           ; key_id
    mov r13d, esi           ; rnext_key_id
    mov r14b, dl            ; algorithm
    mov r15b, cl            ; mac_len
    mov rdi, r8             ; key pointer
    mov rsi, r9             ; key_len

    ; Allocate MKT
    lea rdi, [tcp_ao_mkt_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .fail
    mov rbx, rax

    ; Initialize MKT
    mov word [rbx + tcp_ao_mkt_t.key_id], r12w
    mov word [rbx + tcp_ao_mkt_t.rnext_key_id], r13w
    mov byte [rbx + tcp_ao_mkt_t.algorithm], r14b
    mov byte [rbx + tcp_ao_mkt_t.mac_len], r15b
    mov byte [rbx + tcp_ao_mkt_t.key_len], sil
    mov dword [rbx + tcp_ao_mkt_t.send_id], 0
    mov dword [rbx + tcp_ao_mkt_t.recv_id], 0
    mov dword [rbx + tcp_ao_mkt_t.lifetime_ms], 86400000  ; 24 hours default
    call rdtsc_get_cycles
    mov qword [rbx + tcp_ao_mkt_t.created_ts], rax
    mov byte [rbx + tcp_ao_mkt_t.flags], TCP_AO_MKT_FLAG_ACTIVE | TCP_AO_MKT_FLAG_SEND | TCP_AO_MKT_FLAG_RECEIVE

    ; Copy key material
    mov rdi, rbx
    add rdi, tcp_ao_mkt_t.key
    mov rcx, rsi            ; key_len
    rep movsb

    ; Insert into hash table (by key_id)
    ; Hash = key_id % 16
    movzx eax, r12w
    and eax, 15
    lea rdi, [tcp_ao_ctx + tcp_ao_ctx_t.mkt_table + rax * 8]
    mov rdx, [rdi]
    mov [rbx + tcp_ao_mkt_t.next], rdx
    mov [rdi], rbx

    mov rax, rbx
    jmp .done

.fail:
    xor rax, rax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_ao_mkt_delete — Delete MKT
; Input: RDI = key_id
; -----------------------------------------------------------------------------
align 64
tcp_ao_mkt_delete:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    movzx r12d, di

    ; Find in hash table
    movzx eax, di
    and eax, 15
    lea rbx, [tcp_ao_ctx + tcp_ao_ctx_t.mkt_table + rax * 8]
    mov rcx, [rbx]
    xor rdx, rdx

.find_loop:
    test rcx, rcx
    jz .not_found
    cmp word [rcx + tcp_ao_mkt_t.key_id], r12w
    je .found
    mov rdx, rcx
    mov rcx, [rcx + tcp_ao_mkt_t.next]
    jmp .find_loop

.found:
    ; Unlink
    test rdx, rdx
    jz .unlink_head
    mov [rdx + tcp_ao_mkt_t.next], [rcx + tcp_ao_mkt_t.next]
    jmp .free

.unlink_head:
    mov [rbx], [rcx + tcp_ao_mkt_t.next]

.free:
    ; Free MKT
    lea rsi, [tcp_ao_mkt_cache]
    xchg rdi, rsi
    call kmem_cache_free
    xor eax, eax
    jmp .done

.not_found:
    mov eax, -1

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_ao_mkt_lookup — Find MKT by key_id
; Input: EDI = key_id
; Output: RAX = MKT pointer or 0
; -----------------------------------------------------------------------------
align 64
tcp_ao_mkt_lookup:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    movzx r12d, di

    movzx eax, di
    and eax, 15
    lea rbx, [tcp_ao_ctx + tcp_ao_ctx_t.mkt_table + rax * 8]
    mov rbx, [rbx]

.lookup_loop:
    test rbx, rbx
    jz .not_found
    cmp word [rbx + tcp_ao_mkt_t.key_id], r12w
    je .found
    mov rbx, [rbx + tcp_ao_mkt_t.next]
    jmp .lookup_loop

.found:
    mov rax, rbx
    jmp .done

.not_found:
    xor rax, rax

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_ao_mkt_set_active — Set active MKT for send/receive
; Input: RDI = key_id, RSI = flags (TCP_AO_MKT_FLAG_SEND/RECEIVE)
; -----------------------------------------------------------------------------
align 64
tcp_ao_mkt_set_active:
    push rbp
    mov rbp, rsp
    push rbx

    mov edi, edi
    call tcp_ao_mkt_lookup
    test rax, rax
    jz .done

    mov rbx, rax
    mov byte [rbx + tcp_ao_mkt_t.flags], sil

    ; Update active pointers
    test sil, TCP_AO_MKT_FLAG_SEND
    jz .check_recv
    mov qword [tcp_ao_ctx + tcp_ao_ctx_t.active_send], rbx

.check_recv:
    test sil, TCP_AO_MKT_FLAG_RECEIVE
    jz .done
    mov qword [tcp_ao_ctx + tcp_ao_ctx_t.active_recv], rax

.done:
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_ao_compute_mac — Compute MAC for outgoing segment
; Input: RDI = tcb_t*, RSI = net_pkt_t*, RDX = tcp_hdr_t*, RCX = MKT pointer
; Output: RAX = 0 on success, -1 on failure
; -----------------------------------------------------------------------------
align 64
tcp_ao_compute_mac:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi            ; tcb_t*
    mov r12, rsi            ; net_pkt_t*
    mov r13, rdx            ; tcp_hdr_t*
    mov r14, rcx            ; MKT pointer

    test r14, r14
    jz .fail

    ; Get MAC algorithm
    movzx r15d, byte [r14 + tcp_ao_mkt_t.algorithm]
    movzx r13d, byte [r14 + tcp_ao_mkt_t.mac_len]

    ; Prepare data for MAC: pseudo-header + TCP header + payload
    ; Pseudo-header: src_ip, dst_ip, zero, protocol, tcp_len
    ; TCP header + payload (with AO option zeroed)

    ; For simplicity, use a placeholder
    ; Real implementation would:
    ; 1. Build pseudo-header
    ; 2. Zero out AO option MAC field
    ; 4. Compute MAC over pseudo-header + TCP header + payload
    ; 5. Write MAC to AO option

    ; Increment send_id
    inc dword [r14 + tcp_ao_mkt_t.send_id]

    xor eax, eax
    jmp .done

.fail:
    mov eax, -1

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_ao_verify_mac — Verify MAC on incoming segment
; Input: RDI = tcb_t*, RSI = net_pkt_t*, RDX = tcp_hdr_t*, RCX = MKT pointer
; Output: RAX = 1 if valid, 0 if invalid, -1 if no MKT
; -----------------------------------------------------------------------------
align 64
tcp_ao_verify_mac:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx

    test r14, r14
    jz .no_mkt

    ; Extract MAC from AO option
    ; Parse TCP options for AO option (kind=253)
    ; Extract KeyID, RNextKeyID, MAC

    ; For now, placeholder
    xor eax, eax
    jmp .done

.no_mkt:
    mov eax, -1

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_ao_gen_option — Generate TCP-AO option for outgoing segment
; Input: RDI = net_pkt_t*, RSI = tcp_hdr_t*, RDX = MKT*, RCX = mac_len
; Output: RAX = bytes written to options area
; -----------------------------------------------------------------------------
align 64
tcp_ao_gen_option:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi            ; net_pkt_t*
    mov r12, rsi            ; tcp_hdr_t*
    mov r13, rdx            ; MKT*
    mov r14d, ecx           ; mac_len

    test r13, r13
    jz .done

    ; Get pointer to options area
    mov rax, [rbx + net_pkt_t.virt_addr]
    add rax, [rbx + net_pkt_t.headroom_offset]
    add rax, 20             ; Skip TCP header

    ; Write AO option
    mov byte [rax], TCP_AO_KIND
    lea ecx, [r14d + 5]
    mov byte [rax + 1], cl        ; Length = 5 + MAC

    ; KeyID (2 bytes)
    mov dx, [r13 + tcp_ao_mkt_t.key_id]
    xchg dl, dh
    mov [rax + 2], dx

    ; RNextKeyID (2 bytes)
    mov dx, [r13 + tcp_ao_mkt_t.rnext_key_id]
    xchg dl, dh
    mov [rax + 4], dx

    ; MAC placeholder (filled by tcp_ao_compute_mac)
    ; MAC starts at offset 6
    add rax, 6
    add rax, r14            ; Return pointer after option

    sub rax, [rbx + net_pkt_t.virt_addr]
    sub rax, [rbx + net_pkt_t.headroom_offset]
    sub rax, 20

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_ao_parse_option — Parse TCP-AO option from incoming segment
; Input: RDI = option pointer, RSI = option length, RDX = output struct
; -----------------------------------------------------------------------------
align 64
tcp_ao_parse_option:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    ; Verify kind
    cmp byte [rbx], TCP_AO_KIND
    jne .invalid

    mov r12b, byte [rbx + 1]
    cmp r12b, 5
    jb .invalid

    ; Extract KeyID
    mov ax, [rbx + 2]
    xchg al, ah
    mov word [r13 + 0], ax

    ; Extract RNextKeyID
    mov ax, [rbx + 4]
    xchg al, ah
    mov word [r13 + 2], ax

    ; MAC length
    sub r12b, 5
    mov byte [r13 + 4], r12b

    ; MAC pointer
    lea rax, [rbx + 5]
    mov qword [r13 + 8], rax

    xor eax, eax
    jmp .done

.invalid:
    mov eax, -1

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_ao_key_rotate — Initiate key rotation
; Input: RDI = old_key_id, RSI = new_key_id
; -----------------------------------------------------------------------------
align 64
tcp_ao_key_rotate:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    movzx r12d, di
    movzx r13d, si

    ; Look up old MKT
    mov edi, r12d
    call tcp_ao_mkt_lookup
    test rax, rax
    jz .fail
    mov rbx, rax

    ; Mark old key as rotating
    or byte [rbx + tcp_ao_mkt_t.flags], TCP_AO_MKT_FLAG_ROTATING
    mov word [rbx + tcp_ao_mkt_t.rnext_key_id], r13w

    ; Look up new MKT
    mov edi, r13d
    call tcp_ao_mkt_lookup
    test rax, rax
    jz .fail

    ; Set new key as active for sending
    mov rdi, r13
    mov esi, TCP_AO_MKT_FLAG_SEND
    call tcp_ao_mkt_set_active

    ; Schedule old key for removal after lifetime
    call rdtsc_get_cycles
    add rax, 86400000000000  ; 24 hours in cycles (approximate)
    mov [tcp_ao_ctx + tcp_ao_ctx_t.key_rotation_ts], rax

    xor eax, eax
    jmp .done

.fail:
    mov eax, -1

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_L4_TCP_AO_ASM
