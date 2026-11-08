; =============================================================================
; Utkarsha OS — lib/ubt/l2cap/credit.asm — credit-based channels
; =============================================================================
;   l2cap_connect_ecred(conn, psm, count, ops, user, chans) → how many asked
;                       for: up to five enhanced channels in one request
;   l2cap_reconfigure(chan, mtu)    a larger MTU of ours on an enhanced channel
;                                   (ops.event gets L2CAP_EV_RECONF, EDX = the
;                                   result, when the answer comes)
;   l2cap_cred_new(chan), l2cap_cred_free(chan)
;   l2cap_cred_conn_req(chan)       the request (enhanced: the whole group)
;   l2cap_cred_send(chan, sdu, len), l2cap_cred_recv(chan, payload, len)
;
; LE Credit Based Flow Control mode (LE links) and Enhanced Credit Based
; Flow Control mode (LE, and BR/EDR when the peer says it does it). Data
; goes in K-frames: the first of an SDU starts with its length, none is
; longer than the receiver's MPS, and each takes one of the credits the
; receiver gave. We give CRED_CREDITS and top them up when half are used;
; a peer that sends without a credit, beyond our MPS or MTU, or gives us
; more than 65535 credits loses the channel. Signalling: LE Credit Based
; Connection, Flow Control Credit, Credit Based Connection (up to five
; channels) and Reconfigure (MTU never smaller; MPS smaller only for a
; single channel).
; =============================================================================

%ifndef LIB_UBT_L2CAP_CREDIT_ASM
%define LIB_UBT_L2CAP_CREDIT_ASM

struc l2cap_cred
    .tx_credits:    resd 1          ; K-frames the peer still takes
    .rx_credits:    resd 1          ; K-frames we still take
    .mps:           resd 1          ; the peer's: payload per K-frame
    .new_mtu:       resd 1          ; asked for in a reconfiguration (0: none)
    .index:         resd 1          ; its place in the request it went in
    .pad:           resd 1
    .leader:        resq 1          ; the first channel of that request
    .txq:           resq 1          ; K-frames waiting for credits
    .txq_tail:      resq 1
    .sdu:           resq 1          ; the SDU being put together
    .sdu_size:      resd 1          ; ... its block's size
    .sdu_len:       resd 1
    .sdu_got:       resd 1
    .pad2:          resd 1
endstruc

section .text

; -----------------------------------------------------------------------------
; l2cap_cred_new — RDI = chan: its credit state (a group of one)
; Output: EAX = 0, or -UBT_ENOMEM
; -----------------------------------------------------------------------------
global l2cap_cred_new
l2cap_cred_new:
    push rbx
    mov rbx, rdi
    mov edi, l2cap_cred_size
    mov esi, 8
    call usb_alloc                      ; (zeroed)
    test rax, rax
    jz .nomem
    mov [rax + l2cap_cred.leader], rbx
    mov dword [rax + l2cap_cred.rx_credits], CRED_CREDITS
    mov [rbx + l2cap_chan.cred], rax
    xor eax, eax
    pop rbx
    ret
.nomem:
    mov eax, -UBT_ENOMEM
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_cred_free — RDI = chan: queued K-frames, a half-built SDU and the
;                   state given back
; -----------------------------------------------------------------------------
global l2cap_cred_free
l2cap_cred_free:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, [rbx + l2cap_chan.cred]
    test r12, r12
    jz .out
    mov r13, [r12 + l2cap_cred.txq]
.queued:
    test r13, r13
    jz .sdu
    mov rdi, r13
    mov r13, [r13 + l2cap_seg.next]
    call l2cap_seg_free
    jmp .queued
.sdu:
    mov rdi, [r12 + l2cap_cred.sdu]
    mov esi, [r12 + l2cap_cred.sdu_size]
    mov edx, 8
    call usb_free
    mov rdi, r12
    mov esi, l2cap_cred_size
    mov edx, 8
    call usb_free
    mov qword [rbx + l2cap_chan.cred], 0
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_connect_ecred — RDI = conn, ESI = PSM, EDX = count (1-5), RCX = ops,
;                       R8 = user, R9 = where the channels go (count of them)
; Output: EAX = how many were made; they are asked for in one request
; -----------------------------------------------------------------------------
global l2cap_connect_ecred
l2cap_connect_ecred:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24                         ; [rsp] user, [+8] the first channel
    mov r12, rdi
    mov r13d, esi
    mov r14d, edx
    mov r15, rcx
    mov [rsp], r8
    mov rbp, r9
    mov qword [rsp + 8], 0
    cmp r14d, CRED_MAX_CHANS
    jbe .count
    mov r14d, CRED_MAX_CHANS
.count:
    xor ebx, ebx
.make:
    cmp ebx, r14d
    jae .made
    mov rdi, r12
    mov esi, r13d
    mov edx, L2CAP_MODE_ECRED
    mov rcx, r15
    mov r8, [rsp]
    call l2cap_chan_make
    test rax, rax
    jz .made
    mov [rbp + rbx * 8], rax
    cmp qword [rsp + 8], 0
    jne .member
    mov [rsp + 8], rax
.member:
    mov rcx, [rax + l2cap_chan.cred]
    mov rdx, [rsp + 8]
    mov [rcx + l2cap_cred.leader], rdx
    mov [rcx + l2cap_cred.index], ebx
    inc ebx
    jmp .make
.made:
    test ebx, ebx
    jz .out
    cmp byte [r12 + ubt_conn.info_state], 2
    jne .out                            ; asked when the peer's answer comes
    mov rdi, [rsp + 8]
    call l2cap_cred_conn_req
.out:
    mov eax, ebx
    add rsp, 24
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_cred_conn_req — RDI = an outgoing credit-based channel waiting to
;                       ask: LE Credit Based Connection Request, or the
;                       Credit Based Connection Request for its whole group
; -----------------------------------------------------------------------------
global l2cap_cred_conn_req
l2cap_cred_conn_req:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 72                         ; [rsp] the request, [+24] the group
    mov rbx, rdi
    mov r12, [rbx + l2cap_chan.conn]
    mov r13, [rbx + l2cap_chan.cred]
    mov r13, [r13 + l2cap_cred.leader]
    ; the group, in its order
    xor r14d, r14d                      ; found
    xor r15d, r15d                      ; the place looked for
.place:
    cmp r15d, CRED_MAX_CHANS
    jae .gathered
    mov rax, [r12 + ubt_conn.adapter]
    xor ecx, ecx
.scan:
    cmp ecx, UBT_MAX_CHANS
    jae .next_place
    mov rdx, [rax + ubt_adapter.chans + rcx * 8]
    inc ecx
    test rdx, rdx
    jz .scan
    cmp [rdx + l2cap_chan.conn], r12
    jne .scan
    cmp byte [rdx + l2cap_chan.state], L2CAP_WAIT_INFO
    jne .scan
    mov r8, [rdx + l2cap_chan.cred]
    test r8, r8
    jz .scan
    cmp [r8 + l2cap_cred.leader], r13
    jne .scan
    cmp [r8 + l2cap_cred.index], r15d
    jne .scan
    mov [rsp + 24 + r14 * 8], rdx
    inc r14d
.next_place:
    inc r15d
    jmp .place
.gathered:
    test r14d, r14d
    jz .out
    ; enhanced on BR/EDR: only to a peer that said it does it
    cmp byte [rbx + l2cap_chan.mode], L2CAP_MODE_ECRED
    jne .ask
    cmp byte [r12 + ubt_conn.type], UBT_LINK_LE
    je .ask
    test dword [r12 + ubt_conn.ext_features], L2CAP_FEAT_ECRED
    jnz .ask
    xor r15d, r15d
.refuse:
    mov rdi, [rsp + 24 + r15 * 8]
    mov esi, L2CAP_EV_REFUSED
    mov edx, L2CAP_WHY_MODE
    call l2cap_close
    inc r15d
    cmp r15d, r14d
    jb .refuse
    jmp .out
.ask:
    mov rdi, r12
    call l2cap_next_ident
    mov ebp, r8d
    ; every channel of the group waits for the one answer
    xor r15d, r15d
.wait:
    mov rdi, [rsp + 24 + r15 * 8]
    mov byte [rdi + l2cap_chan.state], L2CAP_WAIT_CONNECT
    mov [rdi + l2cap_chan.ident], bpl
    call l2cap_sig_wait
    inc r15d
    cmp r15d, r14d
    jb .wait
    ; SPSM, our MTU, MPS and credits, then the CIDs
    mov ax, [rbx + l2cap_chan.psm]
    mov [rsp], ax
    mov ax, [rbx + l2cap_chan.imtu]
    mov [rsp + 2], ax
    mov word [rsp + 4], CRED_MPS
    mov word [rsp + 6], CRED_CREDITS
    xor r15d, r15d
.cids:
    mov rdi, [rsp + 24 + r15 * 8]
    mov ax, [rdi + l2cap_chan.scid]
    mov [rsp + 8 + r15 * 2], ax
    inc r15d
    cmp r15d, r14d
    jb .cids
    lea ecx, [r14d * 2 + 8]
    mov esi, L2CAP_ECRED_CONN_REQ
    cmp byte [rbx + l2cap_chan.mode], L2CAP_MODE_ECRED
    je .send
    mov esi, L2CAP_LE_CONN_REQ          ; the same fields, one CID
.send:
    mov rdi, r12
    mov r8d, ebp
    mov rdx, rsp
    call l2cap_sig_send
.out:
    add rsp, 72
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; l2cap_cred_set — RDI = chan, ESI = their CID, EDX = their MTU, ECX = their
; MPS, R8D = their credits: open (its user is told by the caller)
l2cap_cred_set:
    mov [rdi + l2cap_chan.dcid], si
    mov [rdi + l2cap_chan.omtu], dx
    mov rax, [rdi + l2cap_chan.cred]
    mov [rax + l2cap_cred.mps], ecx
    mov [rax + l2cap_cred.tx_credits], r8d
    mov dword [rax + l2cap_cred.rx_credits], CRED_CREDITS
    mov byte [rdi + l2cap_chan.state], L2CAP_OPEN
    mov qword [rdi + l2cap_chan.deadline], 0
    ret

; l2cap_cred_push — RBX = chan, R12 = its state: queued K-frames out while
; the peer's credits last
l2cap_cred_push:
    push r13
.next:
    cmp dword [r12 + l2cap_cred.tx_credits], 0
    je .out
    mov r13, [r12 + l2cap_cred.txq]
    test r13, r13
    jz .out
    mov rdi, [rbx + l2cap_chan.conn]
    movzx esi, word [rbx + l2cap_chan.dcid]
    lea rdx, [r13 + l2cap_seg.data]
    mov ecx, [r13 + l2cap_seg.len]
    call l2cap_frame
    test eax, eax
    js .out                             ; kept for the next try
    dec dword [r12 + l2cap_cred.tx_credits]
    mov rax, [r13 + l2cap_seg.next]
    mov [r12 + l2cap_cred.txq], rax
    test rax, rax
    jnz .free
    mov qword [r12 + l2cap_cred.txq_tail], 0
.free:
    mov rdi, r13
    call l2cap_seg_free
    jmp .next
.out:
    pop r13
    ret

; -----------------------------------------------------------------------------
; l2cap_cred_send — RDI = chan, RSI = SDU, EDX = length → EAX = 0 or negative:
;                   cut to the peer's MPS, queued, sent as credits allow
; -----------------------------------------------------------------------------
global l2cap_cred_send
l2cap_cred_send:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24                         ; [rsp] first K-frame, [+8] last
    mov rbx, rdi
    mov r12, [rbx + l2cap_chan.cred]
    mov r13, rsi
    mov r14d, edx
    mov eax, -UBT_EIO
    test r12, r12
    jz .out
    movzx ecx, word [rbx + l2cap_chan.omtu]
    cmp r14d, ecx
    ja .out
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    xor r15d, r15d                      ; offset in the SDU
.segment:
    mov ebp, [r12 + l2cap_cred.mps]
    mov ecx, r14d
    sub ecx, r15d                       ; what is left
    xor edx, edx                        ; SDU length bytes in this one
    test r15d, r15d
    jnz .room
    mov edx, 2
    sub ebp, 2
.room:
    cmp ecx, ebp
    jbe .make
    mov ecx, ebp
.make:
    push rcx
    push rdx
    lea edi, [rcx + rdx + l2cap_seg_size]
    mov esi, 8
    call usb_alloc
    pop rdx
    pop rcx
    test rax, rax
    jz .nomem
    lea r8d, [rcx + rdx + l2cap_seg_size]
    mov [rax + l2cap_seg.size], r8d
    lea r8d, [rcx + rdx]
    mov [rax + l2cap_seg.len], r8d
    lea rdi, [rax + l2cap_seg.data]
    test edx, edx
    jz .copy
    mov [rdi], r14w                     ; the SDU's length first
    add rdi, 2
.copy:
    lea rsi, [r13 + r15]
    add r15d, ecx
    rep movsb
    mov rcx, [rsp + 8]
    test rcx, rcx
    jz .first
    mov [rcx + l2cap_seg.next], rax
    jmp .linked
.first:
    mov [rsp], rax
.linked:
    mov [rsp + 8], rax
    cmp r15d, r14d
    jb .segment
    ; queued whole
    mov rax, [rsp]
    mov rcx, [r12 + l2cap_cred.txq_tail]
    test rcx, rcx
    jz .empty
    mov [rcx + l2cap_seg.next], rax
    jmp .tail
.empty:
    mov [r12 + l2cap_cred.txq], rax
.tail:
    mov rax, [rsp + 8]
    mov [r12 + l2cap_cred.txq_tail], rax
    call l2cap_cred_push
    xor eax, eax
    jmp .out
.nomem:
    mov r15, [rsp]
.unmake:
    test r15, r15
    jz .nomem_out
    mov rdi, r15
    mov r15, [r15 + l2cap_seg.next]
    call l2cap_seg_free
    jmp .unmake
.nomem_out:
    mov eax, -UBT_ENOMEM
.out:
    add rsp, 24
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; l2cap_cred_deliver — RDI = chan, RSI = SDU, EDX = length: to its user
l2cap_cred_deliver:
    mov rax, [rdi + l2cap_chan.ops]
    test rax, rax
    jz .out
    mov rax, [rax + l2cap_ops.recv]
    test rax, rax
    jz .out
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; l2cap_cred_give — RDI = chan, ESI = credits: Flow Control Credit to the peer
l2cap_cred_give:
    sub rsp, 8
    mov ax, [rdi + l2cap_chan.scid]
    mov [rsp], ax
    mov [rsp + 2], si
    mov rdi, [rdi + l2cap_chan.conn]
    call l2cap_next_ident
    mov esi, L2CAP_LE_CREDITS
    mov rdx, rsp
    mov ecx, 4
    call l2cap_sig_send
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; l2cap_cred_recv — RDI = an open credit-based chan, RSI = a K-frame's
;                   payload, EDX = its length
; -----------------------------------------------------------------------------
global l2cap_cred_recv
l2cap_cred_recv:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, [rbx + l2cap_chan.cred]
    test r12, r12
    jz .drop
    mov r13, rsi
    mov r14d, edx
    ; without a credit, or longer than we take: the peer broke the rules
    cmp dword [r12 + l2cap_cred.rx_credits], 0
    je .broken
    dec dword [r12 + l2cap_cred.rx_credits]
    cmp r14d, CRED_MPS
    ja .broken
    cmp qword [r12 + l2cap_cred.sdu], 0
    jne .more
    ; an SDU's first K-frame: its length first
    cmp r14d, 2
    jb .broken
    movzx r15d, word [r13]
    movzx eax, word [rbx + l2cap_chan.imtu]
    cmp r15d, eax
    ja .broken
    add r13, 2
    sub r14d, 2
    cmp r14d, r15d
    ja .broken
    jb .start
    mov rdi, rbx                        ; whole in one
    mov rsi, r13
    mov edx, r14d
    call l2cap_cred_deliver
    jmp .credits
.start:
    movzx edi, word [rbx + l2cap_chan.imtu]
    mov [r12 + l2cap_cred.sdu_size], edi
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .broken                          ; the rest could not be followed
    mov [r12 + l2cap_cred.sdu], rax
    mov [r12 + l2cap_cred.sdu_len], r15d
    mov dword [r12 + l2cap_cred.sdu_got], 0
.more:
    mov eax, [r12 + l2cap_cred.sdu_got]
    add eax, r14d
    cmp eax, [r12 + l2cap_cred.sdu_len]
    ja .broken                          ; more than the SDU said
    mov rdi, [r12 + l2cap_cred.sdu]
    mov ecx, [r12 + l2cap_cred.sdu_got]
    add rdi, rcx
    mov rsi, r13
    mov ecx, r14d
    rep movsb
    mov [r12 + l2cap_cred.sdu_got], eax
    cmp eax, [r12 + l2cap_cred.sdu_len]
    jb .credits
    mov rdi, rbx
    mov rsi, [r12 + l2cap_cred.sdu]
    mov edx, eax
    call l2cap_cred_deliver
    mov rdi, [r12 + l2cap_cred.sdu]
    mov esi, [r12 + l2cap_cred.sdu_size]
    mov edx, 8
    call usb_free
    mov qword [r12 + l2cap_cred.sdu], 0
.credits:
    ; topped up when half are used
    cmp byte [rbx + l2cap_chan.state], L2CAP_OPEN
    jne .out
    mov esi, CRED_CREDITS
    sub esi, [r12 + l2cap_cred.rx_credits]
    cmp esi, CRED_CREDITS / 2
    jb .out
    mov dword [r12 + l2cap_cred.rx_credits], CRED_CREDITS
    mov rdi, rbx
    call l2cap_cred_give
    jmp .out
.broken:
    mov rdi, rbx
    call l2cap_disconnect
    jmp .out
.drop:
    inc dword [rel l2cap_dropped]
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_reconfigure — RDI = an open enhanced chan, ESI = our new MTU (no
;                     smaller than now) → EAX = 0 or negative
; -----------------------------------------------------------------------------
global l2cap_reconfigure
l2cap_reconfigure:
    push rbx
    sub rsp, 16
    mov rbx, rdi
    mov eax, -UBT_EIO
    cmp byte [rbx + l2cap_chan.mode], L2CAP_MODE_ECRED
    jne .out
    cmp byte [rbx + l2cap_chan.state], L2CAP_OPEN
    jne .out
    movzx ecx, word [rbx + l2cap_chan.imtu]
    cmp esi, ecx
    jb .out                             ; an MTU never shrinks
    cmp esi, 0xFFFF
    ja .out
    mov rax, [rbx + l2cap_chan.cred]
    mov [rax + l2cap_cred.new_mtu], esi
    mov [rsp], si
    mov word [rsp + 2], CRED_MPS
    mov ax, [rbx + l2cap_chan.scid]
    mov [rsp + 4], ax
    mov rdi, rbx
    call l2cap_sig_chan_ident
    mov rdi, [rbx + l2cap_chan.conn]
    mov esi, L2CAP_ECRED_RECONF_REQ
    mov rdx, rsp
    mov ecx, 6
    call l2cap_sig_send
.out:
    add rsp, 16
    pop rbx
    ret

; ---- the signalling handlers: RBX = conn, R12 = data, R13D = length, R14D =
; ---- identifier (from l2cap/sig.asm)

; l2cap_cred_accept — RBX = conn, EDI = PSM, ESI = mode: a new channel for
; the server of that PSM, if it takes that mode → RAX = it, or 0 with EDX =
; the result to give
l2cap_cred_accept:
    push r12
    push r13
    sub rsp, 8
    mov r13d, esi
    call l2cap_server_find
    mov edx, L2CAP_LE_BAD_PSM
    test rax, rax
    jz .fail
    movzx ecx, byte [rax + l2cap_srv.mode]
    cmp ecx, r13d
    jne .fail
    mov r12, rax
    mov rdi, rbx
    call l2cap_chan_new
    mov edx, L2CAP_LE_NO_MEM
    test rax, rax
    jz .fail
    mov r13, rax
    mov rdi, rax
    call l2cap_cred_new
    test eax, eax
    jz .made
    mov rdi, r13
    call l2cap_chan_free
    mov edx, L2CAP_LE_NO_MEM
    jmp .fail
.made:
    mov rax, r13
    mov dx, [r12 + l2cap_srv.psm]
    mov [rax + l2cap_chan.psm], dx
    mov dl, [r12 + l2cap_srv.mode]
    mov [rax + l2cap_chan.mode], dl
    mov rdx, [r12 + l2cap_srv.ops]
    mov [rax + l2cap_chan.ops], rdx
    mov rdx, [r12 + l2cap_srv.user]
    mov [rax + l2cap_chan.user], rdx
    xor edx, edx
    jmp .out
.fail:
    xor eax, eax
.out:
    add rsp, 8
    pop r13
    pop r12
    ret

; LE Credit Based Connection Request: SPSM, MTU, MPS, credits, their CID
l2cap_on_le_conn_req:
    push r15
    push rbp
    sub rsp, 24                         ; [rsp] the response, [+16] chan
    cmp r13d, 10
    jb .out
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], eax
    movzx r15d, word [r12 + 8]
    mov ebp, L2CAP_LE_INVALID_SCID
    cmp r15d, L2CAP_CID_DYN_START
    jb .respond
    cmp r15d, L2CAP_CID_LE_DYN_END
    ja .respond
    mov ebp, L2CAP_LE_SCID_IN_USE
    mov rdi, rbx
    mov esi, r15d
    call l2cap_find_dcid
    test rax, rax
    jnz .respond
    mov ebp, L2CAP_LE_UNACCEPT
    cmp word [r12 + 2], L2CAP_LE_MIN_MTU
    jb .respond
    cmp word [r12 + 4], L2CAP_LE_MIN_MTU
    jb .respond
    cmp word [r12 + 4], 65533
    ja .respond
    movzx edi, word [r12]
    mov esi, L2CAP_MODE_LE_CREDITS
    call l2cap_cred_accept
    mov ebp, edx
    test rax, rax
    jz .respond
    mov [rsp + 16], rax
    mov rdi, rax
    mov esi, r15d
    movzx edx, word [r12 + 2]
    movzx ecx, word [r12 + 4]
    movzx r8d, word [r12 + 6]
    call l2cap_cred_set
    mov rax, [rsp + 16]
    mov dx, [rax + l2cap_chan.scid]
    mov [rsp], dx
    mov dx, [rax + l2cap_chan.imtu]
    mov [rsp + 2], dx
    mov word [rsp + 4], CRED_MPS
    mov word [rsp + 6], CRED_CREDITS
.respond:
    mov [rsp + 8], bp
    mov esi, L2CAP_LE_CONN_RSP
    mov rdx, rsp
    mov ecx, 10
    call l2cap_sig_reply
    test ebp, ebp
    jnz .out
    mov rdi, [rsp + 16]
    mov esi, L2CAP_EV_OPEN
    xor edx, edx
    call l2cap_event
.out:
    add rsp, 24
    pop rbp
    pop r15
    ret

; LE Credit Based Connection Response: their CID, MTU, MPS, credits, result
l2cap_on_le_conn_rsp:
    sub rsp, 8
    cmp r13d, 10
    jb .out
    call l2cap_chan_by_ident
    test rax, rax
    jz .out
    cmp byte [rax + l2cap_chan.state], L2CAP_WAIT_CONNECT
    jne .out
    cmp byte [rax + l2cap_chan.mode], L2CAP_MODE_LE_CREDITS
    jne .out
    movzx edx, word [r12 + 8]
    test edx, edx
    jnz .refused
    movzx esi, word [r12]
    mov [rax + l2cap_chan.dcid], si
    cmp esi, L2CAP_CID_DYN_START
    jb .bad
    cmp esi, L2CAP_CID_LE_DYN_END
    ja .bad
    cmp word [r12 + 2], L2CAP_LE_MIN_MTU
    jb .bad
    cmp word [r12 + 4], L2CAP_LE_MIN_MTU
    jb .bad
    mov [rsp], rax
    mov rdi, rax
    movzx edx, word [r12 + 2]
    movzx ecx, word [r12 + 4]
    movzx r8d, word [r12 + 6]
    call l2cap_cred_set
    mov rdi, [rsp]
    mov esi, L2CAP_EV_OPEN
    xor edx, edx
    call l2cap_event
    jmp .out
.bad:
    ; values no channel can use: closed again at once
    mov rdi, rax
    call l2cap_disconnect
    jmp .out
.refused:
    mov rdi, rax
    mov esi, L2CAP_EV_REFUSED
    call l2cap_close
.out:
    add rsp, 8
    ret

; Flow Control Credit: the sender's CID (ours for them), credits
l2cap_on_credits:
    push rbx
    push r12
    sub rsp, 8
    cmp r13d, 4
    jb .out
    mov rdi, rbx
    movzx esi, word [r12]
    call l2cap_find_dcid
    test rax, rax
    jz .out
    cmp byte [rax + l2cap_chan.state], L2CAP_OPEN
    jne .out
    mov rcx, [rax + l2cap_chan.cred]
    test rcx, rcx
    jz .out
    movzx edx, word [r12 + 2]
    mov rbx, rax
    mov r12, rcx
    add edx, [r12 + l2cap_cred.tx_credits]
    cmp edx, 0xFFFF
    ja .too_many
    mov [r12 + l2cap_cred.tx_credits], edx
    call l2cap_cred_push
    jmp .out
.too_many:
    mov rdi, rbx
    call l2cap_disconnect
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; Credit Based Connection Request: SPSM, MTU, MPS, credits, 1-5 CIDs
l2cap_on_ecred_conn_req:
    push r15
    push rbp
    sub rsp, 88                         ; [rsp] response, [+24] chans, [+64] n
    cmp r13d, 8
    jb .out
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    mov [rsp + 24], rax
    mov [rsp + 32], rax
    mov [rsp + 40], rax
    mov [rsp + 48], rax
    mov [rsp + 56], rax
    lea eax, [r13d - 8]
    shr eax, 1
    mov [rsp + 64], eax
    ; what is wrong with the whole request refuses every channel
    mov ebp, L2CAP_LE_INVALID
    cmp eax, CRED_MAX_CHANS
    ja .too_many
    test eax, eax
    jz .reply
    test r13d, 1
    jnz .reply
    cmp word [r12 + 2], L2CAP_ECRED_MIN_MTU
    jb .reply
    cmp word [r12 + 4], L2CAP_ECRED_MIN_MTU
    jb .reply
    mov ebp, L2CAP_LE_BAD_PSM
    movzx edi, word [r12]
    call l2cap_server_find
    test rax, rax
    jz .reply
    cmp byte [rax + l2cap_srv.mode], L2CAP_MODE_ECRED
    jne .reply
    ; then each CID on its own
    xor ebp, ebp
    xor r15d, r15d
.one:
    movzx esi, word [r12 + 8 + r15 * 2]
    mov edx, L2CAP_LE_INVALID_SCID
    cmp esi, L2CAP_CID_DYN_START
    jb .refuse_one
    cmp byte [rbx + ubt_conn.type], UBT_LINK_LE
    jne .in_range
    cmp esi, L2CAP_CID_LE_DYN_END
    ja .refuse_one
.in_range:
    mov rdi, rbx
    call l2cap_find_dcid
    mov edx, L2CAP_LE_SCID_IN_USE
    test rax, rax
    jnz .refuse_one
    movzx edi, word [r12]
    mov esi, L2CAP_MODE_ECRED
    call l2cap_cred_accept
    test rax, rax
    jz .refuse_one
    mov [rsp + 24 + r15 * 8], rax
    mov rdi, rax
    movzx esi, word [r12 + 8 + r15 * 2]
    movzx edx, word [r12 + 2]
    movzx ecx, word [r12 + 4]
    movzx r8d, word [r12 + 6]
    call l2cap_cred_set
    mov rax, [rsp + 24 + r15 * 8]
    mov ax, [rax + l2cap_chan.scid]
    mov [rsp + 8 + r15 * 2], ax
    jmp .next
.refuse_one:
    mov ebp, edx
.next:
    inc r15d
    cmp r15d, [rsp + 64]
    jb .one
    jmp .reply
.too_many:
    mov dword [rsp + 64], CRED_MAX_CHANS
.reply:
    mov word [rsp], L2CAP_LOCAL_MTU
    mov word [rsp + 2], CRED_MPS
    mov word [rsp + 4], CRED_CREDITS
    mov [rsp + 6], bp
    mov ecx, [rsp + 64]
    lea ecx, [rcx * 2 + 8]
    mov esi, L2CAP_ECRED_CONN_RSP
    mov rdx, rsp
    call l2cap_sig_reply
    ; those opened, told
    xor r15d, r15d
.tell:
    cmp r15d, CRED_MAX_CHANS
    jae .out
    mov rdi, [rsp + 24 + r15 * 8]
    inc r15d
    test rdi, rdi
    jz .tell
    mov esi, L2CAP_EV_OPEN
    xor edx, edx
    call l2cap_event
    jmp .tell
.out:
    add rsp, 88
    pop rbp
    pop r15
    ret

; Credit Based Connection Response: MTU, MPS, credits, result, a CID per
; channel asked for (0: that one refused)
l2cap_on_ecred_conn_rsp:
    push r15
    push rbp
    sub rsp, 24                         ; [rsp] chan, [+8] CIDs given, [+12] CID
    cmp r13d, 8
    jb .out
    lea eax, [r13d - 8]
    shr eax, 1
    mov [rsp + 8], eax
    xor r15d, r15d
.chan:
    cmp r15d, UBT_MAX_CHANS
    jae .out
    mov rax, [rbx + ubt_conn.adapter]
    mov rdi, [rax + ubt_adapter.chans + r15 * 8]
    inc r15d
    test rdi, rdi
    jz .chan
    cmp [rdi + l2cap_chan.conn], rbx
    jne .chan
    cmp byte [rdi + l2cap_chan.state], L2CAP_WAIT_CONNECT
    jne .chan
    cmp byte [rdi + l2cap_chan.mode], L2CAP_MODE_ECRED
    jne .chan
    movzx eax, byte [rdi + l2cap_chan.ident]
    cmp eax, r14d
    jne .chan
    mov rax, [rdi + l2cap_chan.cred]
    mov eax, [rax + l2cap_cred.index]
    xor esi, esi
    cmp eax, [rsp + 8]
    jae .got
    movzx esi, word [r12 + 8 + rax * 2]
.got:
    test esi, esi
    jz .refused
    mov [rsp], rdi
    mov [rsp + 12], esi
    ; a CID of theirs already in use, or values no channel can use
    mov rdi, rbx
    call l2cap_find_dcid
    test rax, rax
    jnz .bad
    cmp word [r12], L2CAP_ECRED_MIN_MTU
    jb .bad
    cmp word [r12 + 2], L2CAP_ECRED_MIN_MTU
    jb .bad
    mov rdi, [rsp]
    mov esi, [rsp + 12]
    movzx edx, word [r12]
    movzx ecx, word [r12 + 2]
    movzx r8d, word [r12 + 4]
    call l2cap_cred_set
    mov rdi, [rsp]
    mov esi, L2CAP_EV_OPEN
    xor edx, edx
    call l2cap_event
    jmp .chan
.bad:
    mov rdi, [rsp]
    mov esi, [rsp + 12]
    mov [rdi + l2cap_chan.dcid], si
    call l2cap_disconnect
    jmp .chan
.refused:
    movzx edx, word [r12 + 6]
    test edx, edx
    jnz .why
    mov edx, L2CAP_LE_NO_MEM            ; refused without a reason given
.why:
    mov esi, L2CAP_EV_REFUSED
    call l2cap_close
    jmp .chan
.out:
    add rsp, 24
    pop rbp
    pop r15
    ret

; Credit Based Reconfigure Request: MTU, MPS, the sender's CIDs (1-5)
l2cap_on_reconf_req:
    push r15
    push rbp
    sub rsp, 8                          ; [rsp] n, [+4] the result
    mov ebp, L2CAP_RECONF_UNACCEPT
    cmp r13d, 6
    jb .reply
    test r13d, 1
    jnz .reply
    cmp word [r12], L2CAP_ECRED_MIN_MTU
    jb .reply
    cmp word [r12 + 2], L2CAP_ECRED_MIN_MTU
    jb .reply
    lea eax, [r13d - 4]
    shr eax, 1
    mov [rsp], eax
    cmp eax, CRED_MAX_CHANS
    ja .reply
    ; every one checked before any changes
    xor r15d, r15d
.check:
    mov rdi, rbx
    movzx esi, word [r12 + 4 + r15 * 2]
    call l2cap_find_dcid
    mov ebp, L2CAP_RECONF_CID
    test rax, rax
    jz .reply
    cmp byte [rax + l2cap_chan.mode], L2CAP_MODE_ECRED
    jne .reply
    cmp byte [rax + l2cap_chan.state], L2CAP_OPEN
    jne .reply
    mov ebp, L2CAP_RECONF_MTU
    mov cx, [r12]
    cmp cx, [rax + l2cap_chan.omtu]
    jb .reply
    mov ebp, L2CAP_RECONF_MPS
    cmp dword [rsp], 1
    je .checked
    movzx ecx, word [r12 + 2]
    mov rdx, [rax + l2cap_chan.cred]
    cmp ecx, [rdx + l2cap_cred.mps]
    jb .reply
.checked:
    inc r15d
    cmp r15d, [rsp]
    jb .check
    xor r15d, r15d
.apply:
    mov rdi, rbx
    movzx esi, word [r12 + 4 + r15 * 2]
    call l2cap_find_dcid
    mov cx, [r12]
    mov [rax + l2cap_chan.omtu], cx
    movzx ecx, word [r12 + 2]
    mov rdx, [rax + l2cap_chan.cred]
    mov [rdx + l2cap_cred.mps], ecx
    inc r15d
    cmp r15d, [rsp]
    jb .apply
    xor ebp, ebp
.reply:
    mov [rsp + 4], bp
    mov esi, L2CAP_ECRED_RECONF_RSP
    lea rdx, [rsp + 4]
    mov ecx, 2
    call l2cap_sig_reply
    add rsp, 8
    pop rbp
    pop r15
    ret

; Credit Based Reconfigure Response: the result for our request
l2cap_on_reconf_rsp:
    push r15
    cmp r13d, 2
    jb .out
    xor r15d, r15d
.chan:
    cmp r15d, UBT_MAX_CHANS
    jae .out
    mov rax, [rbx + ubt_conn.adapter]
    mov rdi, [rax + ubt_adapter.chans + r15 * 8]
    inc r15d
    test rdi, rdi
    jz .chan
    cmp [rdi + l2cap_chan.conn], rbx
    jne .chan
    movzx eax, byte [rdi + l2cap_chan.ident]
    cmp eax, r14d
    jne .chan
    mov rcx, [rdi + l2cap_chan.cred]
    test rcx, rcx
    jz .chan
    mov eax, [rcx + l2cap_cred.new_mtu]
    test eax, eax
    jz .chan
    mov dword [rcx + l2cap_cred.new_mtu], 0
    movzx edx, word [r12]
    test edx, edx
    jnz .tell
    mov [rdi + l2cap_chan.imtu], ax
.tell:
    mov esi, L2CAP_EV_RECONF
    call l2cap_event
    jmp .chan
.out:
    pop r15
    ret

%endif ; LIB_UBT_L2CAP_CREDIT_ASM
