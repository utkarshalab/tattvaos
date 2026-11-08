; =============================================================================
; Utkarsha OS — lib/ubt/l2cap/sig.asm — L2CAP signalling
; =============================================================================
;   l2cap_sig_send(conn, code, ident, data, len)    one command out
;   l2cap_sig_info_req(conn, type), l2cap_sig_conn_req(chan),
;   l2cap_sig_conf_req(chan), l2cap_sig_disconn_req(chan)
;   l2cap_sig_recv(conn, data, len)       BR/EDR: every command of a C-frame
;   l2cap_sig_le_recv(conn, data, len)    LE: the one command of a frame
;
; BR/EDR: Command Reject, Connection, Configuration (MTU, flush timeout,
; QoS, retransmission and flow control, FCS, extended flow spec; unknown
; options named back; continuation), Disconnection, Echo, Information
; (extended features, fixed channels, connectionless MTU). LE: Command
; Reject, Disconnection, Connection Parameter Update (the central accepts
; sensible values and has the controller apply them). Both: the
; credit-based commands (l2cap/credit.asm), LE Credit Based Connection on
; LE only.
; =============================================================================

%ifndef LIB_UBT_L2CAP_SIG_ASM
%define LIB_UBT_L2CAP_SIG_ASM

%define L2CAP_CONF_TRIES    3       ; renegotiations of ours before giving up

section .rodata
; what our L2CAP does, as Information Responses say it
l2cap_local_features: dd L2CAP_FEAT_ERTM | L2CAP_FEAT_STREAMING | L2CAP_FEAT_FCS | L2CAP_FEAT_FIXED_CHAN | L2CAP_FEAT_ECRED
l2cap_local_fixed:    dq (1 << L2CAP_CID_SIGNALING)

section .text

; -----------------------------------------------------------------------------
; l2cap_sig_send — RDI = conn, ESI = code, R8D = identifier, RDX = data,
;                  ECX = length (at most 248)
; Output: EAX = 0 or negative
; -----------------------------------------------------------------------------
global l2cap_sig_send
l2cap_sig_send:
    sub rsp, 264
    cmp ecx, 248
    jbe .len
    mov ecx, 248
.len:
    mov [rsp], sil
    mov [rsp + 1], r8b
    mov [rsp + 2], cx
    push rdi
    push rcx
    lea rdi, [rsp + 16 + 4]
    mov rsi, rdx
    rep movsb
    pop rcx
    pop rdi
    lea edx, [ecx + 4]
    mov ecx, edx
    mov rdx, rsp
    mov esi, L2CAP_CID_SIGNALING
    cmp byte [rdi + ubt_conn.type], UBT_LINK_LE
    jne .send
    mov esi, L2CAP_CID_LE_SIGNALING
.send:
    call l2cap_frame
    add rsp, 264
    ret

; l2cap_sig_chan_ident — RDI = chan: a new identifier for its request
; Output: R8D = it (also kept in the channel)
l2cap_sig_chan_ident:
    push rdi
    mov rdi, [rdi + l2cap_chan.conn]
    call l2cap_next_ident
    pop rdi
    mov [rdi + l2cap_chan.ident], r8b
    ret

; l2cap_sig_wait — RDI = chan: its answer due in RTX
l2cap_sig_wait:
    push rbx
    push rdi
    sub rsp, 8
    mov rbx, [rdi + l2cap_chan.conn]
    mov rbx, [rbx + ubt_conn.adapter]
    call l2cap_rtx
    add rsp, 8
    pop rdi
    mov [rdi + l2cap_chan.deadline], rax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_sig_info_req — RDI = conn, ESI = information type
; -----------------------------------------------------------------------------
global l2cap_sig_info_req
l2cap_sig_info_req:
    sub rsp, 8
    mov [rsp], si
    call l2cap_next_ident
    mov [rdi + ubt_conn.info_ident], r8b
    mov esi, L2CAP_INFO_REQ
    mov rdx, rsp
    mov ecx, 2
    call l2cap_sig_send
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; l2cap_sig_conn_req — RDI = chan: Connection Request (PSM, our CID)
; -----------------------------------------------------------------------------
global l2cap_sig_conn_req
l2cap_sig_conn_req:
    cmp byte [rdi + l2cap_chan.mode], L2CAP_MODE_LE_CREDITS
    jae l2cap_cred_conn_req             ; credit based: their own requests
    push rbx
    sub rsp, 16
    mov rbx, rdi
    ; a mode the peer said it cannot do: no use asking
    movzx eax, byte [rbx + l2cap_chan.mode]
    mov ecx, L2CAP_FEAT_ERTM
    cmp eax, L2CAP_MODE_ERTM
    je .feature
    mov ecx, L2CAP_FEAT_STREAMING
    cmp eax, L2CAP_MODE_STREAMING
    jne .ask
.feature:
    mov rax, [rbx + l2cap_chan.conn]
    test [rax + ubt_conn.ext_features], ecx
    jnz .ask
    mov rdi, rbx
    mov esi, L2CAP_EV_REFUSED
    mov edx, L2CAP_WHY_MODE
    call l2cap_close
    jmp .out
.ask:
    mov byte [rbx + l2cap_chan.state], L2CAP_WAIT_CONNECT
    mov rdi, rbx
    call l2cap_sig_wait
    mov ax, [rbx + l2cap_chan.psm]
    mov [rsp], ax
    mov ax, [rbx + l2cap_chan.scid]
    mov [rsp + 2], ax
    mov rdi, rbx
    call l2cap_sig_chan_ident
    mov rdi, [rbx + l2cap_chan.conn]
    mov esi, L2CAP_CONN_REQ
    mov rdx, rsp
    mov ecx, 4
    call l2cap_sig_send
.out:
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_sig_conf_req — RDI = chan: Configuration Request with our MTU, and
;                      for ERTM and streaming what we take (window,
;                      retransmissions, payload size; the timeouts are the
;                      responder's to set)
; -----------------------------------------------------------------------------
global l2cap_sig_conf_req
l2cap_sig_conf_req:
    push rbx
    sub rsp, 32
    mov rbx, rdi
    or byte [rbx + l2cap_chan.cfg], L2CAP_CFG_SENT
    call l2cap_sig_wait
    mov ax, [rbx + l2cap_chan.dcid]
    mov [rsp], ax
    mov word [rsp + 2], 0               ; flags: complete
    mov byte [rsp + 4], L2CAP_OPT_MTU
    mov byte [rsp + 5], 2
    mov ax, [rbx + l2cap_chan.imtu]
    mov [rsp + 6], ax
    mov ecx, 8
    movzx eax, byte [rbx + l2cap_chan.mode]
    cmp eax, L2CAP_MODE_ERTM
    je .rfc
    cmp eax, L2CAP_MODE_STREAMING
    jne .send
.rfc:
    mov byte [rsp + 8], L2CAP_OPT_RFC
    mov byte [rsp + 9], 9
    mov [rsp + 10], al
    mov byte [rsp + 11], ERTM_TXWIN
    mov byte [rsp + 12], ERTM_MAXTX
    mov dword [rsp + 13], 0             ; retransmission, monitor: theirs
    mov word [rsp + 17], ERTM_MPS
    mov ecx, 19
.send:
    push rcx
    sub rsp, 8
    mov rdi, rbx
    call l2cap_sig_chan_ident
    add rsp, 8
    pop rcx
    mov rdi, [rbx + l2cap_chan.conn]
    mov esi, L2CAP_CONF_REQ
    mov rdx, rsp
    call l2cap_sig_send
    add rsp, 32
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_sig_disconn_req — RDI = chan: Disconnection Request (their CID, ours)
; -----------------------------------------------------------------------------
global l2cap_sig_disconn_req
l2cap_sig_disconn_req:
    push rbx
    sub rsp, 16
    mov rbx, rdi
    mov ax, [rbx + l2cap_chan.dcid]
    mov [rsp], ax
    mov ax, [rbx + l2cap_chan.scid]
    mov [rsp + 2], ax
    mov rdi, rbx
    call l2cap_sig_chan_ident
    mov rdi, [rbx + l2cap_chan.conn]
    mov esi, L2CAP_DISCONN_REQ
    mov rdx, rsp
    mov ecx, 4
    call l2cap_sig_send
    add rsp, 16
    pop rbx
    ret

; l2cap_sig_reply — an answer to the command being handled: RBX = conn,
; R14D = its identifier; ESI = code, RDX = data, ECX = length
l2cap_sig_reply:
    sub rsp, 8
    mov rdi, rbx
    mov r8d, r14d
    call l2cap_sig_send
    add rsp, 8
    ret

; l2cap_sig_reject — Command Reject: RBX = conn, R14D = identifier, ESI =
; reason, RDX = its data (0), ECX = length
l2cap_sig_reject:
    sub rsp, 24
    mov [rsp], si
    test ecx, ecx
    jz .send
    mov eax, [rdx]
    mov [rsp + 2], eax
.send:
    add ecx, 2
    mov rdx, rsp
    mov esi, L2CAP_COMMAND_REJ
    call l2cap_sig_reply
    add rsp, 24
    ret

; l2cap_sig_open — RDI = chan: configured both ways, open (ERTM and
; streaming get their state first; without it the channel goes)
l2cap_sig_open:
    push rbx
    mov rbx, rdi
    movzx eax, byte [rbx + l2cap_chan.mode]
    cmp eax, L2CAP_MODE_ERTM
    je .state
    cmp eax, L2CAP_MODE_STREAMING
    jne .open
.state:
    call l2cap_ertm_open
    test eax, eax
    jz .open
    mov rdi, rbx
    call l2cap_disconnect
    jmp .out
.open:
    mov byte [rbx + l2cap_chan.state], L2CAP_OPEN
    mov qword [rbx + l2cap_chan.deadline], 0
    mov rdi, rbx
    mov esi, L2CAP_EV_OPEN
    xor edx, edx
    call l2cap_event
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_sig_recv — RDI = conn, RSI = the C-frame's payload, EDX = length
; -----------------------------------------------------------------------------
global l2cap_sig_recv
l2cap_sig_recv:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8
    mov rbx, rdi
    mov r15, rsi                        ; the next command
    lea rbp, [rsi + rdx]                ; the end
.command:
    lea rax, [r15 + 4]
    cmp rax, rbp
    ja .out
    movzx r14d, byte [r15 + 1]          ; identifier
    movzx r13d, word [r15 + 2]          ; length
    lea r12, [r15 + 4]                  ; data
    lea rax, [r12 + r13]
    cmp rax, rbp
    ja .out                             ; longer than the frame: stop here
    movzx eax, byte [r15]
    mov r15, rax                        ; (the next one's place, below)
    push r12
    push r13
    call .one
    pop r13
    pop r12
    lea r15, [r12 + r13]
    jmp .command
.out:
    add rsp, 8
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; one command: R15D = code, R12 = data, R13D = length, R14D = identifier,
; RBX = conn (the stack is aligned here: two pushes and a call above it)
.one:
    test r14d, r14d
    jz .ignore                          ; identifier 0 is never valid
    cmp r15d, L2CAP_COMMAND_REJ
    je l2cap_on_reject
    cmp r15d, L2CAP_CONN_REQ
    je l2cap_on_conn_req
    cmp r15d, L2CAP_CONN_RSP
    je l2cap_on_conn_rsp
    cmp r15d, L2CAP_CONF_REQ
    je l2cap_on_conf_req
    cmp r15d, L2CAP_CONF_RSP
    je l2cap_on_conf_rsp
    cmp r15d, L2CAP_DISCONN_REQ
    je l2cap_on_disconn_req
    cmp r15d, L2CAP_DISCONN_RSP
    je l2cap_on_disconn_rsp
    cmp r15d, L2CAP_ECHO_REQ
    je l2cap_on_echo_req
    cmp r15d, L2CAP_ECHO_RSP
    je l2cap_on_echo_rsp
    cmp r15d, L2CAP_INFO_REQ
    je l2cap_on_info_req
    cmp r15d, L2CAP_INFO_RSP
    je l2cap_on_info_rsp
    cmp r15d, L2CAP_LE_CREDITS
    je l2cap_on_credits
    cmp r15d, L2CAP_ECRED_CONN_REQ
    je l2cap_on_ecred_conn_req
    cmp r15d, L2CAP_ECRED_CONN_RSP
    je l2cap_on_ecred_conn_rsp
    cmp r15d, L2CAP_ECRED_RECONF_REQ
    je l2cap_on_reconf_req
    cmp r15d, L2CAP_ECRED_RECONF_RSP
    je l2cap_on_reconf_rsp
    mov esi, L2CAP_REJ_NOT_UNDERSTOOD
    xor edx, edx
    xor ecx, ecx
    jmp l2cap_sig_reject
.ignore:
    ret

; ---- the handlers: RBX = conn, R12 = data, R13D = length, R14D = ident ------

l2cap_on_reject:
    ; our information request: the peer does not do it
    movzx eax, byte [rbx + ubt_conn.info_ident]
    cmp eax, r14d
    jne .chan
    cmp byte [rbx + ubt_conn.info_state], 1
    jne .chan
    mov dword [rbx + ubt_conn.ext_features], 0
    mov byte [rbx + ubt_conn.info_state], 2
    mov rdi, rbx
    jmp l2cap_resume
.chan:
    ; a channel's request: a connection refused, or one the peer no
    ; longer knows (configuring or closing it) simply closed
    call l2cap_chan_by_ident
    test rax, rax
    jz .out
    mov rdi, rax
    mov esi, L2CAP_EV_REFUSED
    cmp byte [rax + l2cap_chan.state], L2CAP_WAIT_CONNECT
    jbe .tell
    mov esi, L2CAP_EV_CLOSED
.tell:
    mov edx, 0xFFFF
    jmp l2cap_close
.out:
    ret

; l2cap_chan_by_ident — RBX = conn, R14D = identifier → RAX = the channel
; waiting with that identifier, or 0
l2cap_chan_by_ident:
    mov r8, [rbx + ubt_conn.adapter]
    xor ecx, ecx
.next:
    cmp ecx, UBT_MAX_CHANS
    jae .none
    mov rax, [r8 + ubt_adapter.chans + rcx * 8]
    inc ecx
    test rax, rax
    jz .next
    cmp [rax + l2cap_chan.conn], rbx
    jne .next
    movzx edx, byte [rax + l2cap_chan.ident]
    cmp edx, r14d
    jne .next
    ret
.none:
    xor eax, eax
    ret

l2cap_on_conn_req:
    push r15
    sub rsp, 16                         ; the response
    cmp r13d, 4
    jb .out
    movzx r15d, word [r12 + 2]          ; their CID
    mov word [rsp], 0
    mov [rsp + 2], r15w
    mov dword [rsp + 4], 0              ; result, status
    mov word [rsp + 4], L2CAP_CR_INVALID_SCID
    cmp r15d, L2CAP_CID_DYN_START
    jb .respond
    mov word [rsp + 4], L2CAP_CR_SCID_IN_USE
    mov rdi, rbx
    mov esi, r15d
    call l2cap_find_dcid
    test rax, rax
    jnz .respond
    mov word [rsp + 4], L2CAP_CR_BAD_PSM
    movzx edi, word [r12]
    call l2cap_server_find
    test rax, rax
    jz .respond
    push rax
    sub rsp, 8
    mov rdi, rbx
    call l2cap_chan_new
    add rsp, 8
    pop rcx                             ; the server
    mov word [rsp + 4], L2CAP_CR_NO_MEM
    test rax, rax
    jz .respond
    mov [rax + l2cap_chan.dcid], r15w
    mov dx, [rcx + l2cap_srv.psm]
    mov [rax + l2cap_chan.psm], dx
    mov dl, [rcx + l2cap_srv.mode]
    mov [rax + l2cap_chan.mode], dl
    mov rdx, [rcx + l2cap_srv.ops]
    mov [rax + l2cap_chan.ops], rdx
    mov rdx, [rcx + l2cap_srv.user]
    mov [rax + l2cap_chan.user], rdx
    mov byte [rax + l2cap_chan.state], L2CAP_CONFIG
    mov dx, [rax + l2cap_chan.scid]
    mov [rsp], dx
    mov word [rsp + 4], L2CAP_CR_SUCCESS
    mov [rsp + 8], rax
    mov esi, L2CAP_CONN_RSP
    lea rdx, [rsp]
    mov ecx, 8
    call l2cap_sig_reply
    mov rdi, [rsp + 8]                  ; then our configuration
    call l2cap_sig_conf_req
    jmp .out
.respond:
    mov esi, L2CAP_CONN_RSP
    lea rdx, [rsp]
    mov ecx, 8
    call l2cap_sig_reply
.out:
    add rsp, 16
    pop r15
    ret

l2cap_on_conn_rsp:
    cmp r13d, 8
    jb .out
    mov rdi, rbx
    movzx esi, word [r12 + 2]           ; our CID
    call l2cap_find_scid
    test rax, rax
    jz .out
    cmp byte [rax + l2cap_chan.state], L2CAP_WAIT_CONNECT
    jne .out
    movzx ecx, byte [rax + l2cap_chan.ident]
    cmp ecx, r14d
    jne .out
    mov rdi, rax
    movzx edx, word [r12 + 4]           ; result
    cmp edx, L2CAP_CR_PENDING
    je .pending
    test edx, edx
    jnz .refused
    mov cx, [r12]
    mov [rdi + l2cap_chan.dcid], cx
    mov byte [rdi + l2cap_chan.state], L2CAP_CONFIG
    jmp l2cap_sig_conf_req
.pending:
    jmp l2cap_sig_wait                  ; still coming: wait again
.refused:
    mov esi, L2CAP_EV_REFUSED
    jmp l2cap_close
.out:
    ret

; -----------------------------------------------------------------------------
; l2cap_on_conf_req — their configuration of the channel's data to them
; -----------------------------------------------------------------------------
l2cap_on_conf_req:
    push r15
    push rbp
    sub rsp, 88                 ; [rsp] response: scid, flags, result, then
                                ; options (up to 64); [rsp+72] chan,
                                ; [rsp+80] response length
    cmp r13d, 4
    jb .out
    mov rdi, rbx
    movzx esi, word [r12]               ; our CID
    call l2cap_find_scid
    test rax, rax
    jnz .found
    sub rsp, 16
    mov ax, [r12]
    mov [rsp], ax                       ; reject: invalid CID (ours, theirs 0)
    mov word [rsp + 2], 0
    mov esi, L2CAP_REJ_INVALID_CID
    mov rdx, rsp
    mov ecx, 4
    call l2cap_sig_reject
    add rsp, 16
    jmp .out
.found:
    mov [rsp + 72], rax
    movzx ecx, byte [rax + l2cap_chan.state]
    cmp ecx, L2CAP_CONFIG
    je .state_ok
    cmp ecx, L2CAP_OPEN
    jne .out                            ; not now
.state_ok:
    mov cx, [rax + l2cap_chan.dcid]
    mov [rsp], cx
    mov cx, [r12 + 2]
    and cx, 1                           ; continuation: echoed
    mov [rsp + 2], cx
    mov word [rsp + 4], L2CAP_CONF_SUCCESS
    mov dword [rsp + 80], 6
    mov dword [rsp + 84], 0             ; no RFC option seen yet
    ; the options
    lea r15, [r12 + 4]
    lea rbp, [r12 + r13]
.option:
    lea rax, [r15 + 2]
    cmp rax, rbp
    ja .options_done
    movzx ecx, byte [r15 + 1]
    lea rax, [r15 + 2 + rcx]
    cmp rax, rbp
    ja .malformed
    movzx eax, byte [r15]
    mov edx, eax
    and edx, ~L2CAP_OPT_HINT
    cmp edx, L2CAP_OPT_MTU
    je .mtu
    cmp edx, L2CAP_OPT_RFC
    je .rfc
    cmp edx, L2CAP_OPT_FLUSH_TO
    je .next_option                     ; any flush timeout will do
    cmp edx, L2CAP_OPT_QOS
    je .next_option                     ; best effort whatever is asked
    cmp edx, L2CAP_OPT_FCS
    je .next_option                     ; basic mode has none either way
    cmp edx, L2CAP_OPT_EFS
    je .next_option
    test eax, L2CAP_OPT_HINT
    jnz .next_option                    ; an unknown hint: ignored
    ; an unknown option: named back (once the result says so)
    cmp word [rsp + 4], L2CAP_CONF_UNKNOWN
    je .add_unknown
    mov word [rsp + 4], L2CAP_CONF_UNKNOWN
    mov dword [rsp + 80], 6
.add_unknown:
    mov ecx, [rsp + 80]
    cmp ecx, 70
    jae .next_option
    mov [rsp + rcx], al
    inc dword [rsp + 80]
    jmp .next_option
.mtu:
    cmp ecx, 2
    jne .malformed
    movzx eax, word [r15 + 2]
    cmp eax, L2CAP_MIN_MTU
    jae .mtu_ok
    ; too small: unacceptable, with the least we take
    cmp word [rsp + 4], L2CAP_CONF_UNKNOWN
    je .next_option
    mov word [rsp + 4], L2CAP_CONF_UNACCEPT
    mov ecx, [rsp + 80]
    cmp ecx, 64
    ja .next_option                     ; no room left in the answer
    mov byte [rsp + rcx], L2CAP_OPT_MTU
    mov byte [rsp + rcx + 1], 2
    mov word [rsp + rcx + 2], L2CAP_MIN_MTU
    add dword [rsp + 80], 4
    jmp .next_option
.mtu_ok:
    mov rdx, [rsp + 72]
    mov [rdx + l2cap_chan.omtu], ax
    jmp .next_option
.rfc:
    cmp ecx, 9
    jne .malformed
    mov rdx, [rsp + 72]
    mov dword [rsp + 84], 1
    mov al, [r15 + 2]
    cmp al, [rdx + l2cap_chan.mode]
    jne .other_mode
    ; ERTM or streaming: what they take, for what we send
    mov al, [r15 + 3]
    mov [rdx + l2cap_chan.peer_txwin], al
    mov al, [r15 + 4]
    mov [rdx + l2cap_chan.peer_maxtx], al
    mov ax, [r15 + 9]
    mov [rdx + l2cap_chan.peer_mps], ax
    jmp .next_option
.other_mode:
    ; another mode than the channel's: unacceptable, with ours
    cmp word [rsp + 4], L2CAP_CONF_UNKNOWN
    je .next_option
    mov word [rsp + 4], L2CAP_CONF_UNACCEPT
    ; ERTM and streaming answer with their full option at the end
    cmp byte [rdx + l2cap_chan.mode], L2CAP_MODE_ERTM
    je .next_option
    cmp byte [rdx + l2cap_chan.mode], L2CAP_MODE_STREAMING
    je .next_option
    mov ecx, [rsp + 80]
    cmp ecx, 60
    ja .next_option
    mov byte [rsp + rcx], L2CAP_OPT_RFC
    mov byte [rsp + rcx + 1], 9
    mov al, [rdx + l2cap_chan.mode]
    mov [rsp + rcx + 2], al
    mov qword [rsp + rcx + 3], 0
    add dword [rsp + 80], 11
    jmp .next_option
.next_option:
    movzx ecx, byte [r15 + 1]
    lea r15, [r15 + 2 + rcx]
    jmp .option
.malformed:
    mov word [rsp + 4], L2CAP_CONF_REJECT
    mov dword [rsp + 80], 6
    jmp .respond
.options_done:
    ; ERTM and streaming need the option: without it they asked for basic
    mov rdx, [rsp + 72]
    movzx eax, byte [rdx + l2cap_chan.mode]
    cmp eax, L2CAP_MODE_ERTM
    je .needs_rfc
    cmp eax, L2CAP_MODE_STREAMING
    jne .respond
.needs_rfc:
    cmp word [rsp + 4], L2CAP_CONF_UNKNOWN
    je .respond
    cmp dword [rsp + 84], 0
    jne .rfc_answer
    mov word [rsp + 4], L2CAP_CONF_UNACCEPT
.rfc_answer:
    ; success or not, the RFC option back: the mode, their values, and the
    ; timeouts we want them to use
    mov ecx, [rsp + 80]
    cmp ecx, 60
    ja .respond
    mov byte [rsp + rcx], L2CAP_OPT_RFC
    mov byte [rsp + rcx + 1], 9
    mov [rsp + rcx + 2], al
    mov r8b, [rdx + l2cap_chan.peer_txwin]
    mov [rsp + rcx + 3], r8b
    mov r8b, [rdx + l2cap_chan.peer_maxtx]
    mov [rsp + rcx + 4], r8b
    mov word [rsp + rcx + 5], ERTM_RETRANS_MS
    mov word [rsp + rcx + 7], ERTM_MONITOR_MS
    mov r8w, [rdx + l2cap_chan.peer_mps]
    mov [rsp + rcx + 9], r8w
    add dword [rsp + 80], 11
.respond:
    mov esi, L2CAP_CONF_RSP
    mov rdx, rsp
    mov ecx, [rsp + 80]
    call l2cap_sig_reply
    ; accepted and complete: their side is done
    cmp word [rsp + 4], L2CAP_CONF_SUCCESS
    jne .out
    test word [rsp + 2], 1
    jnz .out
    mov rdi, [rsp + 72]
    or byte [rdi + l2cap_chan.cfg], L2CAP_CFG_IN_DONE
    cmp byte [rdi + l2cap_chan.state], L2CAP_CONFIG
    jne .out
    test byte [rdi + l2cap_chan.cfg], L2CAP_CFG_OUT_DONE
    jz .ours
    call l2cap_sig_open
    jmp .out
.ours:
    test byte [rdi + l2cap_chan.cfg], L2CAP_CFG_SENT
    jnz .out
    call l2cap_sig_conf_req             ; ours had not gone yet
.out:
    add rsp, 88
    pop rbp
    pop r15
    ret

; -----------------------------------------------------------------------------
; l2cap_on_conf_rsp — their answer to our configuration
; -----------------------------------------------------------------------------
l2cap_on_conf_rsp:
    push r15
    cmp r13d, 6
    jb .out
    mov rdi, rbx
    movzx esi, word [r12]               ; our CID
    call l2cap_find_scid
    test rax, rax
    jz .out
    mov r15, rax
    movzx ecx, byte [r15 + l2cap_chan.ident]
    cmp ecx, r14d
    jne .out
    cmp byte [r15 + l2cap_chan.state], L2CAP_CONFIG
    je .config
    cmp byte [r15 + l2cap_chan.state], L2CAP_OPEN
    jne .out
.config:
    movzx eax, word [r12 + 4]           ; result
    test eax, eax
    jz .success
    cmp eax, L2CAP_CONF_UNACCEPT
    jne .give_up
    ; their counter-offer: an MTU for what they send us we can take
    inc byte [r15 + l2cap_chan.pad]
    cmp byte [r15 + l2cap_chan.pad], L2CAP_CONF_TRIES
    ja .give_up
    lea rcx, [r12 + 6]
    lea rdx, [r12 + r13]
.offer:
    lea rax, [rcx + 2]
    cmp rax, rdx
    ja .again
    movzx r8d, byte [rcx + 1]
    mov al, [rcx]
    and al, ~L2CAP_OPT_HINT
    cmp al, L2CAP_OPT_MTU
    jne .offer_next
    cmp r8d, 2
    jne .offer_next
    movzx eax, word [rcx + 2]
    cmp eax, L2CAP_MIN_MTU
    jb .give_up
    cmp eax, L2CAP_LOCAL_MTU
    ja .offer_next                      ; more than we take: keep ours
    mov [r15 + l2cap_chan.imtu], ax
.offer_next:
    lea rcx, [rcx + 2 + r8]
    jmp .offer
.again:
    mov rdi, r15
    call l2cap_sig_conf_req
    jmp .out
.give_up:
    mov rdi, r15
    call l2cap_disconnect
    jmp .out
.success:
    ; the timeouts they set for ERTM, if they did
    lea rcx, [r12 + 6]
    lea rdx, [r12 + r13]
.timeouts:
    lea rax, [rcx + 2]
    cmp rax, rdx
    ja .timeouts_done
    movzx r8d, byte [rcx + 1]
    lea rax, [rcx + 2 + r8]
    cmp rax, rdx
    ja .timeouts_done
    mov al, [rcx]
    and al, ~L2CAP_OPT_HINT
    cmp al, L2CAP_OPT_RFC
    jne .timeouts_next
    cmp r8d, 9
    jne .timeouts_next
    mov ax, [rcx + 5]
    mov [r15 + l2cap_chan.retrans_ms], ax
    mov ax, [rcx + 7]
    mov [r15 + l2cap_chan.monitor_ms], ax
.timeouts_next:
    lea rcx, [rcx + 2 + r8]
    jmp .timeouts
.timeouts_done:
    test word [r12 + 2], 1
    jnz .out                            ; more to come
    or byte [r15 + l2cap_chan.cfg], L2CAP_CFG_OUT_DONE
    cmp byte [r15 + l2cap_chan.state], L2CAP_CONFIG
    jne .out
    test byte [r15 + l2cap_chan.cfg], L2CAP_CFG_IN_DONE
    jz .wait
    mov rdi, r15
    call l2cap_sig_open
    jmp .out
.wait:
    mov rdi, r15
    call l2cap_sig_wait                 ; now theirs is due
.out:
    pop r15
    ret

l2cap_on_disconn_req:
    sub rsp, 8
    cmp r13d, 4
    jb .out
    mov rdi, rbx
    movzx esi, word [r12]               ; ours
    call l2cap_find_scid
    test rax, rax
    jz .unknown
    mov cx, [r12 + 2]
    cmp cx, [rax + l2cap_chan.dcid]
    jne .unknown
    mov [rsp], rax
    mov esi, L2CAP_DISCONN_RSP
    mov rdx, r12
    mov ecx, 4
    call l2cap_sig_reply
    mov rdi, [rsp]
    mov esi, L2CAP_EV_CLOSED
    mov edx, L2CAP_WHY_PEER
    call l2cap_close
    jmp .out
.unknown:
    mov esi, L2CAP_REJ_INVALID_CID
    mov rdx, r12
    mov ecx, 4
    call l2cap_sig_reject
.out:
    add rsp, 8
    ret

l2cap_on_disconn_rsp:
    cmp r13d, 4
    jb .out
    mov rdi, rbx
    movzx esi, word [r12 + 2]           ; ours
    call l2cap_find_scid
    test rax, rax
    jz .out
    cmp byte [rax + l2cap_chan.state], L2CAP_WAIT_DISCONNECT
    jne .out
    mov rdi, rax
    mov esi, L2CAP_EV_CLOSED
    xor edx, edx
    jmp l2cap_close
.out:
    ret

l2cap_on_echo_req:
    mov esi, L2CAP_ECHO_RSP
    mov rdx, r12
    mov ecx, r13d
    jmp l2cap_sig_reply

l2cap_on_echo_rsp:
    mov rax, [rel l2cap_echo_fn]
    test rax, rax
    jz .out
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    jmp rax
.out:
    ret

l2cap_on_info_req:
    sub rsp, 24
    cmp r13d, 2
    jb .out
    movzx eax, word [r12]
    mov [rsp], ax
    mov word [rsp + 2], 0               ; success
    cmp eax, L2CAP_IT_FEAT_MASK
    je .features
    cmp eax, L2CAP_IT_FIXED_CHAN
    je .fixed
    cmp eax, L2CAP_IT_CL_MTU
    je .cl_mtu
    mov word [rsp + 2], 1               ; not supported
    mov ecx, 4
    jmp .send
.features:
    mov eax, [rel l2cap_local_features]
    mov [rsp + 4], eax
    mov ecx, 8
    jmp .send
.fixed:
    mov rax, [rel l2cap_local_fixed]
    mov [rsp + 4], rax
    mov ecx, 12
    jmp .send
.cl_mtu:
    mov word [rsp + 4], L2CAP_DEFAULT_MTU
    mov ecx, 6
.send:
    mov esi, L2CAP_INFO_RSP
    mov rdx, rsp
    call l2cap_sig_reply
.out:
    add rsp, 24
    ret

l2cap_on_info_rsp:
    cmp r13d, 4
    jb .out
    movzx eax, byte [rbx + ubt_conn.info_ident]
    cmp eax, r14d
    jne .out
    cmp byte [rbx + ubt_conn.info_state], 1
    jne .out
    movzx eax, word [r12]               ; type
    cmp eax, L2CAP_IT_FEAT_MASK
    je .features
    cmp eax, L2CAP_IT_FIXED_CHAN
    jne .known
    cmp word [r12 + 2], 0
    jne .known
    cmp r13d, 12
    jb .known
    mov rax, [r12 + 4]
    mov [rbx + ubt_conn.fixed_chans], rax
    jmp .known
.features:
    mov dword [rbx + ubt_conn.ext_features], 0
    cmp word [r12 + 2], 0
    jne .known
    cmp r13d, 8
    jb .known
    mov eax, [r12 + 4]
    mov [rbx + ubt_conn.ext_features], eax
    test eax, L2CAP_FEAT_FIXED_CHAN
    jz .known
    mov rdi, rbx                        ; and its fixed channels
    mov esi, L2CAP_IT_FIXED_CHAN
    jmp l2cap_sig_info_req
.known:
    mov byte [rbx + ubt_conn.info_state], 2
    mov rdi, rbx
    jmp l2cap_resume
.out:
    ret

; -----------------------------------------------------------------------------
; l2cap_sig_le_recv — RDI = conn, RSI = the LE signalling frame's payload,
;                     EDX = length (one command)
; -----------------------------------------------------------------------------
global l2cap_sig_le_recv
l2cap_sig_le_recv:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    cmp edx, 4
    jb .out
    movzx r15d, byte [rsi]
    movzx r14d, byte [rsi + 1]
    movzx r13d, word [rsi + 2]
    lea r12, [rsi + 4]
    lea eax, [r13d + 4]
    cmp eax, edx
    ja .out
    test r14d, r14d
    jz .out
    cmp r15d, L2CAP_COMMAND_REJ
    je .reject_in
    cmp r15d, L2CAP_DISCONN_REQ
    je .disconnect
    cmp r15d, L2CAP_DISCONN_RSP
    je .disconnected
    cmp r15d, L2CAP_CONN_PARAM_REQ
    je .param
    cmp r15d, L2CAP_CONN_PARAM_RSP
    je .out                             ; ours was answered: nothing to do
    lea rax, [rel l2cap_on_le_conn_req]
    cmp r15d, L2CAP_LE_CONN_REQ
    je .handler
    lea rax, [rel l2cap_on_le_conn_rsp]
    cmp r15d, L2CAP_LE_CONN_RSP
    je .handler
    lea rax, [rel l2cap_on_credits]
    cmp r15d, L2CAP_LE_CREDITS
    je .handler
    lea rax, [rel l2cap_on_ecred_conn_req]
    cmp r15d, L2CAP_ECRED_CONN_REQ
    je .handler
    lea rax, [rel l2cap_on_ecred_conn_rsp]
    cmp r15d, L2CAP_ECRED_CONN_RSP
    je .handler
    lea rax, [rel l2cap_on_reconf_req]
    cmp r15d, L2CAP_ECRED_RECONF_REQ
    je .handler
    lea rax, [rel l2cap_on_reconf_rsp]
    cmp r15d, L2CAP_ECRED_RECONF_RSP
    je .handler
    mov esi, L2CAP_REJ_NOT_UNDERSTOOD
    xor edx, edx
    xor ecx, ecx
    call l2cap_sig_reject
    jmp .out
.reject_in:
    call l2cap_on_reject
    jmp .out
.disconnect:
    call l2cap_on_disconn_req
    jmp .out
.disconnected:
    call l2cap_on_disconn_rsp
    jmp .out
.param:
    call l2cap_on_param_req
    jmp .out
.handler:
    call rax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Connection Parameter Update Request: interval min and max, latency,
; supervision timeout. Only a peripheral asks; the central answers.
l2cap_on_param_req:
    push r15
    sub rsp, 32
    cmp byte [rbx + ubt_conn.role], 0
    je .central
    mov esi, L2CAP_REJ_NOT_UNDERSTOOD
    xor edx, edx
    xor ecx, ecx
    call l2cap_sig_reject
    jmp .out
.central:
    cmp r13d, 8
    jb .out
    mov r15d, 1                         ; rejected unless they make sense
    movzx eax, word [r12]               ; min (1.25 ms units)
    movzx ecx, word [r12 + 2]           ; max
    movzx edx, word [r12 + 4]           ; latency
    movzx r8d, word [r12 + 6]           ; timeout (10 ms units)
    cmp eax, 6
    jb .answer
    cmp ecx, 3200
    ja .answer
    cmp eax, ecx
    ja .answer
    cmp edx, 499
    ja .answer
    cmp r8d, 10
    jb .answer
    cmp r8d, 3200
    ja .answer
    ; the timeout must outlast the slowest interval with its latency:
    ; timeout * 10 ms > (1 + latency) * max * 1.25 ms * 2
    lea r9d, [rdx + 1]
    imul r9d, ecx
    imul r9d, r9d, 25                   ; × 1.25 ms × 2, in tenths of ms ...
    imul r10d, r8d, 100                 ; ... against the timeout in them
    cmp r10d, r9d
    jbe .answer
    xor r15d, r15d
.answer:
    mov [rsp], r15w
    mov esi, L2CAP_CONN_PARAM_RSP
    mov rdx, rsp
    mov ecx, 2
    call l2cap_sig_reply
    test r15d, r15d
    jnz .out
    ; the controller applies them
    mov ax, [rbx + ubt_conn.handle]
    mov [rsp], ax
    mov eax, [r12]
    mov [rsp + 2], eax
    mov eax, [r12 + 4]
    mov [rsp + 6], eax
    mov dword [rsp + 10], 0             ; CE lengths
    mov rdi, [rbx + ubt_conn.adapter]
    mov esi, HCI_LE_CONN_UPDATE
    mov rdx, rsp
    mov ecx, 14
    call ubt_hci_async
.out:
    add rsp, 32
    pop r15
    ret

%endif ; LIB_UBT_L2CAP_SIG_ASM
