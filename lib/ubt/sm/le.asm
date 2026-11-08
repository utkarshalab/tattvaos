; =============================================================================
; Utkarsha OS — lib/ubt/sm/le.asm — LE Security Manager (SMP)
; =============================================================================
;   ubt_smp_pair(conn)          central: encrypt with a bond, or pair;
;                               peripheral: ask the central (Security Request)
;   ubt_smp_confirm(conn, yes), ubt_smp_passkey(conn, value)   the user's say
;   ubt_smp_recv(conn, pdu, len)          SMP on fixed CID 6
;   ubt_smp_ltk_request(conn, ev)         the controller asks for a key
;   ubt_smp_encrypted(conn, status, on)   Encryption Change
;   ubt_smp_tick(adapter, now)            the 30-second SMP timeout
;
; Pairing both ways: LE legacy (Just Works, passkey entry) and LE Secure
; Connections (Just Works, numeric comparison, passkey entry in 20 rounds;
; P-256 keys from the random hook). The association model comes from both
; sides' IO capabilities and MITM flags. Then encryption (the STK or LTK),
; and key distribution: LTK, EDIV and Rand (legacy), IRK and identity
; address, CSRK, kept in the bond store when both sides bond. The user is
; asked through adapter.gap_fn (UBT_GAP_CONFIRM, _PASSKEY, _SHOW,
; _JUST_WORKS) and told the end (UBT_GAP_PAIRED, status 0 or the reason).
;
; Values on the air are least significant octet first; the crypto
; functions take them most significant first, so they are turned around
; on the way in and out.
; =============================================================================

%ifndef LIB_UBT_SM_LE_ASM
%define LIB_UBT_SM_LE_ASM

%define SMP_CID             6
%define SMP_TIMEOUT_MS      30000

; PDUs
%define SMP_PAIR_REQ        0x01
%define SMP_PAIR_RSP        0x02
%define SMP_CONFIRM         0x03
%define SMP_RANDOM          0x04
%define SMP_FAILED          0x05
%define SMP_ENC_INFO        0x06
%define SMP_CENTRAL_ID      0x07
%define SMP_ID_INFO         0x08
%define SMP_ID_ADDR         0x09
%define SMP_SIGN_INFO       0x0A
%define SMP_SEC_REQ         0x0B
%define SMP_PUBKEY          0x0C
%define SMP_CHECK           0x0D
%define SMP_KEYPRESS        0x0E

; AuthReq
%define SMP_AUTH_BOND       0x01
%define SMP_AUTH_MITM       0x04
%define SMP_AUTH_SC         0x08

; key distribution
%define SMP_DIST_ENC        0x01
%define SMP_DIST_ID         0x02
%define SMP_DIST_SIGN       0x04

; Pairing Failed reasons
%define SMP_E_PASSKEY       0x01
%define SMP_E_AUTH          0x03
%define SMP_E_CONFIRM       0x04
%define SMP_E_NOT_SUPPORTED 0x05
%define SMP_E_KEY_SIZE      0x06
%define SMP_E_COMMAND       0x07
%define SMP_E_UNSPECIFIED   0x08
%define SMP_E_INVALID       0x0A
%define SMP_E_DHKEY         0x0B
%define SMP_E_NUMERIC       0x0C
%define SMP_E_TIMEOUT       0x100       ; ours: no answer in 30 s (not sent)

; association models
%define SMP_JW              0
%define SMP_NC              1           ; numeric comparison
%define SMP_PK_SHOW         2           ; passkey: we show it
%define SMP_PK_ENTER        3           ; passkey: the user types it here

; where pairing is: what comes next from the peer
%define ST_RSP              1
%define ST_PUBKEY           2
%define ST_CONFIRM          3
%define ST_RANDOM           4
%define ST_CHECK            5
%define ST_ENC              6
%define ST_KEYS             7
%define ST_DEAD             8           ; timed out: no more SMP on this link
%define ST_REENC            9           ; encrypting with a bond

struc ubt_smp
    .state:         resb 1
    .role:          resb 1          ; 0 initiator (central), 1 responder
    .model:         resb 1
    .sc:            resb 1
    .round:         resb 1          ; passkey entry round, 0-19
    .user_ok:       resb 1          ; the user agreed (or nothing to ask)
    .wait_user:     resb 1
    .have_key:      resb 1          ; the passkey (TK) is known
    .have_confirm:  resb 1          ; the peer's confirm came
    .sent_confirm:  resb 1
    .have_check:    resb 1          ; the peer's DHKey check came
    .dist_local:    resb 1          ; keys we still send
    .dist_peer:     resb 1          ; keys we still wait for
    .key_size:      resb 1
    .bond:          resb 1          ; both sides bond
    .pad:           resb 1
    .passkey:       resd 1
    .pad2:          resd 1
    .deadline:      resq 1
    .preq:          resb 8          ; the Pairing Request and Response PDUs
    .pres:          resb 8
    .a7:            resb 8          ; initiator: type, address (most
    .b7:            resb 8          ; significant first); responder
    .tk:            resb 16         ; legacy TK, most significant first
    .lrand:         resb 16         ; our random, on-air order
    .rrand:         resb 16         ; theirs
    .rconfirm:      resb 16         ; their confirm
    .rcheck:        resb 16         ; their DHKey check
    .ltk:           resb 16         ; STK or LTK, on-air order
    .mackey:        resb 16         ; most significant first
    .dhkey:         resb 32         ; most significant first
    .priv:          resb 32         ; our private key, big-endian
    .lpub:          resb 64         ; public keys, on-air order
    .rpub:          resb 64
    .key:           resb ubt_key_size   ; what pairing gathers, saved at the end
endstruc

; what the user is asked or told (gap_fn's record)
struc ubt_pairing
    .conn:          resq 1
    .value:         resd 1          ; the number or passkey
    .status:        resd 1          ; UBT_GAP_PAIRED: 0, or the reason
    .addr:          resb 6
    .addr_type:     resb 1
    .le:            resb 1
endstruc

section .bss
alignb 8
global ubt_random_fn
ubt_random_fn:      resq 1          ; (buffer, length) → EAX = 0 when filled
global ubt_local_irk
ubt_local_irk:      resb 16         ; ours, made on first use
global ubt_local_csrk
ubt_local_csrk:     resb 16
ubt_local_keys:     resd 1          ; 1: they are made
global ubt_smp_debug
ubt_smp_debug:      resd 1          ; tests: the last DHKey and LTK seen (no use else)

section .rodata
global ubt_smp_layout
ubt_smp_layout:
    dd ubt_smp_size, ubt_smp.state, ubt_smp.model, ubt_smp.sc, ubt_smp.ltk
    dd ubt_smp.dhkey, ubt_key_size, ubt_key.ltk, ubt_key.flags, ubt_pairing_size

section .text

; -----------------------------------------------------------------------------
; ubt_random — RDI = buffer, ESI = length → CF = 1 when there is no source
; -----------------------------------------------------------------------------
global ubt_random
ubt_random:
    mov rax, [rel ubt_random_fn]
    test rax, rax
    jz .none
    sub rsp, 8
    call rax
    add rsp, 8
    test eax, eax
    jnz .none
    clc
    ret
.none:
    stc
    ret

; ubt_rev — RDI = destination, RSI = source, ECX = length: reversed
ubt_rev:
    test ecx, ecx
    jz .out
.byte:
    mov al, [rsi + rcx - 1]
    mov [rdi], al
    inc rdi
    dec ecx
    jnz .byte
.out:
    ret

; ubt_local_keys_make — our IRK and CSRK, once → CF = 1 without randomness
ubt_local_keys_make:
    cmp dword [rel ubt_local_keys], 0
    jne .have
    sub rsp, 8
    lea rdi, [rel ubt_local_irk]
    mov esi, 32                         ; both
    call ubt_random
    lea rsp, [rsp + 8]
    jc .out
    mov dword [rel ubt_local_keys], 1
.have:
    clc
.out:
    ret

; ---- the helpers below: RBX = conn, R12 = its SMP state -----------------

; smp_send — EDI = code, RSI = data, EDX = length (64 at most): one PDU out,
; the timeout running again
smp_send:
    push r13
    sub rsp, 80
    mov [rsp], dil
    mov r13d, edx
    lea rdi, [rsp + 1]
    mov ecx, edx
    rep movsb
    mov rdi, rbx
    mov esi, SMP_CID
    mov rdx, rsp
    lea ecx, [r13d + 1]
    call l2cap_frame
    call smp_restart_timer
    add rsp, 80
    pop r13
    ret

smp_restart_timer:
    sub rsp, 8
    call ubt_now
    add rsp, 8
    test rax, rax
    jz .none
    add rax, SMP_TIMEOUT_MS
.none:
    mov [r12 + ubt_smp.deadline], rax
    ret

; smp_tell — ESI = UBT_GAP_*, EDX = value, ECX = status: the user hears of it
smp_tell:
    sub rsp, 40
    mov [rsp + ubt_pairing.conn], rbx
    mov [rsp + ubt_pairing.value], edx
    mov [rsp + ubt_pairing.status], ecx
    mov eax, [rbx + ubt_conn.peer]
    mov [rsp + ubt_pairing.addr], eax
    mov ax, [rbx + ubt_conn.peer + 4]
    mov [rsp + ubt_pairing.addr + 4], ax
    mov al, [rbx + ubt_conn.peer_type]
    mov [rsp + ubt_pairing.addr_type], al
    mov byte [rsp + ubt_pairing.le], 1
    mov rdi, [rbx + ubt_conn.adapter]
    mov rdx, rsp
    call ubt_gap_tell
    add rsp, 40
    ret

; smp_fail — EDI = reason: Pairing Failed sent (unless the reason is ours
; alone), the user told, the state given back
smp_fail:
    push r13
    sub rsp, 16
    mov r13d, edi
    cmp r13d, 0xFF
    ja .tell
    mov [rsp], r13b
    mov edi, SMP_FAILED
    mov rsi, rsp
    mov edx, 1
    call smp_send
.tell:
    mov edi, r13d
    call smp_end
    add rsp, 16
    pop r13
    ret

; smp_end — EDI = status (0 paired): the user told, the state freed
smp_end:
    push r13
    mov r13d, edi
    mov esi, UBT_GAP_PAIRED
    xor edx, edx
    mov ecx, r13d
    call smp_tell
    call smp_free
    pop r13
    ret

; smp_free: the state wiped and given back
global ubt_smp_free
ubt_smp_free:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, [rbx + ubt_conn.smp]
    test r12, r12
    jz .out
    call smp_free
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret
smp_free:
    sub rsp, 8
    mov rdi, r12
    mov ecx, ubt_smp_size
    xor eax, eax
    rep stosb
    mov rdi, r12
    mov esi, ubt_smp_size
    mov edx, 8
    call usb_free
    mov qword [rbx + ubt_conn.smp], 0
    add rsp, 8
    ret

; smp_new — RBX = conn, EDI = role → R12 = fresh state (0: no memory)
smp_new:
    push r13
    mov r13d, edi
    mov edi, ubt_smp_size
    mov esi, 8
    call usb_alloc
    mov r12, rax
    test rax, rax
    jz .out
    mov [rbx + ubt_conn.smp], rax
    mov [r12 + ubt_smp.role], r13b
    mov byte [r12 + ubt_smp.key_size], 16
    ; A is the initiator, B the responder: type, then the address turned
    mov rdi, [rbx + ubt_conn.adapter]
    lea r8, [r12 + ubt_smp.a7]          ; ours
    lea r9, [r12 + ubt_smp.b7]          ; theirs
    test r13d, r13d
    jz .ours
    xchg r8, r9
.ours:
    mov byte [r8], 0                    ; public
    lea rsi, [rdi + ubt_adapter.bdaddr]
    lea rdi, [r8 + 1]
    mov ecx, 6
    call ubt_rev
    mov al, [rbx + ubt_conn.peer_type]
    mov [r9], al
    lea rsi, [rbx + ubt_conn.peer]
    lea rdi, [r9 + 1]
    mov ecx, 6
    call ubt_rev
    call smp_restart_timer
.out:
    pop r13
    ret

; smp_our_auth → AL = our AuthReq
smp_our_auth:
    mov rax, [rbx + ubt_conn.adapter]
    xor ecx, ecx
    cmp byte [rax + ubt_adapter.bondable], 0
    je .mitm
    or ecx, SMP_AUTH_BOND
.mitm:
    cmp byte [rax + ubt_adapter.io_cap], 3      ; no input, no output
    je .sc
    or ecx, SMP_AUTH_MITM
.sc:
    cmp byte [rax + ubt_adapter.legacy], 0
    jne .auth
    or ecx, SMP_AUTH_SC
.auth:
    mov eax, ecx
    ret

; smp_agree — after the Request and Response: SC or legacy, the key sizes,
; which keys go each way, the model, the passkey to show
; → CF = 1 with EDI = the reason pairing cannot go on
smp_agree:
    push r13
    push r14
    sub rsp, 8
    movzx eax, byte [r12 + ubt_smp.preq + 3]
    and al, [r12 + ubt_smp.pres + 3]
    test al, SMP_AUTH_SC
    setnz byte [r12 + ubt_smp.sc]
    test al, SMP_AUTH_BOND
    setnz byte [r12 + ubt_smp.bond]
    mov rax, [rbx + ubt_conn.adapter]
    mov edi, SMP_E_AUTH
    cmp byte [r12 + ubt_smp.sc], 0
    jne .size
    cmp byte [rax + ubt_adapter.sc_only], 0
    jne .bad
.size:
    ; the smaller maximum key size, at least 7
    movzx ecx, byte [r12 + ubt_smp.preq + 4]
    movzx edx, byte [r12 + ubt_smp.pres + 4]
    cmp ecx, edx
    jbe .min
    mov ecx, edx
.min:
    mov edi, SMP_E_KEY_SIZE
    cmp ecx, 7
    jb .bad
    cmp ecx, 16
    ja .bad
    mov [r12 + ubt_smp.key_size], cl
    ; keys each way: what the Response agreed (the link key bit not ours)
    movzx ecx, byte [r12 + ubt_smp.pres + 5]   ; the initiator's
    movzx edx, byte [r12 + ubt_smp.pres + 6]   ; the responder's
    and ecx, 7
    and edx, 7
    cmp byte [r12 + ubt_smp.sc], 0
    je .dist
    and ecx, ~SMP_DIST_ENC              ; SC: the LTK is made, not sent
    and edx, ~SMP_DIST_ENC
.dist:
    cmp byte [r12 + ubt_smp.role], 0
    je .initiator
    xchg ecx, edx
.initiator:
    mov [r12 + ubt_smp.dist_local], cl
    mov [r12 + ubt_smp.dist_peer], dl
    ; the model
    call smp_choose
    mov [r12 + ubt_smp.model], al
    mov byte [r12 + ubt_smp.user_ok], 1
    cmp eax, SMP_JW
    jne .not_jw
    ; Just Works: TK 0; the user may be asked to allow it
    mov byte [r12 + ubt_smp.have_key], 1
    mov rax, [rbx + ubt_conn.adapter]
    cmp qword [rax + ubt_adapter.gap_fn], 0
    je .done
    mov byte [r12 + ubt_smp.user_ok], 0
    jmp .done
.not_jw:
    cmp eax, SMP_NC
    jne .passkey
    mov byte [r12 + ubt_smp.user_ok], 0
    mov byte [r12 + ubt_smp.have_key], 1
    jmp .done
.passkey:
    cmp eax, SMP_PK_SHOW
    je .show
    ; entering it: the user is asked (their time does not run out)
    mov byte [r12 + ubt_smp.wait_user], 1
    mov esi, UBT_GAP_PASSKEY
    xor edx, edx
    xor ecx, ecx
    call smp_tell
    jmp .done
.show:
    ; a passkey of six digits, shown here
    lea rdi, [r12 + ubt_smp.passkey]
    mov esi, 4
    call ubt_random
    mov edi, SMP_E_UNSPECIFIED
    jc .bad
    mov eax, [r12 + ubt_smp.passkey]
    xor edx, edx
    mov ecx, 1000000
    div ecx
    mov [r12 + ubt_smp.passkey], edx
    call smp_set_tk
    mov esi, UBT_GAP_SHOW
    mov edx, [r12 + ubt_smp.passkey]
    xor ecx, ecx
    call smp_tell
.done:
    ; legacy Just Works: the user is asked now (SC asks after the nonces)
    cmp byte [r12 + ubt_smp.sc], 0
    jne .ok
    cmp byte [r12 + ubt_smp.model], SMP_JW
    jne .ok
    call smp_ask_user
.ok:
    clc
    jmp .out
.bad:
    stc
.out:
    lea rsp, [rsp + 8]
    pop r14
    pop r13
    ret

; smp_set_tk — the passkey as the TK (most significant first) → have_key
smp_set_tk:
    pxor xmm0, xmm0
    movdqu [r12 + ubt_smp.tk], xmm0
    mov eax, [r12 + ubt_smp.passkey]
    bswap eax
    mov [r12 + ubt_smp.tk + 12], eax
    mov byte [r12 + ubt_smp.have_key], 1
    ret

; smp_choose → EAX = the model: from the IO capability table of the
; specification (Vol 3 Part H 2.3.5.1); Just Works when neither side asks
; for MITM protection
smp_choose:
    movzx eax, byte [r12 + ubt_smp.preq + 3]
    or al, [r12 + ubt_smp.pres + 3]
    test al, SMP_AUTH_MITM
    jz .jw
    ; ours and theirs
    mov rax, [rbx + ubt_conn.adapter]
    movzx ecx, byte [rax + ubt_adapter.io_cap]      ; local
    lea rdx, [r12 + ubt_smp.pres + 1]
    cmp byte [r12 + ubt_smp.role], 0
    je .remote
    lea rdx, [r12 + ubt_smp.preq + 1]
.remote:
    movzx edx, byte [rdx]
    cmp ecx, 4
    ja .jw
    cmp edx, 4
    ja .jw
    imul eax, edx, 5
    add eax, ecx
    lea r8, [rel smp_table_legacy]
    cmp byte [r12 + ubt_smp.sc], 0
    je .look
    lea r8, [rel smp_table_sc]
.look:
    movzx eax, byte [r8 + rax]
    cmp eax, 4                          ; both may type: the initiator shows
    jne .out
    mov eax, SMP_PK_SHOW
    cmp byte [r12 + ubt_smp.role], 0
    je .out
    mov eax, SMP_PK_ENTER
.out:
    ret
.jw:
    xor eax, eax
    ret

section .rodata
; [remote][local]: 0 Just Works, 1 numeric comparison, 2 show, 3 enter,
; 4 both keyboards with displays (legacy: the initiator shows)
; IO: 0 display only, 1 display yes/no, 2 keyboard only, 3 none,
; 4 keyboard and display
smp_table_legacy:
    db 0, 0, 3, 0, 3
    db 0, 0, 3, 0, 3
    db 2, 2, 3, 0, 2
    db 0, 0, 0, 0, 0
    db 2, 2, 3, 0, 4
smp_table_sc:
    db 0, 0, 3, 0, 3
    db 0, 1, 3, 0, 1
    db 2, 2, 3, 0, 2
    db 0, 0, 0, 0, 0
    db 2, 1, 3, 0, 1
section .text

; ---- the crypto, in the order the specification writes values ------------

; smp_f4 — RDI = U's public key, RSI = V's (on-air, 64), RDX = nonce (on
; air), ECX = Z, R8 = out (on air, 16)
smp_f4:
    push r13
    push r14
    push r15
    sub rsp, 96                         ; U, V, X, out
    mov r13, rsi
    mov r14, rdx
    mov r15, r8
    mov [rsp + 88], ecx
    mov rsi, rdi
    mov rdi, rsp
    push rcx
    mov ecx, 32
    call ubt_rev
    pop rcx
    lea rdi, [rsp + 32]
    mov rsi, r13
    mov ecx, 32
    call ubt_rev
    lea rdi, [rsp + 64]
    mov rsi, r14
    mov ecx, 16
    call ubt_rev
    mov rdi, rsp
    lea rsi, [rsp + 32]
    lea rdx, [rsp + 64]
    mov ecx, [rsp + 88]
    lea r8, [rsp + 64]
    call ubt_f4
    mov rdi, r15
    lea rsi, [rsp + 64]
    mov ecx, 16
    call ubt_rev
    add rsp, 96
    pop r15
    pop r14
    pop r13
    ret

; smp_na / smp_nb → RAX = the initiator's / responder's nonce (on air)
smp_na:
    lea rax, [r12 + ubt_smp.lrand]
    cmp byte [r12 + ubt_smp.role], 0
    je .out
    lea rax, [r12 + ubt_smp.rrand]
.out:
    ret
smp_nb:
    lea rax, [r12 + ubt_smp.rrand]
    cmp byte [r12 + ubt_smp.role], 0
    je .out
    lea rax, [r12 + ubt_smp.lrand]
.out:
    ret
; smp_pka / smp_pkb → RAX = the initiator's / responder's public key
smp_pka:
    lea rax, [r12 + ubt_smp.lpub]
    cmp byte [r12 + ubt_smp.role], 0
    je .out
    lea rax, [r12 + ubt_smp.rpub]
.out:
    ret
smp_pkb:
    lea rax, [r12 + ubt_smp.rpub]
    cmp byte [r12 + ubt_smp.role], 0
    je .out
    lea rax, [r12 + ubt_smp.lpub]
.out:
    ret

; smp_z → ECX = f4's Z: 0, or 0x80 | this round's passkey bit
smp_z:
    xor ecx, ecx
    movzx eax, byte [r12 + ubt_smp.model]
    cmp eax, SMP_PK_SHOW
    jb .out
    movzx ecx, byte [r12 + ubt_smp.round]
    mov eax, [r12 + ubt_smp.passkey]
    shr eax, cl
    and eax, 1
    or eax, 0x80
    mov ecx, eax
.out:
    ret

; smp_sc_confirm — RDI = out: our SC confirm for this round
;   initiator: f4(PKa, PKb, Na, z), responder: f4(PKb, PKa, Nb, z)
smp_sc_confirm:
    push r13
    mov r13, rdi
    call smp_z
    lea rdi, [r12 + ubt_smp.lpub]
    lea rsi, [r12 + ubt_smp.rpub]
    lea rdx, [r12 + ubt_smp.lrand]
    mov r8, r13
    call smp_f4
    pop r13
    ret

; smp_sc_verify → CF = 1 when the peer's confirm does not match its nonce
smp_sc_verify:
    sub rsp, 24
    call smp_z
    lea rdi, [r12 + ubt_smp.rpub]
    lea rsi, [r12 + ubt_smp.lpub]
    lea rdx, [r12 + ubt_smp.rrand]
    mov r8, rsp
    call smp_f4
    movdqu xmm0, [rsp]
    movdqu xmm1, [r12 + ubt_smp.rconfirm]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    add rsp, 24
    cmp eax, 0xFFFF
    jne .bad
    clc
    ret
.bad:
    stc
    ret

; smp_legacy_confirm — RDI = out, RSI = the random (on air): c1(TK, r, preq,
; pres, iat, rat, ia, ra)
smp_legacy_confirm:
    push r13
    push r14
    sub rsp, 72                         ; r, preq, pres, addresses, out
    mov r13, rdi
    mov r14, rsi
    mov rdi, rsp
    mov rsi, r14
    mov ecx, 16
    call ubt_rev
    lea rdi, [rsp + 16]
    lea rsi, [r12 + ubt_smp.preq]
    mov ecx, 7
    call ubt_rev
    lea rdi, [rsp + 24]
    lea rsi, [r12 + ubt_smp.pres]
    mov ecx, 7
    call ubt_rev
    ; iat, rat, ia, ra
    mov al, [r12 + ubt_smp.a7]
    mov [rsp + 32], al
    mov al, [r12 + ubt_smp.b7]
    mov [rsp + 33], al
    mov eax, [r12 + ubt_smp.a7 + 1]
    mov [rsp + 34], eax
    mov ax, [r12 + ubt_smp.a7 + 5]
    mov [rsp + 38], ax
    mov eax, [r12 + ubt_smp.b7 + 1]
    mov [rsp + 40], eax
    mov ax, [r12 + ubt_smp.b7 + 5]
    mov [rsp + 44], ax
    lea rdi, [r12 + ubt_smp.tk]
    mov rsi, rsp
    lea rdx, [rsp + 16]
    lea rcx, [rsp + 24]
    lea r8, [rsp + 32]
    lea r9, [rsp + 48]
    call ubt_c1
    mov rdi, r13
    lea rsi, [rsp + 48]
    mov ecx, 16
    call ubt_rev
    add rsp, 72
    pop r14
    pop r13
    ret

; smp_legacy_verify → CF = 1 when the peer's confirm and random disagree
smp_legacy_verify:
    sub rsp, 24
    mov rdi, rsp
    lea rsi, [r12 + ubt_smp.rrand]
    call smp_legacy_confirm
    movdqu xmm0, [rsp]
    movdqu xmm1, [r12 + ubt_smp.rconfirm]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    add rsp, 24
    cmp eax, 0xFFFF
    jne .bad
    clc
    ret
.bad:
    stc
    ret

; smp_stk — the STK: s1(TK, Srand, Mrand), cut to the key size, into ltk
smp_stk:
    sub rsp, 56
    call smp_nb                         ; Srand
    mov rsi, rax
    mov rdi, rsp
    mov ecx, 16
    call ubt_rev
    call smp_na                         ; Mrand
    mov rsi, rax
    lea rdi, [rsp + 16]
    mov ecx, 16
    call ubt_rev
    lea rdi, [r12 + ubt_smp.tk]
    mov rsi, rsp
    lea rdx, [rsp + 16]
    lea rcx, [rsp + 32]
    call ubt_s1
    lea rdi, [r12 + ubt_smp.ltk]
    lea rsi, [rsp + 32]
    mov ecx, 16
    call ubt_rev
    call smp_cut_ltk
    add rsp, 56
    ret

; smp_cut_ltk — ltk (on air) cut to the agreed key size
smp_cut_ltk:
    movzx ecx, byte [r12 + ubt_smp.key_size]
.zero:
    cmp ecx, 16
    jae .out
    mov byte [r12 + ubt_smp.ltk + rcx], 0
    inc ecx
    jmp .zero
.out:
    ret

; smp_keys_sc — MacKey and LTK from f5(DHKey, Na, Nb, A, B)
smp_keys_sc:
    push r13
    sub rsp, 64                         ; Na, Nb, out
    call smp_na
    mov rsi, rax
    mov rdi, rsp
    mov ecx, 16
    call ubt_rev
    call smp_nb
    mov rsi, rax
    lea rdi, [rsp + 16]
    mov ecx, 16
    call ubt_rev
    lea rdi, [r12 + ubt_smp.dhkey]
    mov rsi, rsp
    lea rdx, [rsp + 16]
    lea rcx, [r12 + ubt_smp.a7]
    lea r8, [r12 + ubt_smp.b7]
    lea r9, [rsp + 32]
    call ubt_f5
    movdqu xmm0, [rsp + 32]
    movdqu [r12 + ubt_smp.mackey], xmm0
    lea rdi, [r12 + ubt_smp.ltk]
    lea rsi, [rsp + 48]
    mov ecx, 16
    call ubt_rev
    call smp_cut_ltk
    pxor xmm0, xmm0
    movdqu [rsp + 32], xmm0
    movdqu [rsp + 48], xmm0
    add rsp, 64
    pop r13
    ret

; smp_check_value — EDI = 0 for Ea (the initiator's), 1 for Eb; RSI = out
; (on air)
;   Ea = f6(MacKey, Na, Nb, rb, IOcapA, A, B)
;   Eb = f6(MacKey, Nb, Na, ra, IOcapB, B, A)
smp_check_value:
    push r13
    push r14
    sub rsp, 120                        ; N1, N2, r, IOcap (4), A1A2 (14), out
    mov r13d, edi
    mov r14, rsi
    call smp_na
    mov rsi, rax
    mov rdi, rsp
    test r13d, r13d
    jz .n1
    lea rdi, [rsp + 16]
.n1:
    mov ecx, 16
    call ubt_rev
    call smp_nb
    mov rsi, rax
    lea rdi, [rsp + 16]
    test r13d, r13d
    jz .n2
    mov rdi, rsp
.n2:
    mov ecx, 16
    call ubt_rev
    ; r: the passkey for passkey entry, else 0
    pxor xmm0, xmm0
    movdqu [rsp + 32], xmm0
    cmp byte [r12 + ubt_smp.model], SMP_PK_SHOW
    jb .io
    mov eax, [r12 + ubt_smp.passkey]
    bswap eax
    mov [rsp + 44], eax
.io:
    ; IOcap: AuthReq, OOB flag, IO capability of the one checking
    lea rsi, [r12 + ubt_smp.preq]
    test r13d, r13d
    jz .iocap
    lea rsi, [r12 + ubt_smp.pres]
.iocap:
    mov al, [rsi + 3]
    mov [rsp + 48], al
    mov al, [rsi + 2]
    mov [rsp + 49], al
    mov al, [rsi + 1]
    mov [rsp + 50], al
    ; A1 || A2: A then B, or B then A
    lea rsi, [r12 + ubt_smp.a7]
    lea rdx, [r12 + ubt_smp.b7]
    test r13d, r13d
    jz .addrs
    xchg rsi, rdx
.addrs:
    mov eax, [rsi]
    mov [rsp + 56], eax
    mov eax, [rsi + 3]
    mov [rsp + 59], eax
    mov eax, [rdx]
    mov [rsp + 63], eax
    mov eax, [rdx + 3]
    mov [rsp + 66], eax
    sub rsp, 16
    lea rax, [rsp + 16 + 80]
    mov [rsp], rax
    lea rdi, [r12 + ubt_smp.mackey]
    lea rsi, [rsp + 16]
    lea rdx, [rsp + 16 + 16]
    lea rcx, [rsp + 16 + 32]
    lea r8, [rsp + 16 + 48]
    lea r9, [rsp + 16 + 56]
    call ubt_f6
    add rsp, 16
    mov rdi, r14
    lea rsi, [rsp + 80]
    mov ecx, 16
    call ubt_rev
    add rsp, 120
    pop r14
    pop r13
    ret

; smp_keypair — our P-256 key pair → CF = 1 without randomness
smp_keypair:
    push r13
    sub rsp, 64
    mov r13d, 8                         ; tries for a key in range
.try:
    lea rdi, [r12 + ubt_smp.priv]
    mov esi, 32
    call ubt_random
    jc .out
    lea rdi, [r12 + ubt_smp.priv]
    mov rsi, rsp
    call ubt_p256_public
    test eax, eax
    jz .made
    dec r13d
    jnz .try
    stc
    jmp .out
.made:
    lea rdi, [r12 + ubt_smp.lpub]
    mov rsi, rsp
    mov ecx, 32
    call ubt_rev
    lea rdi, [r12 + ubt_smp.lpub + 32]
    lea rsi, [rsp + 32]
    mov ecx, 32
    call ubt_rev
    clc
.out:
    lea rsp, [rsp + 64]
    pop r13
    ret

; smp_dhkey — the shared secret from the peer's key → CF = 1 when its key is
; not a point of the curve (or is ours)
smp_dhkey:
    sub rsp, 72
    lea rsi, [r12 + ubt_smp.rpub]
    lea rdi, [r12 + ubt_smp.lpub]
    mov ecx, 64
    repe cmpsb
    je .bad                             ; our own key sent back
    mov rdi, rsp
    lea rsi, [r12 + ubt_smp.rpub]
    mov ecx, 32
    call ubt_rev
    lea rdi, [rsp + 32]
    lea rsi, [r12 + ubt_smp.rpub + 32]
    mov ecx, 32
    call ubt_rev
    lea rdi, [r12 + ubt_smp.priv]
    mov rsi, rsp
    lea rdx, [r12 + ubt_smp.dhkey]
    call ubt_p256_dh
    test eax, eax
    jnz .bad
    lea rsp, [rsp + 72]
    clc
    ret
.bad:
    lea rsp, [rsp + 72]
    stc
    ret

; smp_nonce — a new random of ours → CF = 1 without randomness
smp_nonce:
    sub rsp, 8
    lea rdi, [r12 + ubt_smp.lrand]
    mov esi, 16
    call ubt_random
    lea rsp, [rsp + 8]
    ret

; ---- steps ------------------------------------------------------------------

; smp_send_confirm — our confirm (legacy or SC) out
smp_send_confirm:
    sub rsp, 24
    cmp byte [r12 + ubt_smp.sc], 0
    jne .sc
    call smp_nonce
    jc .noran
    mov rdi, rsp
    lea rsi, [r12 + ubt_smp.lrand]
    call smp_legacy_confirm
    jmp .send
.sc:
    call smp_nonce
    jc .noran
    mov rdi, rsp
    call smp_sc_confirm
.send:
    mov byte [r12 + ubt_smp.sent_confirm], 1
    mov edi, SMP_CONFIRM
    mov rsi, rsp
    mov edx, 16
    call smp_send
    add rsp, 24
    ret
.noran:
    add rsp, 24
    mov edi, SMP_E_UNSPECIFIED
    jmp smp_fail

; smp_send_random — our random out
smp_send_random:
    mov edi, SMP_RANDOM
    lea rsi, [r12 + ubt_smp.lrand]
    mov edx, 16
    jmp smp_send

; smp_start_enc — the initiator encrypts with ltk (EDIV and Rand 0)
smp_start_enc:
    sub rsp, 40
    mov ax, [rbx + ubt_conn.handle]
    mov [rsp], ax
    xor eax, eax
    mov [rsp + 2], rax                  ; Rand
    mov [rsp + 10], ax                  ; EDIV
    movdqu xmm0, [r12 + ubt_smp.ltk]
    movdqu [rsp + 12], xmm0
    mov byte [r12 + ubt_smp.state], ST_ENC
    mov rdi, [rbx + ubt_conn.adapter]
    mov esi, HCI_LE_START_ENC
    mov rdx, rsp
    mov ecx, 28
    call ubt_hci_async
    pxor xmm0, xmm0
    movdqu [rsp + 12], xmm0
    add rsp, 40
    ret

; smp_send_check — our DHKey check out; the initiator then waits for the
; responder's, the responder for encryption
smp_send_check:
    sub rsp, 24
    call smp_keys_sc
    movzx edi, byte [r12 + ubt_smp.role]
    mov rsi, rsp
    call smp_check_value
    mov edi, SMP_CHECK
    mov rsi, rsp
    mov edx, 16
    call smp_send
    mov byte [r12 + ubt_smp.state], ST_CHECK
    cmp byte [r12 + ubt_smp.role], 0
    je .out
    mov byte [r12 + ubt_smp.state], ST_ENC
.out:
    add rsp, 24
    ret

; smp_verify_check → CF = 1 when the peer's DHKey check is wrong
smp_verify_check:
    sub rsp, 24
    call smp_keys_sc
    movzx edi, byte [r12 + ubt_smp.role]
    xor edi, 1                          ; the other side's
    mov rsi, rsp
    call smp_check_value
    movdqu xmm0, [rsp]
    movdqu xmm1, [r12 + ubt_smp.rcheck]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    add rsp, 24
    cmp eax, 0xFFFF
    jne .bad
    clc
    ret
.bad:
    stc
    ret

; smp_go — after anything changed (a PDU, the user): do what can be done
; now. Called with the state as it is.
smp_go:
    sub rsp, 8
    movzx eax, byte [r12 + ubt_smp.state]
    cmp byte [r12 + ubt_smp.sc], 0
    jne .sc
    ; ---- legacy ----
    cmp eax, ST_CONFIRM
    jne .done
    cmp byte [r12 + ubt_smp.have_key], 0
    je .done
    cmp byte [r12 + ubt_smp.user_ok], 0
    je .done
    cmp byte [r12 + ubt_smp.sent_confirm], 0
    jne .done
    cmp byte [r12 + ubt_smp.role], 0
    je .confirm_first                   ; the initiator goes first
    cmp byte [r12 + ubt_smp.have_confirm], 0
    je .done
    call smp_send_confirm               ; the responder answers
    jmp .to_random
.sc:
    cmp eax, ST_CONFIRM
    je .sc_confirm
    cmp eax, ST_CHECK
    je .sc_check
    jmp .done
.sc_confirm:
    ; passkey entry rounds: the initiator sends first, the responder after
    ; the initiator's confirm; both once the passkey is known
    cmp byte [r12 + ubt_smp.model], SMP_PK_SHOW
    jb .done
    cmp byte [r12 + ubt_smp.have_key], 0
    je .done
    cmp byte [r12 + ubt_smp.sent_confirm], 0
    jne .done
    cmp byte [r12 + ubt_smp.role], 0
    je .confirm_first
    cmp byte [r12 + ubt_smp.have_confirm], 0
    je .done
    call smp_send_confirm
.to_random:
    mov r12, [rbx + ubt_conn.smp]       ; (it fails without randomness)
    test r12, r12
    jz .done
    mov byte [r12 + ubt_smp.state], ST_RANDOM
    jmp .done
.confirm_first:
    call smp_send_confirm
    jmp .done
.sc_check:
    ; the user's yes first; the initiator then sends its check, the
    ; responder answers the initiator's
    cmp byte [r12 + ubt_smp.user_ok], 0
    je .done
    cmp byte [r12 + ubt_smp.role], 0
    jne .responder
    cmp byte [r12 + ubt_smp.sent_confirm], 2    ; (2: our check is out)
    je .done
    mov byte [r12 + ubt_smp.sent_confirm], 2
    call smp_send_check
    jmp .done
.responder:
    cmp byte [r12 + ubt_smp.have_check], 0
    je .done
    call smp_verify_check
    jc .dhkey_bad
    call smp_send_check
    jmp .done
.dhkey_bad:
    mov edi, SMP_E_DHKEY
    call smp_fail
.done:
    add rsp, 8
    ret

; smp_ask_user — the numeric comparison or Just Works question, when due
smp_ask_user:
    cmp byte [r12 + ubt_smp.user_ok], 0
    jne .out
    cmp byte [r12 + ubt_smp.wait_user], 0
    jne .out
    mov byte [r12 + ubt_smp.wait_user], 1
    cmp byte [r12 + ubt_smp.model], SMP_NC
    je .number
    mov esi, UBT_GAP_JUST_WORKS
    xor edx, edx
    xor ecx, ecx
    jmp smp_tell
.number:
    ; g2(PKax, PKbx, Na, Nb) mod 1 000 000
    sub rsp, 104
    call smp_pka
    mov rsi, rax
    mov rdi, rsp
    mov ecx, 32
    call ubt_rev
    call smp_pkb
    mov rsi, rax
    lea rdi, [rsp + 32]
    mov ecx, 32
    call ubt_rev
    call smp_na
    mov rsi, rax
    lea rdi, [rsp + 64]
    mov ecx, 16
    call ubt_rev
    call smp_nb
    mov rsi, rax
    lea rdi, [rsp + 80]
    mov ecx, 16
    call ubt_rev
    mov rdi, rsp
    lea rsi, [rsp + 32]
    lea rdx, [rsp + 64]
    lea rcx, [rsp + 80]
    call ubt_g2
    xor edx, edx
    mov ecx, 1000000
    div ecx
    add rsp, 104
    mov esi, UBT_GAP_CONFIRM
    xor ecx, ecx
    jmp smp_tell
.out:
    ret

; ---- key distribution ---------------------------------------------------------

; smp_send_keys — the keys we give, as agreed
smp_send_keys:
    push r13
    sub rsp, 32
    movzx r13d, byte [r12 + ubt_smp.dist_local]
    test r13d, SMP_DIST_ENC
    jz .id
    ; legacy: an LTK of ours with its EDIV and Rand, cut to the key size
    lea rdi, [r12 + ubt_smp.key + ubt_key.our_ltk]
    mov esi, 16 + 2 + 8
    call ubt_random                     ; (our_ltk, our_ediv... laid out apart)
    lea rdi, [r12 + ubt_smp.key + ubt_key.our_ediv]
    mov esi, 2
    call ubt_random
    lea rdi, [r12 + ubt_smp.key + ubt_key.our_rand]
    mov esi, 8
    call ubt_random
    movzx ecx, byte [r12 + ubt_smp.key_size]
.cut:
    cmp ecx, 16
    jae .cut_done
    mov byte [r12 + ubt_smp.key + ubt_key.our_ltk + rcx], 0
    inc ecx
    jmp .cut
.cut_done:
    or byte [r12 + ubt_smp.key + ubt_key.flags], KEY_OUR_LTK
    mov edi, SMP_ENC_INFO
    lea rsi, [r12 + ubt_smp.key + ubt_key.our_ltk]
    mov edx, 16
    call smp_send
    mov ax, [r12 + ubt_smp.key + ubt_key.our_ediv]
    mov [rsp], ax
    mov rax, [r12 + ubt_smp.key + ubt_key.our_rand]
    mov [rsp + 2], rax
    mov edi, SMP_CENTRAL_ID
    mov rsi, rsp
    mov edx, 10
    call smp_send
.id:
    test r13d, SMP_DIST_ID
    jz .sign
    call ubt_local_keys_make
    mov edi, SMP_ID_INFO
    lea rsi, [rel ubt_local_irk]
    mov edx, 16
    call smp_send
    mov byte [rsp], 0                   ; our public address
    mov rax, [rbx + ubt_conn.adapter]
    mov ecx, [rax + ubt_adapter.bdaddr]
    mov [rsp + 1], ecx
    mov cx, [rax + ubt_adapter.bdaddr + 4]
    mov [rsp + 5], cx
    mov edi, SMP_ID_ADDR
    mov rsi, rsp
    mov edx, 7
    call smp_send
.sign:
    test r13d, SMP_DIST_SIGN
    jz .out
    call ubt_local_keys_make
    mov edi, SMP_SIGN_INFO
    lea rsi, [rel ubt_local_csrk]
    mov edx, 16
    call smp_send
.out:
    mov byte [r12 + ubt_smp.dist_local], 0
    add rsp, 32
    pop r13
    ret

; smp_keys_due — after encryption or a key in: send ours when it is our
; turn, finish when nothing is left
smp_keys_due:
    cmp byte [r12 + ubt_smp.state], ST_KEYS
    jne .out
    ; the responder gives first, the initiator after it has everything
    cmp byte [r12 + ubt_smp.role], 0
    je .initiator
    cmp byte [r12 + ubt_smp.dist_local], 0
    je .wait
    sub rsp, 8
    call smp_send_keys
    add rsp, 8
    jmp .wait
.initiator:
    cmp byte [r12 + ubt_smp.dist_peer], 0
    jne .out
    sub rsp, 8
    call smp_send_keys
    add rsp, 8
.wait:
    cmp byte [r12 + ubt_smp.dist_peer], 0
    jne .out
    jmp smp_complete
.out:
    ret

; smp_complete — paired: the keys kept when both bond, the user told
smp_complete:
    push r13
    push r14
    sub rsp, 8
    cmp byte [r12 + ubt_smp.bond], 0
    je .told
    lea rsi, [rbx + ubt_conn.peer]
    movzx edx, byte [rbx + ubt_conn.peer_type]
    call ubt_key_get
    test rax, rax
    jz .told                            ; the store is full: paired, not kept
    mov r13, rax
    lea r14, [r12 + ubt_smp.key]
    ; what the pairing was
    mov al, [r13 + ubt_key.flags]
    and al, ~(KEY_MITM | KEY_SC)
    cmp byte [r12 + ubt_smp.model], SMP_JW
    je .sc_flag
    or al, KEY_MITM
.sc_flag:
    cmp byte [r12 + ubt_smp.sc], 0
    je .flags
    or al, KEY_SC
.flags:
    mov [r13 + ubt_key.flags], al
    mov al, [r12 + ubt_smp.key_size]
    mov [r13 + ubt_key.key_size], al
    ; SC: the one LTK both ways, EDIV and Rand 0
    cmp byte [r12 + ubt_smp.sc], 0
    je .legacy
    movdqu xmm0, [r12 + ubt_smp.ltk]
    movdqu [r13 + ubt_key.ltk], xmm0
    movdqu [r13 + ubt_key.our_ltk], xmm0
    xor eax, eax
    mov [r13 + ubt_key.ediv], ax
    mov [r13 + ubt_key.our_ediv], ax
    mov [r13 + ubt_key.rand], rax
    mov [r13 + ubt_key.our_rand], rax
    or byte [r13 + ubt_key.flags], KEY_LTK | KEY_OUR_LTK
    jmp .identity
.legacy:
    test byte [r14 + ubt_key.flags], KEY_LTK
    jz .given
    movdqu xmm0, [r14 + ubt_key.ltk]
    movdqu [r13 + ubt_key.ltk], xmm0
    mov ax, [r14 + ubt_key.ediv]
    mov [r13 + ubt_key.ediv], ax
    mov rax, [r14 + ubt_key.rand]
    mov [r13 + ubt_key.rand], rax
    or byte [r13 + ubt_key.flags], KEY_LTK
.given:
    test byte [r14 + ubt_key.flags], KEY_OUR_LTK
    jz .identity
    movdqu xmm0, [r14 + ubt_key.our_ltk]
    movdqu [r13 + ubt_key.our_ltk], xmm0
    mov ax, [r14 + ubt_key.our_ediv]
    mov [r13 + ubt_key.our_ediv], ax
    mov rax, [r14 + ubt_key.our_rand]
    mov [r13 + ubt_key.our_rand], rax
    or byte [r13 + ubt_key.flags], KEY_OUR_LTK
.identity:
    test byte [r14 + ubt_key.flags], KEY_IRK
    jz .sign
    movdqu xmm0, [r14 + ubt_key.irk]
    movdqu [r13 + ubt_key.irk], xmm0
    mov eax, [r14 + ubt_key.id_addr]
    mov [r13 + ubt_key.id_addr], eax
    mov ax, [r14 + ubt_key.id_addr + 4]
    mov [r13 + ubt_key.id_addr + 4], ax
    mov al, [r14 + ubt_key.id_type]
    mov [r13 + ubt_key.id_type], al
    or byte [r13 + ubt_key.flags], KEY_IRK
.sign:
    test byte [r14 + ubt_key.flags], KEY_CSRK
    jz .save
    movdqu xmm0, [r14 + ubt_key.csrk]
    movdqu [r13 + ubt_key.csrk], xmm0
    mov dword [r13 + ubt_key.sign_count], 0
    or byte [r13 + ubt_key.flags], KEY_CSRK
.save:
    mov rdi, r13
    call ubt_key_saved
.told:
    xor edi, edi
    call smp_end
    add rsp, 8
    pop r14
    pop r13
    ret

; -----------------------------------------------------------------------------
; ubt_smp_recv — RDI = conn, RSI = the PDU, EDX = its length
; -----------------------------------------------------------------------------
global ubt_smp_recv
ubt_smp_recv:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r13, rsi
    mov r14d, edx
    mov r12, [rbx + ubt_conn.smp]
    cmp byte [rbx + ubt_conn.type], UBT_LINK_LE
    jne .out
    test r14d, r14d
    jz .out
    test r12, r12
    jz .no_state
    cmp byte [r12 + ubt_smp.state], ST_DEAD
    je .out
.no_state:
    ; each PDU's length
    movzx r15d, byte [r13]
    cmp r15d, SMP_KEYPRESS
    ja .unknown
    test r15d, r15d
    jz .unknown
    lea rax, [rel smp_lengths]
    movzx eax, byte [rax + r15]
    cmp r14d, eax
    jne .invalid
    lea rax, [rel smp_handlers]
    jmp [rax + r15 * 8]
.unknown:
    mov edi, SMP_E_COMMAND
    jmp .refuse
.invalid:
    mov edi, SMP_E_INVALID
.refuse:
    ; without a pairing going on, the answer goes without state
    test r12, r12
    jnz .fail
    sub rsp, 16
    mov [rsp], dil
    mov byte [rsp + 1], SMP_FAILED
    mov al, [rsp]
    mov [rsp + 1], al
    mov byte [rsp], SMP_FAILED
    mov rdi, rbx
    mov esi, SMP_CID
    mov rdx, rsp
    mov ecx, 2
    call l2cap_frame
    add rsp, 16
    jmp .out
.fail:
    call smp_fail
    jmp .out
.unexpected:
    mov edi, SMP_E_UNSPECIFIED
    test r12, r12
    jnz .fail
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- the handlers (jumped to: RBX conn, R12 state or 0, R13 PDU) ----------

.pair_req:
    ; only a peripheral is asked, and only once at a time
    cmp byte [rbx + ubt_conn.role], 1
    jne .not_supported
    test r12, r12
    jz .new_rsp
    cmp byte [r12 + ubt_smp.state], ST_RSP
    jae .unexpected
.new_rsp:
    test r12, r12
    jnz .have_rsp
    mov edi, 1
    call smp_new
    test r12, r12
    jz .out
.have_rsp:
    mov rax, [r13]
    mov [r12 + ubt_smp.preq], rax
    ; our answer: our IO, our AuthReq, 16, the keys both want (when both bond)
    mov byte [r12 + ubt_smp.pres], SMP_PAIR_RSP
    mov rax, [rbx + ubt_conn.adapter]
    mov al, [rax + ubt_adapter.io_cap]
    mov [r12 + ubt_smp.pres + 1], al
    mov byte [r12 + ubt_smp.pres + 2], 0
    call smp_our_auth
    mov [r12 + ubt_smp.pres + 3], al
    mov byte [r12 + ubt_smp.pres + 4], 16
    xor ecx, ecx
    test byte [r12 + ubt_smp.preq + 3], SMP_AUTH_BOND
    jz .rsp_dist
    test al, SMP_AUTH_BOND
    jz .rsp_dist
    mov ecx, 7
.rsp_dist:
    mov edx, ecx
    and cl, [r12 + ubt_smp.preq + 5]
    and dl, [r12 + ubt_smp.preq + 6]
    mov [r12 + ubt_smp.pres + 5], cl
    mov [r12 + ubt_smp.pres + 6], dl
    ; a request we cannot meet is refused before answering
    movzx eax, byte [r12 + ubt_smp.preq + 4]
    cmp eax, 7
    jb .key_size
    cmp eax, 16
    ja .invalid_fail
    call smp_agree
    jc .fail
    mov edi, SMP_PAIR_RSP
    lea rsi, [r12 + ubt_smp.pres + 1]
    mov edx, 6
    call smp_send
    mov byte [r12 + ubt_smp.state], ST_CONFIRM
    cmp byte [r12 + ubt_smp.sc], 0
    je .go
    mov byte [r12 + ubt_smp.state], ST_PUBKEY
    jmp .go
.key_size:
    mov edi, SMP_E_KEY_SIZE
    jmp .fail
.invalid_fail:
    mov edi, SMP_E_INVALID
    jmp .fail
.not_supported:
    mov edi, SMP_E_COMMAND
    jmp .refuse

.pair_rsp:
    test r12, r12
    jz .out
    cmp byte [r12 + ubt_smp.state], ST_RSP
    jne .unexpected
    mov rax, [r13]
    mov [r12 + ubt_smp.pres], rax
    ; keys only the request offered
    mov al, [r12 + ubt_smp.preq + 5]
    and [r12 + ubt_smp.pres + 5], al
    mov al, [r12 + ubt_smp.preq + 6]
    and [r12 + ubt_smp.pres + 6], al
    call smp_agree
    jc .fail
    cmp byte [r12 + ubt_smp.sc], 0
    je .legacy_start
    call smp_keypair
    jc .random_fail
    mov edi, SMP_PUBKEY
    lea rsi, [r12 + ubt_smp.lpub]
    mov edx, 64
    call smp_send
    mov byte [r12 + ubt_smp.state], ST_PUBKEY
    jmp .go
.legacy_start:
    mov byte [r12 + ubt_smp.state], ST_CONFIRM
    jmp .go
.random_fail:
    mov edi, SMP_E_UNSPECIFIED
    jmp .fail

.pubkey:
    test r12, r12
    jz .out
    cmp byte [r12 + ubt_smp.state], ST_PUBKEY
    jne .unexpected
    lea rdi, [r12 + ubt_smp.rpub]
    lea rsi, [r13 + 1]
    mov ecx, 64
    rep movsb
    cmp byte [r12 + ubt_smp.role], 0
    je .pub_dh
    ; the responder answers with its own
    call smp_keypair
    jc .random_fail
    mov edi, SMP_PUBKEY
    lea rsi, [r12 + ubt_smp.lpub]
    mov edx, 64
    call smp_send
.pub_dh:
    call smp_dhkey
    jc .dhkey_fail
    mov byte [r12 + ubt_smp.state], ST_CONFIRM
    cmp byte [r12 + ubt_smp.model], SMP_PK_SHOW
    jae .go                             ; passkey rounds
    cmp byte [r12 + ubt_smp.role], 0
    je .go                              ; the initiator waits for Cb
    ; the responder: Nb and Cb = f4(PKb, PKa, Nb, 0)
    call smp_send_confirm
    mov byte [r12 + ubt_smp.state], ST_RANDOM
    jmp .go
.dhkey_fail:
    mov edi, SMP_E_DHKEY
    jmp .fail

.confirm:
    test r12, r12
    jz .out
    cmp byte [r12 + ubt_smp.state], ST_CONFIRM
    jne .unexpected
    movdqu xmm0, [r13 + 1]
    movdqu [r12 + ubt_smp.rconfirm], xmm0
    mov byte [r12 + ubt_smp.have_confirm], 1
    cmp byte [r12 + ubt_smp.role], 0
    jne .go                             ; the responder answers when it can
    ; the initiator: ours went first (legacy, passkey rounds), or this is
    ; Cb (SC numeric and Just Works); now our random
    cmp byte [r12 + ubt_smp.sc], 0
    je .confirm_ours
    cmp byte [r12 + ubt_smp.model], SMP_PK_SHOW
    jb .confirm_nonce
.confirm_ours:
    cmp byte [r12 + ubt_smp.sent_confirm], 0
    je .unexpected
    jmp .confirm_random
.confirm_nonce:
    call smp_nonce
    jc .random_fail
.confirm_random:
    call smp_send_random
    mov byte [r12 + ubt_smp.state], ST_RANDOM
    jmp .out

.random:
    test r12, r12
    jz .out
    cmp byte [r12 + ubt_smp.state], ST_RANDOM
    jne .unexpected
    movdqu xmm0, [r13 + 1]
    movdqu [r12 + ubt_smp.rrand], xmm0
    cmp byte [r12 + ubt_smp.sc], 0
    jne .random_sc
    ; legacy: their confirm checked, then the STK
    call smp_legacy_verify
    jc .confirm_fail
    cmp byte [r12 + ubt_smp.role], 0
    je .legacy_enc
    call smp_send_random                ; the responder's Srand
    call smp_stk
    mov byte [r12 + ubt_smp.state], ST_ENC
    jmp .out
.legacy_enc:
    call smp_stk
    call smp_start_enc
    jmp .out
.confirm_fail:
    mov edi, SMP_E_CONFIRM
    jmp .fail
.random_sc:
    cmp byte [r12 + ubt_smp.model], SMP_PK_SHOW
    jae .random_pk
    cmp byte [r12 + ubt_smp.role], 0
    jne .random_resp
    call smp_sc_verify                  ; Cb against Nb
    jc .confirm_fail
    jmp .random_check
.random_resp:
    call smp_send_random                ; Nb back
.random_check:
    mov byte [r12 + ubt_smp.state], ST_CHECK
    call smp_ask_user
    mov r12, [rbx + ubt_conn.smp]       ; (the user may have ended it)
    test r12, r12
    jz .out
    jmp .go
.random_pk:
    ; a passkey round: check theirs, the responder answers with its nonce
    call smp_sc_verify
    jc .confirm_fail
    cmp byte [r12 + ubt_smp.role], 0
    je .round_next
    call smp_send_random
.round_next:
    inc byte [r12 + ubt_smp.round]
    mov byte [r12 + ubt_smp.have_confirm], 0
    mov byte [r12 + ubt_smp.sent_confirm], 0
    mov byte [r12 + ubt_smp.state], ST_CONFIRM
    cmp byte [r12 + ubt_smp.round], 20
    jb .go
    mov byte [r12 + ubt_smp.round], 19  ; (Z no longer used)
    mov byte [r12 + ubt_smp.state], ST_CHECK
    jmp .go

.check:
    test r12, r12
    jz .out
    cmp byte [r12 + ubt_smp.state], ST_CHECK
    jne .unexpected
    movdqu xmm0, [r13 + 1]
    movdqu [r12 + ubt_smp.rcheck], xmm0
    mov byte [r12 + ubt_smp.have_check], 1
    cmp byte [r12 + ubt_smp.role], 0
    jne .go
    ; the initiator: Eb checked, then encryption with the LTK
    cmp byte [r12 + ubt_smp.sent_confirm], 2
    jne .unexpected
    call smp_verify_check
    jc .dhkey_fail
    call smp_start_enc
    jmp .out

.failed:
    test r12, r12
    jz .out
    movzx edi, byte [r13 + 1]
    call smp_end
    jmp .out

.sec_req:
    ; a peripheral asks us (central) to secure the link
    cmp byte [rbx + ubt_conn.role], 0
    jne .not_supported
    test r12, r12
    jnz .out                            ; already at it
    mov rdi, rbx
    call ubt_smp_pair
    jmp .out

.key_in:
    ; keys come once encrypted, each only when agreed
    test r12, r12
    jz .out
    cmp byte [r12 + ubt_smp.state], ST_KEYS
    jne .unexpected
    lea r14, [r12 + ubt_smp.key]
    movzx eax, byte [r12 + ubt_smp.dist_peer]
    cmp r15d, SMP_ENC_INFO
    je .enc_info
    cmp r15d, SMP_CENTRAL_ID
    je .central_id
    cmp r15d, SMP_ID_INFO
    je .id_info
    cmp r15d, SMP_ID_ADDR
    je .id_addr
    ; Signing Information
    test eax, SMP_DIST_SIGN
    jz .unexpected
    movdqu xmm0, [r13 + 1]
    movdqu [r14 + ubt_key.csrk], xmm0
    or byte [r14 + ubt_key.flags], KEY_CSRK
    and byte [r12 + ubt_smp.dist_peer], ~SMP_DIST_SIGN
    jmp .keys_next
.enc_info:
    test eax, SMP_DIST_ENC
    jz .unexpected
    movdqu xmm0, [r13 + 1]
    movdqu [r14 + ubt_key.ltk], xmm0
    jmp .out
.central_id:
    test eax, SMP_DIST_ENC
    jz .unexpected
    mov ax, [r13 + 1]
    mov [r14 + ubt_key.ediv], ax
    mov rax, [r13 + 3]
    mov [r14 + ubt_key.rand], rax
    or byte [r14 + ubt_key.flags], KEY_LTK
    and byte [r12 + ubt_smp.dist_peer], ~SMP_DIST_ENC
    jmp .keys_next
.id_info:
    test eax, SMP_DIST_ID
    jz .unexpected
    movdqu xmm0, [r13 + 1]
    movdqu [r14 + ubt_key.irk], xmm0
    jmp .out
.id_addr:
    test eax, SMP_DIST_ID
    jz .unexpected
    mov al, [r13 + 1]
    mov [r14 + ubt_key.id_type], al
    mov eax, [r13 + 2]
    mov [r14 + ubt_key.id_addr], eax
    mov ax, [r13 + 6]
    mov [r14 + ubt_key.id_addr + 4], ax
    or byte [r14 + ubt_key.flags], KEY_IRK
    and byte [r12 + ubt_smp.dist_peer], ~SMP_DIST_ID
.keys_next:
    call smp_restart_timer
    call smp_keys_due
    jmp .out

.keypress:
    jmp .out                            ; a peer typing: nothing to do

.go:
    call smp_go
    jmp .out

section .rodata
; each PDU's length, code included
smp_lengths:    db 0, 7, 7, 17, 17, 2, 17, 11, 17, 8, 17, 2, 65, 17, 2
section .data
align 8
smp_handlers:
    dq ubt_smp_recv.unknown, ubt_smp_recv.pair_req, ubt_smp_recv.pair_rsp
    dq ubt_smp_recv.confirm, ubt_smp_recv.random, ubt_smp_recv.failed
    dq ubt_smp_recv.key_in, ubt_smp_recv.key_in, ubt_smp_recv.key_in
    dq ubt_smp_recv.key_in, ubt_smp_recv.key_in, ubt_smp_recv.sec_req
    dq ubt_smp_recv.pubkey, ubt_smp_recv.check, ubt_smp_recv.keypress
section .text

; -----------------------------------------------------------------------------
; ubt_smp_pair — RDI = an LE conn → EAX = 0, or negative
;   central: a bond's LTK encrypts the link; without one, a Pairing Request
;   peripheral: a Security Request asks the central
; -----------------------------------------------------------------------------
global ubt_smp_pair
ubt_smp_pair:
    push rbx
    push r12
    push r13
    sub rsp, 48
    mov rbx, rdi
    mov eax, -UBT_EBUSY
    cmp qword [rbx + ubt_conn.smp], 0
    jne .out
    cmp byte [rbx + ubt_conn.role], 0
    jne .ask
    ; a bond: encrypt with its LTK
    lea rsi, [rbx + ubt_conn.peer]
    movzx edx, byte [rbx + ubt_conn.peer_type]
    call ubt_key_find
    test rax, rax
    jz .pair
    test byte [rax + ubt_key.flags], KEY_LTK
    jz .pair
    mov r13, rax
    xor edi, edi
    call smp_new
    mov eax, -UBT_ENOMEM
    test r12, r12
    jz .out
    mov byte [r12 + ubt_smp.state], ST_REENC
    mov ax, [rbx + ubt_conn.handle]
    mov [rsp], ax
    mov rax, [r13 + ubt_key.rand]
    mov [rsp + 2], rax
    mov ax, [r13 + ubt_key.ediv]
    mov [rsp + 10], ax
    movdqu xmm0, [r13 + ubt_key.ltk]
    movdqu [rsp + 12], xmm0
    mov rdi, [rbx + ubt_conn.adapter]
    mov esi, HCI_LE_START_ENC
    mov rdx, rsp
    mov ecx, 28
    call ubt_hci_async
    pxor xmm0, xmm0
    movdqu [rsp + 12], xmm0
    xor eax, eax
    jmp .out
.pair:
    xor edi, edi
    call smp_new
    mov eax, -UBT_ENOMEM
    test r12, r12
    jz .out
    mov byte [r12 + ubt_smp.preq], SMP_PAIR_REQ
    mov rax, [rbx + ubt_conn.adapter]
    mov al, [rax + ubt_adapter.io_cap]
    mov [r12 + ubt_smp.preq + 1], al
    mov byte [r12 + ubt_smp.preq + 2], 0
    call smp_our_auth
    mov [r12 + ubt_smp.preq + 3], al
    mov byte [r12 + ubt_smp.preq + 4], 16
    xor ecx, ecx
    test al, SMP_AUTH_BOND
    jz .dist
    mov ecx, 7
.dist:
    mov [r12 + ubt_smp.preq + 5], cl
    mov [r12 + ubt_smp.preq + 6], cl
    mov byte [r12 + ubt_smp.state], ST_RSP
    mov edi, SMP_PAIR_REQ
    lea rsi, [r12 + ubt_smp.preq + 1]
    mov edx, 6
    call smp_send
    xor eax, eax
    jmp .out
.ask:
    call smp_our_auth
    mov [rsp], al
    mov rdi, rbx
    mov esi, SMP_CID
    mov byte [rsp + 1], al
    mov byte [rsp], SMP_SEC_REQ
    mov rdx, rsp
    mov ecx, 2
    call l2cap_frame
    xor eax, eax
.out:
    add rsp, 48
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_smp_confirm — RDI = conn, ESI = 1 yes, 0 no: the numbers match, or
;                   Just Works is allowed
; ubt_smp_passkey — RDI = conn, ESI = the passkey typed (0-999999; more:
;                   cancelled)
; -----------------------------------------------------------------------------
global ubt_smp_confirm
ubt_smp_confirm:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, [rbx + ubt_conn.smp]
    test r12, r12
    jz .out
    cmp byte [r12 + ubt_smp.wait_user], 0
    je .out
    mov byte [r12 + ubt_smp.wait_user], 0
    test esi, esi
    jz .no
    mov byte [r12 + ubt_smp.user_ok], 1
    cmp byte [r12 + ubt_smp.sc], 0
    jne .go
    ; legacy Just Works: the confirms can go now
.go:
    call smp_go
    jmp .out
.no:
    mov edi, SMP_E_NUMERIC
    cmp byte [r12 + ubt_smp.model], SMP_NC
    je .fail
    mov edi, SMP_E_AUTH
.fail:
    call smp_fail
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

global ubt_smp_passkey
ubt_smp_passkey:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, [rbx + ubt_conn.smp]
    test r12, r12
    jz .out
    cmp byte [r12 + ubt_smp.model], SMP_PK_ENTER
    jne .out
    cmp byte [r12 + ubt_smp.have_key], 0
    jne .out
    mov byte [r12 + ubt_smp.wait_user], 0
    cmp esi, 999999
    ja .cancel
    mov [r12 + ubt_smp.passkey], esi
    call smp_restart_timer
    call smp_set_tk
    call smp_go
    jmp .out
.cancel:
    mov edi, SMP_E_PASSKEY
    call smp_fail
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_smp_ltk_request — RDI = conn, RSI = the LTK Request subevent (handle,
;   Rand, EDIV): the pairing's key, a bond's, or a negative reply
; -----------------------------------------------------------------------------
global ubt_smp_ltk_request
ubt_smp_ltk_request:
    push rbx
    push r12
    push r13
    sub rsp, 32
    mov rbx, rdi
    mov r13, rsi
    mov ax, [rbx + ubt_conn.handle]
    mov [rsp], ax
    mov r12, [rbx + ubt_conn.smp]
    test r12, r12
    jz .bond
    cmp byte [r12 + ubt_smp.state], ST_ENC
    jne .bond
    ; pairing: the STK or the SC LTK, asked for with EDIV and Rand 0
    cmp qword [r13 + 2], 0
    jne .negative
    cmp word [r13 + 10], 0
    jne .negative
    movdqu xmm0, [r12 + ubt_smp.ltk]
    jmp .reply
.bond:
    lea rsi, [rbx + ubt_conn.peer]
    movzx edx, byte [rbx + ubt_conn.peer_type]
    call ubt_key_find
    test rax, rax
    jz .negative
    test byte [rax + ubt_key.flags], KEY_OUR_LTK
    jz .negative
    mov rcx, [r13 + 2]
    cmp rcx, [rax + ubt_key.our_rand]
    jne .negative
    mov cx, [r13 + 10]
    cmp cx, [rax + ubt_key.our_ediv]
    jne .negative
    movdqu xmm0, [rax + ubt_key.our_ltk]
.reply:
    movdqu [rsp + 2], xmm0
    mov rdi, [rbx + ubt_conn.adapter]
    mov esi, HCI_LE_LTK_REPLY
    lea rdx, [rsp]
    mov ecx, 18
    call ubt_hci_async
    pxor xmm0, xmm0
    movdqu [rsp + 2], xmm0
    jmp .out
.negative:
    mov rdi, [rbx + ubt_conn.adapter]
    mov esi, HCI_LE_LTK_NEG_REPLY
    lea rdx, [rsp]
    mov ecx, 2
    call ubt_hci_async
.out:
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_smp_encrypted — RDI = an LE conn, ESI = status, EDX = 1 encryption on
; -----------------------------------------------------------------------------
global ubt_smp_encrypted
ubt_smp_encrypted:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r13d, esi
    mov r14d, edx
    mov r12, [rbx + ubt_conn.smp]
    ; how secure the link is now
    mov byte [rbx + ubt_conn.sec], 0
    test r13d, r13d
    jnz .state
    test r14d, r14d
    jz .state
    mov byte [rbx + ubt_conn.sec], 1
    mov byte [rbx + ubt_conn.key_size], 16
    test r12, r12
    jz .from_bond
    cmp byte [r12 + ubt_smp.state], ST_REENC
    je .from_bond
    mov al, [r12 + ubt_smp.key_size]
    mov [rbx + ubt_conn.key_size], al
    cmp byte [r12 + ubt_smp.model], SMP_JW
    je .state
    mov byte [rbx + ubt_conn.sec], 2
    cmp byte [r12 + ubt_smp.sc], 0
    je .state
    mov byte [rbx + ubt_conn.sec], 3
    jmp .state
.from_bond:
    lea rsi, [rbx + ubt_conn.peer]
    movzx edx, byte [rbx + ubt_conn.peer_type]
    call ubt_key_find
    test rax, rax
    jz .state
    mov cl, [rax + ubt_key.key_size]
    mov [rbx + ubt_conn.key_size], cl
    test byte [rax + ubt_key.flags], KEY_MITM
    jz .state
    mov byte [rbx + ubt_conn.sec], 2
    test byte [rax + ubt_key.flags], KEY_SC
    jz .state
    mov byte [rbx + ubt_conn.sec], 3
.state:
    test r12, r12
    jz .out
    cmp byte [r12 + ubt_smp.state], ST_REENC
    je .reenc
    cmp byte [r12 + ubt_smp.state], ST_ENC
    jne .out
    test r13d, r13d
    jnz .enc_failed
    test r14d, r14d
    jz .enc_failed
    mov byte [r12 + ubt_smp.state], ST_KEYS
    call smp_restart_timer
    call smp_keys_due
    jmp .out
.enc_failed:
    mov edi, r13d
    test edi, edi
    jnz .failed_status
    mov edi, SMP_E_UNSPECIFIED
.failed_status:
    or edi, 0x200                       ; ours: the controller's status
    call smp_end
    jmp .out
.reenc:
    ; a bond's key: done, well or not (0x06: the peer lost its key)
    mov edi, r13d
    test edi, edi
    jz .reenc_done
    or edi, 0x200
.reenc_done:
    call smp_end
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_smp_tick — RDI = adapter, RSI = now (ms): pairings past 30 s fail, and
;                no more SMP is taken on their links
; -----------------------------------------------------------------------------
global ubt_smp_tick
ubt_smp_tick:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r13, rdi
    mov r14, rsi
    xor r15d, r15d
.next:
    cmp r15d, UBT_MAX_CONNS
    jae .out
    mov rbx, [r13 + ubt_adapter.conns + r15 * 8]
    inc r15d
    test rbx, rbx
    jz .next
    mov r12, [rbx + ubt_conn.smp]
    test r12, r12
    jz .next
    cmp byte [r12 + ubt_smp.state], ST_DEAD
    je .next
    cmp byte [r12 + ubt_smp.wait_user], 0
    jne .next                           ; the user's time is the user's
    mov rax, [r12 + ubt_smp.deadline]
    test rax, rax
    jz .next
    cmp r14, rax
    jb .next
    ; told, and left dead (the state stays so nothing more is taken)
    mov esi, UBT_GAP_PAIRED
    xor edx, edx
    mov ecx, SMP_E_TIMEOUT
    call smp_tell
    mov byte [r12 + ubt_smp.state], ST_DEAD
    jmp .next
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_UBT_SM_LE_ASM
