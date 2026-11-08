; =============================================================================
; Utkarsha OS — lib/ubt/sm/sec.asm — security, whichever the link
; =============================================================================
;   ubt_pair(conn)                  secure the link: encrypt with a bond, or pair
;   ubt_pair_confirm(conn, yes)     the user's answer to UBT_GAP_CONFIRM or
;                                   UBT_GAP_JUST_WORKS
;   ubt_pair_passkey(conn, value)   ... to UBT_GAP_PASSKEY
;   ubt_sec_event(adapter, ev, len) from GAP: encryption, key requests,
;                                   pairing events
;   ubt_sec_tick(adapter)           timeouts (from ubt_service)
;   ubt_layers_free(conn)           a link gone: what the upper layers kept
;
; LE goes to the Security Manager (sm/le.asm), BR/EDR to Secure Simple
; Pairing in the controller (sm/br.asm).
; =============================================================================

%ifndef LIB_UBT_SM_SEC_ASM
%define LIB_UBT_SM_SEC_ASM

section .text

global ubt_pair
ubt_pair:
    cmp byte [rdi + ubt_conn.type], UBT_LINK_LE
    je ubt_smp_pair
    jmp ubt_br_pair

global ubt_pair_confirm
ubt_pair_confirm:
    cmp byte [rdi + ubt_conn.type], UBT_LINK_LE
    je ubt_smp_confirm
    jmp ubt_br_confirm

global ubt_pair_passkey
ubt_pair_passkey:
    cmp byte [rdi + ubt_conn.type], UBT_LINK_LE
    je ubt_smp_passkey
    jmp ubt_br_passkey

; -----------------------------------------------------------------------------
; ubt_sec_event — RDI = adapter, RSI = event, EDX = length
; -----------------------------------------------------------------------------
global ubt_sec_event
ubt_sec_event:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    movzx eax, byte [r12]
    cmp eax, HCI_EV_ENCRYPT_CHANGE
    je .encrypt
    cmp eax, HCI_EV_KEY_REFRESH
    je .refresh
    cmp eax, HCI_EV_LE_META
    je .le
    ; the rest is BR/EDR pairing
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call ubt_br_event
    jmp .out
.encrypt:
    ; status, handle, on
    cmp r13d, 2 + 4
    jb .out
    mov rdi, rbx
    movzx esi, word [r12 + 3]
    call ubt_conn_find
    test rax, rax
    jz .out
    mov rdi, rax
    movzx esi, byte [r12 + 2]
    movzx edx, byte [r12 + 5]
    jmp .to_link
.refresh:
    ; status, handle: encrypted with the new key
    cmp r13d, 2 + 3
    jb .out
    mov rdi, rbx
    movzx esi, word [r12 + 3]
    call ubt_conn_find
    test rax, rax
    jz .out
    mov rdi, rax
    movzx esi, byte [r12 + 2]
    mov edx, 1
.to_link:
    cmp byte [rdi + ubt_conn.type], UBT_LINK_LE
    jne .br_encrypt
    call ubt_smp_encrypted
    jmp .out
.br_encrypt:
    call ubt_br_encrypted
    jmp .out
.le:
    ; LTK Request: handle, Rand, EDIV
    cmp r13d, 2 + 13
    jb .out
    cmp byte [r12 + 2], HCI_LE_EV_LTK_REQUEST
    jne .out
    mov rdi, rbx
    movzx esi, word [r12 + 3]
    call ubt_conn_find
    test rax, rax
    jz .out
    mov rdi, rax
    lea rsi, [r12 + 3]
    call ubt_smp_ltk_request
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ubt_sec_tick — RDI = adapter: pairing timeouts
global ubt_sec_tick
ubt_sec_tick:
    push rbx
    mov rbx, rdi
    call ubt_now
    test rax, rax
    jz .out
    push rax
    sub rsp, 8
    mov rdi, rbx
    mov rsi, rax
    call ubt_smp_tick
    mov rsi, [rsp + 8]
    mov rdi, rbx
    call ubt_att_tick
    add rsp, 16
.out:
    pop rbx
    ret

; ubt_layers_free — RDI = a conn going away: pairing state given back
global ubt_layers_free
ubt_layers_free:
    push rbx
    mov rbx, rdi
    call ubt_smp_free
    mov rdi, rbx
    call ubt_br_free
    mov rdi, rbx
    call ubt_att_free
    pop rbx
    ret

%endif ; LIB_UBT_SM_SEC_ASM
