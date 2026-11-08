; =============================================================================
; Utkarsha OS — lib/ubt/gap/privacy.asm — LE privacy
; =============================================================================
;   ubt_le_privacy(adapter, on, rotate_s) → HCI status: a resolvable private
;                       address of ours (from our IRK) set and used for
;                       advertising and scanning, a new one every rotate_s
;                       seconds (0: 15 minutes); off: the public address
;   ubt_rpa_make(irk, out)      a resolvable private address from an IRK
;   ubt_own_addr_type(adapter) → EAX = 0 public, 1 random (for GAP)
;   ubt_le_resolving_sync(adapter) → HCI status: the controller's resolving
;                       list made from the bonds' IRKs, resolution on
;   ubt_privacy_tick(adapter, now)   the rotation (from ubt_sec_tick)
; =============================================================================

%ifndef LIB_UBT_GAP_PRIVACY_ASM
%define LIB_UBT_GAP_PRIVACY_ASM

%define HCI_LE_ADD_RESOLVING    0x2027
%define HCI_LE_CLEAR_RESOLVING  0x2029
%define HCI_LE_RESOLUTION_ON    0x202D
%define PRIVACY_DEFAULT_S       900

struc ubt_priv
    .adapter:       resq 1
    .on:            resd 1
    .rotate_ms:     resd 1
    .next_at:       resq 1
    .rpa:           resb 6
    .pad:           resw 1
endstruc

section .bss
alignb 8
global ubt_privacy
ubt_privacy:        resb UBT_MAX_ADAPTERS * ubt_priv_size

section .text

; priv_of — RDI = adapter, ESI = 1 to take a slot → RAX = its state, or 0
priv_of:
    lea rax, [rel ubt_privacy]
    xor ecx, ecx
    xor r8d, r8d
.next:
    cmp ecx, UBT_MAX_ADAPTERS
    jae .none
    cmp [rax + ubt_priv.adapter], rdi
    je .out
    test r8, r8
    jnz .skip
    cmp qword [rax + ubt_priv.adapter], 0
    jne .skip
    mov r8, rax
.skip:
    add rax, ubt_priv_size
    inc ecx
    jmp .next
.none:
    xor eax, eax
    test esi, esi
    jz .out
    mov rax, r8
    test rax, rax
    jz .out
    mov [rax + ubt_priv.adapter], rdi
.out:
    ret

; -----------------------------------------------------------------------------
; ubt_rpa_make — RDI = IRK (16, on-air order), RSI = out (6, least
;   significant first) → CF = 1 without randomness. prand: 22 random bits
;   under 01; hash = ah(IRK, prand)
; -----------------------------------------------------------------------------
global ubt_rpa_make
ubt_rpa_make:
    push rbx
    push r12
    sub rsp, 40                         ; IRK (most significant first), prand,
                                        ; hash
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rsp + 16]
    mov esi, 3
    call ubt_random
    jc .out
    and byte [rsp + 16], 0x3F           ; most significant first
    or byte [rsp + 16], 0x40
    mov rdi, rsp
    mov rsi, rbx
    mov ecx, 16
    call ubt_rev
    mov rdi, rsp
    lea rsi, [rsp + 16]
    lea rdx, [rsp + 24]
    call ubt_ah
    ; the address: hash low, prand high, least significant first
    mov al, [rsp + 26]
    mov [r12], al
    mov al, [rsp + 25]
    mov [r12 + 1], al
    mov al, [rsp + 24]
    mov [r12 + 2], al
    mov al, [rsp + 18]
    mov [r12 + 3], al
    mov al, [rsp + 17]
    mov [r12 + 4], al
    mov al, [rsp + 16]
    mov [r12 + 5], al
    pxor xmm0, xmm0
    movdqu [rsp], xmm0
    clc
.out:
    lea rsp, [rsp + 40]
    pop r12
    pop rbx
    ret

; priv_new — RBX = adapter, R12 = its state: a new address made and set
; (ESI = 1: waited for) → EAX = HCI status, or negative
priv_new:
    push r13
    sub rsp, 16
    mov r13d, esi
    call ubt_local_keys_make
    mov eax, -UBT_EIO
    jc .out
    lea rdi, [rel ubt_local_irk]
    lea rsi, [r12 + ubt_priv.rpa]
    call ubt_rpa_make
    mov eax, -UBT_EIO
    jc .out
    call ubt_now
    test rax, rax
    jz .timer
    mov ecx, [r12 + ubt_priv.rotate_ms]
    add rax, rcx
.timer:
    mov [r12 + ubt_priv.next_at], rax
    mov rdi, rbx
    mov esi, HCI_LE_SET_RANDOM_ADDR
    lea rdx, [r12 + ubt_priv.rpa]
    mov ecx, 6
    test r13d, r13d
    jz .async
    call ubt_hci_cmd
    jmp .out
.async:
    call ubt_hci_async
    xor eax, eax
.out:
    add rsp, 16
    pop r13
    ret

; -----------------------------------------------------------------------------
; ubt_le_privacy — RDI = adapter, ESI = 1 on / 0 off, EDX = seconds between
;   addresses (0: 15 minutes) → EAX = HCI status, or negative
; -----------------------------------------------------------------------------
global ubt_le_privacy
ubt_le_privacy:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r13d, esi
    mov r14d, edx
    mov esi, 1
    call priv_of
    mov r12, rax
    mov eax, -UBT_ENOMEM
    test r12, r12
    jz .out
    xor eax, eax
    mov [r12 + ubt_priv.on], r13d
    test r13d, r13d
    jz .out
    test r14d, r14d
    jnz .rotate
    mov r14d, PRIVACY_DEFAULT_S
.rotate:
    imul r14d, r14d, 1000
    mov [r12 + ubt_priv.rotate_ms], r14d
    mov esi, 1
    call priv_new
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ubt_own_addr_type — RDI = adapter → EAX = 1 when privacy is on, else 0
global ubt_own_addr_type
ubt_own_addr_type:
    xor esi, esi
    call priv_of
    test rax, rax
    jz .public
    mov eax, [rax + ubt_priv.on]
    and eax, 1
    ret
.public:
    xor eax, eax
    ret

; ubt_privacy_tick — RDI = adapter, RSI = now: a new address when due
global ubt_privacy_tick
ubt_privacy_tick:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r13, rsi
    xor esi, esi
    call priv_of
    test rax, rax
    jz .out
    mov r12, rax
    cmp dword [r12 + ubt_priv.on], 0
    je .out
    mov rax, [r12 + ubt_priv.next_at]
    test rax, rax
    jz .out
    cmp r13, rax
    jb .out
    xor esi, esi
    call priv_new
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_le_resolving_sync — RDI = adapter → EAX = HCI status (0), or the first
;   failure: the list cleared, each bond with an IRK added (its identity
;   address, its IRK, ours), address resolution turned on
; -----------------------------------------------------------------------------
global ubt_le_resolving_sync
ubt_le_resolving_sync:
    push rbx
    push r12
    push r13
    sub rsp, 48                         ; Add Device To Resolving List (39)
    mov rbx, rdi
    call ubt_local_keys_make
    mov rdi, rbx
    mov esi, HCI_LE_CLEAR_RESOLVING
    xor edx, edx
    xor ecx, ecx
    call ubt_hci_cmd
    test eax, eax
    jnz .out
    lea r12, [rel ubt_keys]
    xor r13d, r13d
.key:
    cmp r13d, UBT_MAX_KEYS
    jae .enable
    cmp byte [r12 + ubt_key.used], 0
    je .skip
    test byte [r12 + ubt_key.flags], KEY_IRK
    jz .skip
    mov al, [r12 + ubt_key.id_type]
    mov [rsp], al
    mov eax, [r12 + ubt_key.id_addr]
    mov [rsp + 1], eax
    mov ax, [r12 + ubt_key.id_addr + 4]
    mov [rsp + 5], ax
    movdqu xmm0, [r12 + ubt_key.irk]
    movdqu [rsp + 7], xmm0
    movdqu xmm0, [rel ubt_local_irk]
    movdqu [rsp + 23], xmm0
    mov rdi, rbx
    mov esi, HCI_LE_ADD_RESOLVING
    mov rdx, rsp
    mov ecx, 39
    call ubt_hci_cmd
    test eax, eax
    jnz .out
.skip:
    add r12, ubt_key_size
    inc r13d
    jmp .key
.enable:
    mov byte [rsp], 1
    mov rdi, rbx
    mov esi, HCI_LE_RESOLUTION_ON
    mov rdx, rsp
    mov ecx, 1
    call ubt_hci_cmd
.out:
    pxor xmm0, xmm0
    movdqu [rsp + 7], xmm0
    movdqu [rsp + 23], xmm0
    add rsp, 48
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_UBT_GAP_PRIVACY_ASM
