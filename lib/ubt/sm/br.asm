; =============================================================================
; Utkarsha OS — lib/ubt/sm/br.asm — BR/EDR pairing (Secure Simple Pairing)
; =============================================================================
;   ubt_br_pair(conn)               authenticate (with a bond's link key, or
;                                   by pairing), then encrypt
;   ubt_br_confirm(conn, yes)       the user's answer: the numbers match /
;                                   Just Works is allowed
;   ubt_br_passkey(conn, value)     the passkey typed (more than 999999:
;                                   cancelled)
;   ubt_br_pin(conn, pin, len)      a legacy PIN (len 0: refused)
;   ubt_br_event(adapter, ev, len)  the controller's pairing events
;   ubt_br_encrypted(conn, status, on), ubt_br_free(conn)
;   ubt_br_oob_local(adapter, out) → HCI status: the controller's C and R
;                                   (P-192 then P-256, 64 bytes) to hand over
;   ubt_br_oob_peer(addr, c, r)     a peer's P-256 C and R, received out of
;                                   band (Secure Simple Pairing uses them)
;
; Secure Connections Only (adapter.sc_only): link keys that are not P-256
; are neither used nor kept, and a pairing that would make one ends the
; link.
;
; The controller does the pairing over the air; the host answers it: link
; keys from the bond store (or "none"), our IO capability and bonding
; wish, the user's confirmation or passkey (or a legacy PIN), and keeps
; the link key it is told of (with its type: authenticated or not, P-192
; or P-256). The side that asked authenticates and then turns encryption
; on; both learn how secure the link is from Encryption Change, and the
; user hears UBT_GAP_PAIRED.
; =============================================================================

%ifndef LIB_UBT_SM_BR_ASM
%define LIB_UBT_SM_BR_ASM

; IO Capability Request Reply's authentication requirements
%define BR_AUTH_MITM        0x01
%define BR_AUTH_GENERAL     0x04        ; general bonding

; out of band
%define HCI_REMOTE_OOB_NEG      0x0433
%define HCI_REMOTE_OOB_EXT_REPLY      0x0445
%define HCI_READ_LOCAL_OOB_EXT  0x0C7D
%define HCI_EV_REMOTE_OOB       0x35
%define OOB_BR                  3       ; an ubt_oob_peers kind: C and R (P-256)

; link key types
%define BR_KEY_UNAUTH_192   4
%define BR_KEY_AUTH_192     5
%define BR_KEY_UNAUTH_256   7
%define BR_KEY_AUTH_256     8

struc ubt_br_pairing
    .asked:         resb 1          ; 1: we authenticate (and then encrypt)
    .remote_io:     resb 1
    .remote_auth:   resb 1
    .wait:          resb 1          ; the user's turn: UBT_GAP_* (0: none)
    .value:         resd 1
    .done:          resb 1          ; told already
    .legacy:        resb 1          ; a PIN pairing (no IO capabilities heard)
    .pad:           resb 6
endstruc

section .text

; br_conn_by_addr — RBX = adapter, RSI = address → RAX = its BR/EDR link, or 0
br_conn_by_addr:
    xor ecx, ecx
.next:
    cmp ecx, UBT_MAX_CONNS
    jae .none
    mov rax, [rbx + ubt_adapter.conns + rcx * 8]
    inc ecx
    test rax, rax
    jz .next
    cmp byte [rax + ubt_conn.type], UBT_LINK_BREDR
    jne .next
    mov edx, [rax + ubt_conn.peer]
    cmp edx, [rsi]
    jne .next
    mov dx, [rax + ubt_conn.peer + 4]
    cmp dx, [rsi + 4]
    jne .next
    ret
.none:
    xor eax, eax
    ret

; br_state — R12 = conn → RAX = its pairing state, made when missing (0: no
; memory)
br_state:
    mov rax, [r12 + ubt_conn.pair]
    test rax, rax
    jnz .out
    sub rsp, 8
    mov edi, ubt_br_pairing_size
    mov esi, 8
    call usb_alloc
    add rsp, 8
    test rax, rax
    jz .out
    mov [r12 + ubt_conn.pair], rax
.out:
    ret

; br_cmd_addr — RBX = adapter, ESI = opcode, RDX = the address, then ECX
; more bytes from R8: sent without waiting
br_cmd_addr:
    sub rsp, 88
    mov eax, [rdx]
    mov [rsp], eax
    mov ax, [rdx + 4]
    mov [rsp + 4], ax
    push rsi
    push rcx
    lea rdi, [rsp + 16 + 6]
    mov rsi, r8
    rep movsb
    pop rcx
    pop rsi
    lea ecx, [rcx + 6]
    mov rdi, rbx
    mov rdx, rsp
    call ubt_hci_async
    pxor xmm0, xmm0
    movdqu [rsp + 6], xmm0
    movdqu [rsp + 22], xmm0
    movdqu [rsp + 38], xmm0
    movdqu [rsp + 54], xmm0
    add rsp, 88
    ret

; br_tell — R12 = conn, ESI = UBT_GAP_*, EDX = value, ECX = status
br_tell:
    sub rsp, 40
    mov [rsp + ubt_pairing.conn], r12
    mov [rsp + ubt_pairing.value], edx
    mov [rsp + ubt_pairing.status], ecx
    mov eax, [r12 + ubt_conn.peer]
    mov [rsp + ubt_pairing.addr], eax
    mov ax, [r12 + ubt_conn.peer + 4]
    mov [rsp + ubt_pairing.addr + 4], ax
    mov byte [rsp + ubt_pairing.addr_type], 0
    mov byte [rsp + ubt_pairing.le], 0
    mov rdi, [r12 + ubt_conn.adapter]
    mov rdx, rsp
    call ubt_gap_tell
    add rsp, 40
    ret

; br_finish — R12 = conn, EDI = status: the user told once, the state freed
br_finish:
    push r13
    mov r13d, edi
    mov rax, [r12 + ubt_conn.pair]
    test rax, rax
    jz .tell
    cmp byte [rax + ubt_br_pairing.done], 0
    jne .free
.tell:
    mov esi, UBT_GAP_PAIRED
    xor edx, edx
    mov ecx, r13d
    call br_tell
.free:
    mov rdi, r12
    call ubt_br_free
    pop r13
    ret

; -----------------------------------------------------------------------------
; ubt_br_pair — RDI = a BR/EDR conn → EAX = 0, or negative
; -----------------------------------------------------------------------------
global ubt_br_pair
ubt_br_pair:
    push rbx
    push r12
    sub rsp, 24
    mov r12, rdi
    mov rbx, [r12 + ubt_conn.adapter]
    call br_state
    mov rcx, rax
    mov eax, -UBT_ENOMEM
    test rcx, rcx
    jz .out
    mov byte [rcx + ubt_br_pairing.asked], 1
    mov ax, [r12 + ubt_conn.handle]
    mov [rsp], ax
    mov rdi, rbx
    mov esi, HCI_AUTH_REQUESTED
    mov rdx, rsp
    mov ecx, 2
    call ubt_hci_async
    xor eax, eax
.out:
    add rsp, 24
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_br_confirm — RDI = conn, ESI = 1 yes / 0 no
; ubt_br_passkey — RDI = conn, ESI = the passkey (more than 999999: no)
; ubt_br_pin     — RDI = conn, RSI = PIN, EDX = length (1-16; 0: refused)
; -----------------------------------------------------------------------------
global ubt_br_confirm
ubt_br_confirm:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    mov rbx, [r12 + ubt_conn.adapter]
    mov rax, [r12 + ubt_conn.pair]
    test rax, rax
    jz .out
    cmp byte [rax + ubt_br_pairing.wait], UBT_GAP_CONFIRM
    je .answer
    cmp byte [rax + ubt_br_pairing.wait], UBT_GAP_JUST_WORKS
    jne .out
.answer:
    mov byte [rax + ubt_br_pairing.wait], 0
    mov ecx, HCI_USER_CONFIRM_REPLY
    test esi, esi
    jnz .send
    mov ecx, HCI_USER_CONFIRM_NEG
.send:
    mov esi, ecx
    lea rdx, [r12 + ubt_conn.peer]
    xor ecx, ecx
    call br_cmd_addr
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

global ubt_br_passkey
ubt_br_passkey:
    push rbx
    push r12
    sub rsp, 24
    mov r12, rdi
    mov rbx, [r12 + ubt_conn.adapter]
    mov rax, [r12 + ubt_conn.pair]
    test rax, rax
    jz .out
    cmp byte [rax + ubt_br_pairing.wait], UBT_GAP_PASSKEY
    jne .out
    mov byte [rax + ubt_br_pairing.wait], 0
    lea rdx, [r12 + ubt_conn.peer]
    cmp esi, 999999
    ja .no
    mov [rsp], esi
    mov r8, rsp
    mov ecx, 4
    mov esi, HCI_USER_PASSKEY_REPLY
    call br_cmd_addr
    jmp .out
.no:
    mov esi, HCI_USER_PASSKEY_NEG
    xor ecx, ecx
    call br_cmd_addr
.out:
    add rsp, 24
    pop r12
    pop rbx
    ret

global ubt_br_pin
ubt_br_pin:
    push rbx
    push r12
    sub rsp, 40
    mov r12, rdi
    mov rbx, [r12 + ubt_conn.adapter]
    mov rax, [r12 + ubt_conn.pair]
    test rax, rax
    jz .out
    cmp byte [rax + ubt_br_pairing.wait], UBT_GAP_PIN
    jne .out
    mov byte [rax + ubt_br_pairing.wait], 0
    test edx, edx
    jz .no
    cmp edx, 16
    ja .no
    ; length, then 16 bytes of PIN (zero padded)
    pxor xmm0, xmm0
    movdqu [rsp + 1], xmm0
    mov [rsp], dl
    lea rdi, [rsp + 1]
    mov ecx, edx
    rep movsb
    mov r8, rsp
    mov ecx, 17
    mov esi, HCI_PIN_REPLY
    lea rdx, [r12 + ubt_conn.peer]
    call br_cmd_addr
    pxor xmm0, xmm0
    movdqu [rsp + 1], xmm0
    jmp .out
.no:
    mov esi, HCI_PIN_NEG_REPLY
    lea rdx, [r12 + ubt_conn.peer]
    xor ecx, ecx
    call br_cmd_addr
.out:
    add rsp, 40
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_br_event — RDI = adapter, RSI = event, EDX = length
; -----------------------------------------------------------------------------
global ubt_br_event
ubt_br_event:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 80
    mov rbx, rdi
    mov r13, rsi
    mov r14d, edx
    movzx r15d, byte [r13]
    cmp r15d, HCI_EV_AUTH_COMPLETE
    je .auth_complete
    cmp r15d, HCI_EV_SSP_COMPLETE
    jne .by_addr
    cmp r14d, 2 + 7
    jb .out
    lea rsi, [r13 + 3]                  ; (its status comes first)
    call br_conn_by_addr
    mov r12, rax
    jmp .ssp_complete
.by_addr:
    cmp r14d, 2 + 6
    jb .out
    ; the rest name the peer by address first
    lea rsi, [r13 + 2]
    call br_conn_by_addr
    mov r12, rax
    cmp r15d, HCI_EV_LINK_KEY_REQUEST
    je .key_request
    cmp r15d, HCI_EV_LINK_KEY_NOTIFY
    je .key_notify
    cmp r15d, HCI_EV_IO_CAP_REQUEST
    je .io_request
    cmp r15d, HCI_EV_IO_CAP_RESPONSE
    je .io_response
    cmp r15d, HCI_EV_USER_CONFIRM
    je .confirm
    cmp r15d, HCI_EV_USER_PASSKEY
    je .passkey
    cmp r15d, HCI_EV_PASSKEY_NOTIFY
    je .show
    cmp r15d, HCI_EV_PIN_REQUEST
    je .pin
    cmp r15d, HCI_EV_REMOTE_OOB
    je .oob
    jmp .out

.oob:
    ; the peer's C and R as received out of band, or none
    lea rdi, [r13 + 2]
    xor esi, esi
    call oob_find
    test rax, rax
    jz .oob_none
    cmp byte [rax + 2], OOB_BR
    jne .oob_none
    ; C192, R192 (none), C256, R256
    pxor xmm0, xmm0
    movdqu [rsp], xmm0
    movdqu [rsp + 16], xmm0
    movdqu xmm0, [rax + 32]
    movdqu [rsp + 32], xmm0            ; (C is kept second: see ubt_br_oob_peer)
    movdqu xmm0, [rax + 16]
    movdqu [rsp + 48], xmm0
    mov r8, rsp
    mov ecx, 64
    mov esi, HCI_REMOTE_OOB_EXT_REPLY
    lea rdx, [r13 + 2]
    call br_cmd_addr
    jmp .out
.oob_none:
    mov esi, HCI_REMOTE_OOB_NEG
    lea rdx, [r13 + 2]
    xor ecx, ecx
    call br_cmd_addr
    jmp .out

.key_request:
    ; a bond's link key, or none
    lea rsi, [r13 + 2]
    xor edx, edx
    call ubt_key_find
    test rax, rax
    jz .no_key
    test byte [rax + ubt_key.flags], KEY_LINK
    jz .no_key
    cmp byte [rbx + ubt_adapter.sc_only], 0
    je .key_ok
    cmp byte [rax + ubt_key.link_type], BR_KEY_UNAUTH_256
    jb .no_key                          ; SC only: P-256 keys only
.key_ok:
    lea r8, [rax + ubt_key.link_key]
    mov ecx, 16
    mov esi, HCI_LINK_KEY_REPLY
    lea rdx, [r13 + 2]
    call br_cmd_addr
    jmp .out
.no_key:
    mov esi, HCI_LINK_KEY_NEG_REPLY
    lea rdx, [r13 + 2]
    xor ecx, ecx
    call br_cmd_addr
    jmp .out

.io_request:
    ; ours: IO capability, no OOB data, general bonding when bondable,
    ; MITM when we can show or type something
    test r12, r12
    jz .io_refuse
    call br_state
    test rax, rax
    jz .io_refuse
    mov rax, [r12 + ubt_conn.adapter]
    mov cl, [rax + ubt_adapter.io_cap]
    cmp cl, 4
    jbe .io_ok
    mov cl, 3
.io_ok:
    mov [rsp], cl
    push rcx
    push rax
    lea rdi, [r13 + 2]
    xor esi, esi
    call oob_find
    test rax, rax
    setnz dl
    pop rax
    pop rcx
    mov [rsp + 1], dl
    xor edx, edx
    cmp byte [rax + ubt_adapter.bondable], 0
    je .io_mitm
    mov edx, BR_AUTH_GENERAL
.io_mitm:
    cmp cl, 3
    je .io_auth
    or edx, BR_AUTH_MITM
.io_auth:
    mov [rsp + 2], dl
    mov r8, rsp
    mov ecx, 3
    mov esi, HCI_IO_CAP_REPLY
    lea rdx, [r13 + 2]
    call br_cmd_addr
    jmp .out
.io_refuse:
    mov byte [rsp], 0x18                ; pairing not allowed
    mov r8, rsp
    mov ecx, 1
    mov esi, HCI_IO_CAP_NEG_REPLY
    lea rdx, [r13 + 2]
    call br_cmd_addr
    jmp .out

.io_response:
    ; the peer's IO capability and wishes
    test r12, r12
    jz .out
    cmp r14d, 2 + 9
    jb .out
    call br_state
    test rax, rax
    jz .out
    mov cl, [r13 + 8]
    mov [rax + ubt_br_pairing.remote_io], cl
    mov cl, [r13 + 10]
    mov [rax + ubt_br_pairing.remote_auth], cl
    jmp .out

.confirm:
    ; a number to compare, or Just Works: the user asked (with no hook: yes)
    test r12, r12
    jz .out
    cmp r14d, 2 + 10
    jb .out
    call br_state
    test rax, rax
    jz .out
    mov r15, rax
    mov rax, [r12 + ubt_conn.adapter]
    cmp qword [rax + ubt_adapter.gap_fn], 0
    jne .ask
    mov esi, HCI_USER_CONFIRM_REPLY
    lea rdx, [r13 + 2]
    xor ecx, ecx
    call br_cmd_addr
    jmp .out
.ask:
    ; a number when both sides can show and confirm one
    mov esi, UBT_GAP_JUST_WORKS
    mov rax, [r12 + ubt_conn.adapter]
    movzx ecx, byte [rax + ubt_adapter.io_cap]
    movzx edx, byte [r15 + ubt_br_pairing.remote_io]
    cmp ecx, 1
    je .ask_remote
    cmp ecx, 4
    jne .ask_send
.ask_remote:
    cmp edx, 1
    je .ask_number
    cmp edx, 4
    jne .ask_send
.ask_number:
    mov esi, UBT_GAP_CONFIRM
.ask_send:
    mov [r15 + ubt_br_pairing.wait], sil
    mov edx, [r13 + 8]
    mov [r15 + ubt_br_pairing.value], edx
    xor ecx, ecx
    call br_tell
    jmp .out

.passkey:
    test r12, r12
    jz .out
    call br_state
    test rax, rax
    jz .out
    mov byte [rax + ubt_br_pairing.wait], UBT_GAP_PASSKEY
    mov esi, UBT_GAP_PASSKEY
    xor edx, edx
    xor ecx, ecx
    call br_tell
    jmp .out

.show:
    test r12, r12
    jz .out
    cmp r14d, 2 + 10
    jb .out
    mov esi, UBT_GAP_SHOW
    mov edx, [r13 + 8]
    xor ecx, ecx
    call br_tell
    jmp .out

.pin:
    ; a peer without Secure Simple Pairing: the user is asked for a PIN
    test r12, r12
    jz .pin_refuse
    call br_state
    test rax, rax
    jz .pin_refuse
    mov rcx, [r12 + ubt_conn.adapter]
    cmp qword [rcx + ubt_adapter.gap_fn], 0
    je .pin_refuse
    mov byte [rax + ubt_br_pairing.wait], UBT_GAP_PIN
    mov byte [rax + ubt_br_pairing.legacy], 1
    mov esi, UBT_GAP_PIN
    xor edx, edx
    xor ecx, ecx
    call br_tell
    jmp .out
.pin_refuse:
    mov esi, HCI_PIN_NEG_REPLY
    lea rdx, [r13 + 2]
    xor ecx, ecx
    call br_cmd_addr
    jmp .out

.key_notify:
    ; the new link key: kept when both sides bond
    test r12, r12
    jz .out
    cmp r14d, 2 + 23
    jb .out
    mov rax, [r12 + ubt_conn.adapter]
    cmp byte [rax + ubt_adapter.sc_only], 0
    je .key_any
    cmp byte [r13 + 24], BR_KEY_UNAUTH_256
    jae .key_any
    ; SC only and an older key: not kept, the link ended
    mov ax, [r12 + ubt_conn.handle]
    mov [rsp], ax
    mov byte [rsp + 2], 0x05            ; authentication failure
    mov rdi, rbx
    mov esi, HCI_DISCONNECT
    mov rdx, rsp
    mov ecx, 3
    call ubt_hci_async
    mov edi, 0x05
    call br_finish
    jmp .out
.key_any:
    mov rax, [r12 + ubt_conn.adapter]
    cmp byte [rax + ubt_adapter.bondable], 0
    je .out
    mov rax, [r12 + ubt_conn.pair]
    test rax, rax
    jz .key_keep
    cmp byte [rax + ubt_br_pairing.legacy], 0
    jne .key_keep                       ; a PIN pairing: no wishes heard
    cmp byte [rax + ubt_br_pairing.remote_auth], 2
    jb .out                             ; they did not want to bond
.key_keep:
    lea rsi, [r13 + 2]
    xor edx, edx
    call ubt_key_get
    test rax, rax
    jz .out
    mov r15, rax
    movdqu xmm0, [r13 + 8]
    movdqu [r15 + ubt_key.link_key], xmm0
    movzx ecx, byte [r13 + 24]
    mov [r15 + ubt_key.link_type], cl
    mov byte [r15 + ubt_key.key_size], 16
    mov al, [r15 + ubt_key.flags]
    or al, KEY_LINK
    and al, ~(KEY_MITM | KEY_SC)
    cmp ecx, BR_KEY_AUTH_192
    je .mitm
    cmp ecx, BR_KEY_AUTH_256
    jne .sc
.mitm:
    or al, KEY_MITM
.sc:
    cmp ecx, BR_KEY_UNAUTH_256
    jb .flags
    or al, KEY_SC
.flags:
    mov [r15 + ubt_key.flags], al
    mov rdi, r15
    call ubt_key_saved
    jmp .out

.ssp_complete:
    ; a failure ends it here; success waits for authentication and encryption
    test r12, r12
    jz .out
    movzx edi, byte [r13 + 2]
    test edi, edi
    jz .out
    mov rax, [r12 + ubt_conn.pair]
    test rax, rax
    jz .out
    cmp byte [rax + ubt_br_pairing.asked], 0
    jne .out                            ; Authentication Complete tells
    call br_finish
    jmp .out

.auth_complete:
    ; status, handle: the side that asked turns encryption on, or is told
    cmp r14d, 2 + 3
    jb .out
    mov rdi, rbx
    movzx esi, word [r13 + 3]
    call ubt_conn_find
    test rax, rax
    jz .out
    mov r12, rax
    mov rax, [r12 + ubt_conn.pair]
    test rax, rax
    jz .out
    cmp byte [rax + ubt_br_pairing.asked], 0
    je .out
    movzx edi, byte [r13 + 2]
    test edi, edi
    jnz .auth_failed
    mov ax, [r12 + ubt_conn.handle]
    mov [rsp], ax
    mov byte [rsp + 2], 1
    mov rdi, rbx
    mov esi, HCI_SET_CONN_ENCRYPT
    mov rdx, rsp
    mov ecx, 3
    call ubt_hci_async
    jmp .out
.auth_failed:
    call br_finish
.out:
    add rsp, 80
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_br_encrypted — RDI = conn, ESI = status, EDX = on: the link's security
;   from its bond; the user told when this ends a pairing of ours
; -----------------------------------------------------------------------------
global ubt_br_encrypted
ubt_br_encrypted:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi
    mov r13d, esi
    mov r14d, edx
    mov byte [r12 + ubt_conn.sec], 0
    test r13d, r13d
    jnz .tell
    test r14d, r14d
    jz .tell
    mov byte [r12 + ubt_conn.sec], 1
    mov byte [r12 + ubt_conn.key_size], 16
    lea rsi, [r12 + ubt_conn.peer]
    xor edx, edx
    call ubt_key_find
    test rax, rax
    jz .tell
    test byte [rax + ubt_key.flags], KEY_MITM
    jz .tell
    mov byte [r12 + ubt_conn.sec], 2
    test byte [rax + ubt_key.flags], KEY_SC
    jz .tell
    mov byte [r12 + ubt_conn.sec], 3
.tell:
    mov rax, [r12 + ubt_conn.pair]
    test rax, rax
    jz .out
    mov edi, r13d
    test edi, edi
    jz .done
    or edi, 0x200
.done:
    call br_finish
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ubt_br_enable — RDI = adapter: Secure Simple Pairing and Secure
; Connections host support on (sent without waiting; a controller without
; them says so and pairs the older way)
global ubt_br_enable
ubt_br_enable:
    push rbx
    sub rsp, 16
    mov rbx, rdi
    mov byte [rsp], 1
    mov esi, HCI_WRITE_SSP_MODE
    mov rdx, rsp
    mov ecx, 1
    call ubt_hci_async
    mov byte [rsp], 1
    mov rdi, rbx
    mov esi, HCI_WRITE_SC_SUPPORT
    mov rdx, rsp
    mov ecx, 1
    call ubt_hci_async
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_br_oob_local — RDI = adapter, RSI = out (64: C192, R192, C256, R256)
;   → EAX = HCI status, or negative
; ubt_br_oob_peer — RDI = address, RSI = its C (P-256), RDX = its R
;   → EAX = 0, or -1 (no room)
; -----------------------------------------------------------------------------
global ubt_br_oob_local
ubt_br_oob_local:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov esi, HCI_READ_LOCAL_OOB_EXT
    xor edx, edx
    xor ecx, ecx
    call ubt_hci_cmd
    test eax, eax
    jnz .out
    mov rdi, r12
    lea rsi, [rbx + ubt_adapter.wait_buf]
    mov ecx, 64
    rep movsb
    xor eax, eax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

global ubt_br_oob_peer
ubt_br_oob_peer:
    ; kept as (R, C) like LE's (r, commitment)
    mov rcx, rsi
    xor esi, esi
    mov r8d, OOB_BR
    jmp oob_store

; ubt_br_free — RDI = conn: its pairing state given back
global ubt_br_free
ubt_br_free:
    mov rax, rdi
    mov rdi, [rax + ubt_conn.pair]
    test rdi, rdi
    jz .out
    mov qword [rax + ubt_conn.pair], 0
    mov esi, ubt_br_pairing_size
    mov edx, 8
    jmp usb_free
.out:
    ret

%endif ; LIB_UBT_SM_BR_ASM
