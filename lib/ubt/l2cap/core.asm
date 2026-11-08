; =============================================================================
; Utkarsha OS — lib/ubt/l2cap/core.asm — L2CAP channels
; =============================================================================
;   l2cap_server(psm, mode, ops, user)      take incoming channels on a PSM
;   l2cap_connect(conn, psm, mode, ops, user) → chan   open one; ops.event
;                       says L2CAP_EV_OPEN, _REFUSED or _CLOSED later
;   l2cap_send(chan, sdu, len)              one SDU on an open channel
;   (credit based: l2cap_connect_ecred, l2cap_reconfigure in l2cap/credit.asm)
;   l2cap_disconnect(chan)
;   l2cap_echo(conn, data, len)             BR/EDR ping: l2cap_echo_fn later
;   l2cap_tick(adapter)                     timeouts (from ubt_service)
;
; From the link layer: l2cap_conn_up, l2cap_conn_down, l2cap_recv (one
; whole frame). Fixed channels (ATT, SMP, connectionless) go to the
; adapter's fixed_fn; signalling to l2cap/sig.asm; dynamic channels to their
; user, in basic mode here (other modes in their own files).
; =============================================================================

%ifndef LIB_UBT_L2CAP_CORE_ASM
%define LIB_UBT_L2CAP_CORE_ASM

section .bss
alignb 8
global l2cap_servers
l2cap_servers:      resb L2CAP_MAX_SERVERS * l2cap_srv_size
global l2cap_server_count
l2cap_server_count: resd 1
global l2cap_dropped
l2cap_dropped:      resd 1          ; frames for no channel, or too long
alignb 8
global ubt_clock_fn
ubt_clock_fn:       resq 1          ; → RAX = milliseconds (0: no timeouts)
global l2cap_echo_fn
l2cap_echo_fn:      resq 1          ; (conn, data, length): an Echo Response

section .rodata
; record sizes and offsets, for the host tests to check their copies
global l2cap_layout
l2cap_layout:
    dd ubt_conn_size, ubt_conn.tx_head, ubt_conn.ext_features, ubt_conn.rx_buf
    dd l2cap_chan_size, l2cap_chan.scid, l2cap_chan.state, l2cap_ops_size

section .text

; ubt_now — RAX = milliseconds from ubt_clock_fn, or 0
global ubt_now
ubt_now:
    mov rax, [rel ubt_clock_fn]
    test rax, rax
    jz .zero
    sub rsp, 8
    call rax
    add rsp, 8
    ret
.zero:
    xor eax, eax
    ret

; l2cap_rtx — RBX = adapter → RAX = the deadline for an answer from now
l2cap_rtx:
    sub rsp, 8
    call ubt_now
    add rsp, 8
    test rax, rax
    jz .out                             ; no clock: never times out
    mov ecx, [rbx + ubt_adapter.rtx_ms]
    add rax, rcx
.out:
    ret

; -----------------------------------------------------------------------------
; l2cap_server — EDI = PSM, ESI = mode, RDX = l2cap_ops*, RCX = user
; Output: EAX = 0, or -UBT_ENOMEM (16 at most), -UBT_EBUSY (PSM taken)
; -----------------------------------------------------------------------------
global l2cap_server
l2cap_server:
    xor r8d, r8d
.find:
    cmp r8d, [rel l2cap_server_count]
    jae .add
    mov eax, r8d
    imul eax, eax, l2cap_srv_size
    lea r9, [rel l2cap_servers]
    cmp [r9 + rax + l2cap_srv.psm], di
    je .taken
    inc r8d
    jmp .find
.add:
    mov eax, -UBT_ENOMEM
    cmp r8d, L2CAP_MAX_SERVERS
    jae .out
    mov eax, r8d
    imul eax, eax, l2cap_srv_size
    lea r9, [rel l2cap_servers]
    add r9, rax
    mov [r9 + l2cap_srv.psm], di
    mov [r9 + l2cap_srv.mode], sil
    mov [r9 + l2cap_srv.ops], rdx
    mov [r9 + l2cap_srv.user], rcx
    inc dword [rel l2cap_server_count]
    xor eax, eax
    ret
.taken:
    mov eax, -UBT_EBUSY
.out:
    ret

; l2cap_server_find — EDI = PSM → RAX = l2cap_server*, or 0
global l2cap_server_find
l2cap_server_find:
    xor ecx, ecx
.next:
    cmp ecx, [rel l2cap_server_count]
    jae .none
    mov eax, ecx
    imul eax, eax, l2cap_srv_size
    lea rdx, [rel l2cap_servers]
    add rax, rdx
    inc ecx
    cmp [rax + l2cap_srv.psm], di
    jne .next
    ret
.none:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; l2cap_chan_new — RDI = conn → RAX = a channel with a free CID of ours,
;                  listed on the adapter; 0 when there is no room
; -----------------------------------------------------------------------------
global l2cap_chan_new
l2cap_chan_new:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, [r12 + ubt_conn.adapter]
    xor r13d, r13d
.slot:
    cmp r13d, UBT_MAX_CHANS
    jae .none
    cmp qword [rbx + ubt_adapter.chans + r13 * 8], 0
    je .free
    inc r13d
    jmp .slot
.free:
    ; the lowest dynamic CID no channel of this link has (LE: to 0x7F)
    mov ecx, L2CAP_CID_DYN_START
.cid:
    mov rdi, r12
    mov esi, ecx
    push rcx
    sub rsp, 8
    call l2cap_find_scid                ; (counts in ECX)
    add rsp, 8
    pop rcx
    test rax, rax
    jz .cid_free
    inc ecx
    cmp byte [r12 + ubt_conn.type], UBT_LINK_LE
    jne .cid
    cmp ecx, L2CAP_CID_LE_DYN_END
    ja .none
    jmp .cid
.cid_free:
    push rcx
    sub rsp, 8
    mov edi, l2cap_chan_size
    mov esi, 8
    call usb_alloc
    add rsp, 8
    pop rcx
    test rax, rax
    jz .none
    mov [rbx + ubt_adapter.chans + r13 * 8], rax
    mov [rax + l2cap_chan.conn], r12
    mov word [rax + l2cap_chan.imtu], L2CAP_LOCAL_MTU
    mov word [rax + l2cap_chan.omtu], L2CAP_DEFAULT_MTU
    mov [rax + l2cap_chan.scid], cx
    jmp .out
.none:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; l2cap_find_scid — RDI = conn, ESI = our CID → RAX = chan, or 0
; l2cap_find_dcid — RDI = conn, ESI = their CID → RAX = chan, or 0
global l2cap_find_scid
l2cap_find_scid:
    mov edx, l2cap_chan.scid
    jmp l2cap_find_cid
global l2cap_find_dcid
l2cap_find_dcid:
    mov edx, l2cap_chan.dcid
l2cap_find_cid:
    mov r8, [rdi + ubt_conn.adapter]
    xor ecx, ecx
.next:
    cmp ecx, UBT_MAX_CHANS
    jae .none
    mov rax, [r8 + ubt_adapter.chans + rcx * 8]
    inc ecx
    test rax, rax
    jz .next
    cmp [rax + l2cap_chan.conn], rdi
    jne .next
    cmp [rax + rdx], si
    jne .next
    ret
.none:
    xor eax, eax
    ret

; l2cap_chan_free — RDI = chan: off the adapter's list, given back
global l2cap_chan_free
l2cap_chan_free:
    push rbx
    mov rbx, rdi
    mov rax, [rbx + l2cap_chan.conn]
    mov rax, [rax + ubt_conn.adapter]
    xor ecx, ecx
.next:
    cmp ecx, UBT_MAX_CHANS
    jae .free
    cmp [rax + ubt_adapter.chans + rcx * 8], rbx
    jne .skip
    mov qword [rax + ubt_adapter.chans + rcx * 8], 0
.skip:
    inc ecx
    jmp .next
.free:
    mov rdi, rbx
    call l2cap_mode_free                ; what a mode keeps
    mov rdi, rbx
    mov esi, l2cap_chan_size
    mov edx, 8
    call usb_free
    pop rbx
    ret

; l2cap_event — RDI = chan, ESI = event, EDX = why: to its user
global l2cap_event
l2cap_event:
    mov rax, [rdi + l2cap_chan.ops]
    test rax, rax
    jz .out
    mov rax, [rax + l2cap_ops.event]
    test rax, rax
    jz .out
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; l2cap_close — RDI = chan, ESI = event (CLOSED or REFUSED), EDX = why:
; told, then freed
global l2cap_close
l2cap_close:
    push rbx
    mov rbx, rdi
    mov byte [rbx + l2cap_chan.state], L2CAP_CLOSED
    call l2cap_event
    mov rdi, rbx
    call l2cap_chan_free
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_frame — RDI = conn, ESI = CID, RDX = payload, ECX = length: one
;               B-frame out. EAX = 0 or negative
; -----------------------------------------------------------------------------
global l2cap_frame
l2cap_frame:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov r15d, ecx
    lea edi, [r15d + 4]
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .nomem
    mov rbx, rax
    mov [rbx], r15w
    mov [rbx + 2], r13w
    lea rdi, [rbx + 4]
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    mov rdi, r12
    mov rsi, rbx
    lea edx, [r15d + 4]
    call ubt_conn_send
    mov r13d, eax
    mov rdi, rbx
    lea esi, [r15d + 4]
    mov edx, 8
    call usb_free
    mov eax, r13d
    jmp .out
.nomem:
    mov eax, -UBT_ENOMEM
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_conn_up — RDI = conn: a new link. BR/EDR: what the peer's L2CAP can
;                 do is asked first (extended features, then fixed channels)
; -----------------------------------------------------------------------------
global l2cap_conn_up
l2cap_conn_up:
    cmp byte [rdi + ubt_conn.type], UBT_LINK_LE
    jne .bredr
    mov byte [rdi + ubt_conn.info_state], 2     ; LE has nothing to ask
    ret
.bredr:
    mov byte [rdi + ubt_conn.info_state], 1
    mov esi, L2CAP_IT_FEAT_MASK
    jmp l2cap_sig_info_req

; -----------------------------------------------------------------------------
; l2cap_conn_down — RDI = conn: its link is gone; every channel on it closed
; -----------------------------------------------------------------------------
global l2cap_conn_down
l2cap_conn_down:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, [r12 + ubt_conn.adapter]
    xor r13d, r13d
.next:
    cmp r13d, UBT_MAX_CHANS
    jae .out
    mov rdi, [rbx + ubt_adapter.chans + r13 * 8]
    inc r13d
    test rdi, rdi
    jz .next
    cmp [rdi + l2cap_chan.conn], r12
    jne .next
    mov esi, L2CAP_EV_CLOSED
    mov edx, L2CAP_WHY_LINK
    call l2cap_close
    jmp .next
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_recv — RDI = conn, RSI = a whole frame (basic header first), EDX =
;              its length
; -----------------------------------------------------------------------------
global l2cap_recv
l2cap_recv:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    cmp edx, 4
    jb .drop
    movzx r13d, word [r12]              ; payload length
    lea eax, [r13d + 4]
    cmp eax, edx
    jne .drop                           ; not what the header says
    movzx r14d, word [r12 + 2]          ; CID
    lea rsi, [r12 + 4]
    mov edx, r13d
    cmp r14d, L2CAP_CID_SIGNALING
    je .signaling
    cmp r14d, L2CAP_CID_LE_SIGNALING
    je .le_signaling
    cmp r14d, L2CAP_CID_DYN_START
    jb .fixed
    ; a dynamic channel
    mov rdi, rbx
    mov esi, r14d
    call l2cap_find_scid
    test rax, rax
    jz .drop
    cmp byte [rax + l2cap_chan.state], L2CAP_OPEN
    jne .drop
    mov rdi, rax
    lea rsi, [r12 + 4]
    mov edx, r13d
    call l2cap_mode_recv
    jmp .out
.signaling:
    cmp byte [rbx + ubt_conn.type], UBT_LINK_BREDR
    jne .drop
    mov rdi, rbx
    call l2cap_sig_recv
    jmp .out
.le_signaling:
    cmp byte [rbx + ubt_conn.type], UBT_LINK_LE
    jne .drop
    mov rdi, rbx
    call l2cap_sig_le_recv
    jmp .out
.fixed:
    cmp byte [rbx + ubt_conn.type], UBT_LINK_LE
    jne .fixed_hook
    mov rdi, rbx
    cmp r14d, L2CAP_CID_LE_SMP
    jne .att
    call ubt_smp_recv                   ; SMP: the Security Manager
    jmp .out
.att:
    cmp r14d, L2CAP_CID_ATT
    jne .fixed_hook
    call ubt_att_recv                   ; ATT: the GATT server and client
    jmp .out
.fixed_hook:
    mov rax, [rbx + ubt_conn.adapter]
    mov rax, [rax + ubt_adapter.fixed_fn]
    test rax, rax
    jz .drop
    mov rdi, rbx
    mov rcx, rdx                        ; length
    mov rdx, rsi                        ; data
    mov esi, r14d                       ; CID
    call rax
    jmp .out
.drop:
    inc dword [rel l2cap_dropped]
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_mode_recv — RDI = an open chan, RSI = payload, EDX = length: by mode
; l2cap_mode_send — RDI = an open chan, RSI = SDU, EDX = length → EAX
; l2cap_mode_free — RDI = chan: what its mode keeps given back
; -----------------------------------------------------------------------------
l2cap_mode_recv:
    cmp byte [rdi + l2cap_chan.mode], L2CAP_MODE_BASIC
    jne l2cap_mode_recv_other
    ; basic: one frame, one SDU, no larger than we said we take
    movzx eax, word [rdi + l2cap_chan.imtu]
    cmp edx, eax
    ja .too_long
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
.too_long:
    inc dword [rel l2cap_dropped]
    ret

l2cap_mode_send:
    cmp byte [rdi + l2cap_chan.mode], L2CAP_MODE_BASIC
    jne l2cap_mode_send_other
    movzx eax, word [rdi + l2cap_chan.omtu]
    cmp edx, eax
    ja .too_long
    mov ecx, edx
    mov rdx, rsi
    movzx esi, word [rdi + l2cap_chan.dcid]
    mov rdi, [rdi + l2cap_chan.conn]
    jmp l2cap_frame
.too_long:
    mov eax, -UBT_EIO
    ret

; the other modes: ERTM and streaming (l2cap/ertm.asm), credit based
; (l2cap/credit.asm)
l2cap_mode_recv_other:
    cmp qword [rdi + l2cap_chan.ertm], 0
    jne l2cap_ertm_recv
    cmp qword [rdi + l2cap_chan.cred], 0
    jne l2cap_cred_recv
    inc dword [rel l2cap_dropped]
    ret
l2cap_mode_send_other:
    cmp qword [rdi + l2cap_chan.ertm], 0
    jne l2cap_ertm_send
    cmp qword [rdi + l2cap_chan.cred], 0
    jne l2cap_cred_send
    mov eax, -UBT_EIO
    ret
l2cap_mode_free:
    push rdi                            ; each: nothing when there is no state
    call l2cap_ertm_free
    pop rdi
    jmp l2cap_cred_free

; -----------------------------------------------------------------------------
; l2cap_connect — RDI = conn, ESI = PSM, EDX = mode, RCX = ops, R8 = user
; Output: RAX = chan (opening), or 0
; BR/EDR: basic, ERTM, streaming, enhanced credit based. LE: LE credit
; based, enhanced credit based.
; -----------------------------------------------------------------------------
global l2cap_connect
l2cap_connect:
    push rbx
    call l2cap_chan_make
    test rax, rax
    jz .out
    mov rbx, rax
    mov rcx, [rax + l2cap_chan.conn]
    cmp byte [rcx + ubt_conn.info_state], 2
    jne .later                          ; asked when the peer's answer comes
    mov rdi, rax
    call l2cap_sig_conn_req
.later:
    mov rax, rbx
.out:
    pop rbx
    ret

; l2cap_chan_make — RDI = conn, ESI = PSM, EDX = mode, RCX = ops, R8 = user
; → RAX = a new outgoing channel waiting to ask, or 0 when the link cannot
; carry that mode or there is no room
global l2cap_chan_make
l2cap_chan_make:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push r8
    sub rsp, 8                          ; [rsp] the channel, [+8] user
    mov r12, rdi
    mov r13d, esi
    mov r14d, edx
    mov r15, rcx
    mov rbx, [r12 + ubt_conn.adapter]
    cmp r14d, L2CAP_MODE_ECRED
    je .mode_ok
    cmp byte [r12 + ubt_conn.type], UBT_LINK_BREDR
    jne .le
    cmp r14d, L2CAP_MODE_BASIC
    je .mode_ok
    cmp r14d, L2CAP_MODE_ERTM
    je .mode_ok
    cmp r14d, L2CAP_MODE_STREAMING
    je .mode_ok
    jmp .refuse
.le:
    cmp r14d, L2CAP_MODE_LE_CREDITS
    jne .refuse
.mode_ok:
    mov rdi, r12
    call l2cap_chan_new
    test rax, rax
    jz .refuse
    mov [rsp], rax
    cmp r14d, L2CAP_MODE_LE_CREDITS
    jb .fields
    mov rdi, rax
    call l2cap_cred_new
    test eax, eax
    jz .fields
    mov rdi, [rsp]
    call l2cap_chan_free
    jmp .refuse
.fields:
    mov rdi, [rsp]
    mov [rdi + l2cap_chan.psm], r13w
    mov [rdi + l2cap_chan.mode], r14b
    mov [rdi + l2cap_chan.ops], r15
    mov rax, [rsp + 8]
    mov [rdi + l2cap_chan.user], rax
    mov byte [rdi + l2cap_chan.outgoing], 1
    mov byte [rdi + l2cap_chan.state], L2CAP_WAIT_INFO
    call l2cap_rtx
    mov rdi, [rsp]
    mov [rdi + l2cap_chan.deadline], rax
    mov rax, rdi
    jmp .out
.refuse:
    xor eax, eax
.out:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_send — RDI = chan, RSI = SDU, EDX = length → EAX = 0 or negative
; -----------------------------------------------------------------------------
global l2cap_send
l2cap_send:
    mov eax, -UBT_EDOWN
    cmp byte [rdi + l2cap_chan.state], L2CAP_OPEN
    jne .out
    jmp l2cap_mode_send
.out:
    ret

; -----------------------------------------------------------------------------
; l2cap_disconnect — RDI = chan: Disconnection Request; closed when the
;                    answer comes (or its time runs out)
; -----------------------------------------------------------------------------
global l2cap_disconnect
l2cap_disconnect:
    push rbx
    mov rbx, rdi
    cmp byte [rbx + l2cap_chan.state], L2CAP_WAIT_INFO
    jne .ask
    ; nothing sent yet: just closed
    mov esi, L2CAP_EV_CLOSED
    xor edx, edx
    call l2cap_close
    jmp .out
.ask:
    mov byte [rbx + l2cap_chan.state], L2CAP_WAIT_DISCONNECT
    mov rax, [rbx + l2cap_chan.conn]
    push rbx
    sub rsp, 8                          ; aligned: the clock is a hook
    mov rbx, [rax + ubt_conn.adapter]
    call l2cap_rtx
    add rsp, 8
    pop rbx
    mov [rbx + l2cap_chan.deadline], rax
    mov rdi, rbx
    call l2cap_sig_disconn_req
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_echo — RDI = conn, RSI = data, EDX = length: an Echo Request
; -----------------------------------------------------------------------------
global l2cap_echo
l2cap_echo:
    sub rsp, 8
    mov ecx, edx
    mov rdx, rsi
    call l2cap_next_ident
    mov esi, L2CAP_ECHO_REQ
    call l2cap_sig_send
    add rsp, 8
    ret

; l2cap_next_ident — RDI = conn → R8D = a signalling identifier (1-255)
global l2cap_next_ident
l2cap_next_ident:
    movzx r8d, byte [rdi + ubt_conn.ident]
    inc byte [rdi + ubt_conn.ident]
    jnz .ok
    mov byte [rdi + ubt_conn.ident], 1  ; 0 is not an identifier
.ok:
    test r8d, r8d
    jnz .out
    mov r8d, 1
.out:
    ret

; -----------------------------------------------------------------------------
; l2cap_tick — RDI = adapter: answers that did not come in time
; -----------------------------------------------------------------------------
global l2cap_tick
l2cap_tick:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    call ubt_now
    test rax, rax
    jz .out
    mov r13, rax
    xor r12d, r12d
.next:
    cmp r12d, UBT_MAX_CHANS
    jae .out
    mov rdi, [rbx + ubt_adapter.chans + r12 * 8]
    inc r12d
    test rdi, rdi
    jz .next
    ; an open ERTM channel's own timers
    cmp byte [rdi + l2cap_chan.state], L2CAP_OPEN
    jne .signalling
    cmp qword [rdi + l2cap_chan.ertm], 0
    je .signalling
    push rdi
    sub rsp, 8
    mov rsi, r13
    call l2cap_ertm_tick
    add rsp, 8
    pop rdi
    mov rax, [rbx + ubt_adapter.chans + r12 * 8 - 8]
    cmp rax, rdi
    jne .next                           ; it closed
.signalling:
    mov rax, [rdi + l2cap_chan.deadline]
    test rax, rax
    jz .next
    cmp r13, rax
    jb .next
    movzx eax, byte [rdi + l2cap_chan.state]
    cmp eax, L2CAP_WAIT_INFO
    je .no_info
    cmp eax, L2CAP_OPEN
    je .clear
    ; waiting to connect, configure or disconnect: given up
    mov esi, L2CAP_EV_CLOSED
    mov edx, L2CAP_WHY_TIMEOUT
    call l2cap_close
    jmp .next
.no_info:
    ; the peer never said what it does: assume only the basics, carry on
    mov rax, [rdi + l2cap_chan.conn]
    mov byte [rax + ubt_conn.info_state], 2
    push rdi
    sub rsp, 8
    call l2cap_resume_conn
    add rsp, 8
    pop rdi
    jmp .next
.clear:
    mov qword [rdi + l2cap_chan.deadline], 0
    jmp .next
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_resume_conn — RDI = a channel of a link whose peer is now known:
;                     every outgoing channel waiting on that link asks now
; -----------------------------------------------------------------------------
global l2cap_resume_conn
l2cap_resume_conn:
    mov rdi, [rdi + l2cap_chan.conn]
; l2cap_resume — RDI = conn
global l2cap_resume
l2cap_resume:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, [r12 + ubt_conn.adapter]
    xor r13d, r13d
.next:
    cmp r13d, UBT_MAX_CHANS
    jae .out
    mov rdi, [rbx + ubt_adapter.chans + r13 * 8]
    inc r13d
    test rdi, rdi
    jz .next
    cmp [rdi + l2cap_chan.conn], r12
    jne .next
    cmp byte [rdi + l2cap_chan.state], L2CAP_WAIT_INFO
    jne .next
    call l2cap_sig_conn_req
    jmp .next
.out:
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_UBT_L2CAP_CORE_ASM
