; =============================================================================
; Utkarsha OS — lib/ubt/hci/conn.asm — ACL links
; =============================================================================
;   ubt_connect(adapter, bdaddr)            BR/EDR: Create Connection
;   ubt_le_connect(adapter, addr, type)     LE: Create Connection
;   ubt_disconnect(conn, reason)            Disconnect
;   ubt_conn_event(adapter, event, len)     the link events: Connection
;                       Request (accepted), Connection Complete, LE
;                       (Enhanced) Connection Complete, Disconnection
;                       Complete, Number of Completed Packets
;   ubt_conn_send(conn, frame, len)         an L2CAP frame out: cut to the
;                       controller's buffer size, each fragment sent when
;                       the controller has a buffer free
;   ubt_conn_pump(adapter)                  send what waits, as buffers free
;   ubt_acl_input(adapter, packet, len)     an ACL packet in: whole L2CAP
;                       frames, put back together, to l2cap_recv
;   ubt_conn_find(adapter, handle)
;   ubt_acl_send(adapter, packet, len)      one raw ACL packet to the transport
;   ubt_conns_drop(adapter)                 the adapter went: every link closed
;
; Commands here are sent without waiting (ubt_hci_async): events about
; them arrive later, and a link exists once its Complete event says so.
; =============================================================================

%ifndef LIB_UBT_HCI_CONN_ASM
%define LIB_UBT_HCI_CONN_ASM

section .bss
global ubt_conn_dropped
ubt_conn_dropped:   resd 1          ; ACL data that fitted no frame or link

section .text

; -----------------------------------------------------------------------------
; ubt_conn_find — RDI = adapter, ESI = handle → RAX = conn, or 0
; -----------------------------------------------------------------------------
global ubt_conn_find
ubt_conn_find:
    and esi, 0x0FFF
    xor ecx, ecx
.next:
    cmp ecx, UBT_MAX_CONNS
    jae .none
    mov rax, [rdi + ubt_adapter.conns + rcx * 8]
    inc ecx
    test rax, rax
    jz .next
    movzx edx, word [rax + ubt_conn.handle]
    cmp edx, esi
    jne .next
    ret
.none:
    xor eax, eax
    ret

; ubt_conn_notify — the adapter's conn_fn: RBX = adapter, ESI = event,
; RDX = conn
ubt_conn_notify:
    mov rax, [rbx + ubt_adapter.conn_fn]
    test rax, rax
    jz .out
    mov rdi, rbx
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; -----------------------------------------------------------------------------
; ubt_connect — RDI = adapter, RSI = the peer's address (6 bytes)
; Output: EAX = 0 (asked for), or negative
; -----------------------------------------------------------------------------
global ubt_connect
ubt_connect:
    push rbx
    sub rsp, 16                         ; the parameters
    mov rbx, rdi
    mov eax, [rsi]
    mov [rsp], eax
    mov [rbx + ubt_adapter.connecting], eax
    mov ax, [rsi + 4]
    mov [rsp + 4], ax
    mov [rbx + ubt_adapter.connecting + 4], ax
    mov byte [rbx + ubt_adapter.connecting_on], 1
    mov word [rsp + 6], 0xCC18          ; packet types: DM1 DH1 DM3 DH3 DM5 DH5
    mov byte [rsp + 8], 1               ; page scan repetition mode R1
    mov byte [rsp + 9], 0
    mov word [rsp + 10], 0              ; clock offset unknown
    mov byte [rsp + 12], 1              ; role switch allowed
    mov rdi, rbx
    mov esi, HCI_CREATE_CONN
    mov rdx, rsp
    mov ecx, 13
    call ubt_hci_async
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_le_connect — RDI = adapter, RSI = address, EDX = its type (0 public,
;                  1 random)
; -----------------------------------------------------------------------------
global ubt_le_connect
ubt_le_connect:
    sub rsp, 40
    mov word [rsp], 0x0060              ; scan interval, window: 60 ms, 30 ms
    mov word [rsp + 2], 0x0030
    mov byte [rsp + 4], 0               ; this address, not the accept list
    mov [rsp + 5], dl
    mov eax, [rsi]
    mov [rsp + 6], eax
    mov ax, [rsi + 4]
    mov [rsp + 10], ax
    mov byte [rsp + 12], 0              ; own address public
    mov word [rsp + 13], 0x0018         ; interval 30-50 ms
    mov word [rsp + 15], 0x0028
    mov word [rsp + 17], 0              ; latency
    mov word [rsp + 19], 0x01F4         ; supervision timeout 5 s
    mov word [rsp + 21], 0
    mov word [rsp + 23], 0
    mov rdx, rsp
    mov esi, HCI_LE_CREATE_CONN
    mov ecx, 25
    call ubt_hci_async
    add rsp, 40
    ret

; -----------------------------------------------------------------------------
; ubt_disconnect — RDI = conn, ESI = reason (0x13: remote user terminated)
; -----------------------------------------------------------------------------
global ubt_disconnect
ubt_disconnect:
    sub rsp, 8
    mov ax, [rdi + ubt_conn.handle]
    mov [rsp], ax
    mov [rsp + 2], sil
    mov byte [rdi + ubt_conn.state], 2
    mov rdi, [rdi + ubt_conn.adapter]
    mov esi, HCI_DISCONNECT
    mov rdx, rsp
    mov ecx, 3
    call ubt_hci_async
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_conn_add — a link that came up: RBX = adapter, EDI = handle, ESI =
;                type, EDX = role, RCX = peer address, R8D = peer type
; Output: RAX = conn, or 0 (no room)
; -----------------------------------------------------------------------------
ubt_conn_add:
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15, rcx
    mov ebp, r8d
    xor ecx, ecx
.slot:
    cmp ecx, UBT_MAX_CONNS
    jae .full
    cmp qword [rbx + ubt_adapter.conns + rcx * 8], 0
    je .free
    inc ecx
    jmp .slot
.free:
    push rcx
    sub rsp, 8                          ; aligned for the allocator's hook
    mov edi, ubt_conn_size
    mov esi, 8
    call usb_alloc
    add rsp, 8
    pop rcx
    test rax, rax
    jz .full
    mov [rbx + ubt_adapter.conns + rcx * 8], rax
    mov [rax + ubt_conn.adapter], rbx
    mov [rax + ubt_conn.handle], r12w
    mov [rax + ubt_conn.type], r13b
    mov [rax + ubt_conn.role], r14b
    mov ecx, [r15]
    mov [rax + ubt_conn.peer], ecx
    mov cx, [r15 + 4]
    mov [rax + ubt_conn.peer + 4], cx
    mov [rax + ubt_conn.peer_type], bpl
    mov byte [rax + ubt_conn.state], 1
    mov byte [rax + ubt_conn.ident], 1
    jmp .out
.full:
    xor eax, eax
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; ubt_conn_free — RBX = adapter, RDI = conn: off the table, its queue and
; reassembly buffer given back
ubt_conn_free:
    push r12
    push r13
    sub rsp, 8
    mov r12, rdi
    xor ecx, ecx
.slot:
    cmp ecx, UBT_MAX_CONNS
    jae .queue
    cmp [rbx + ubt_adapter.conns + rcx * 8], r12
    jne .slot_next
    mov qword [rbx + ubt_adapter.conns + rcx * 8], 0
.slot_next:
    inc ecx
    jmp .slot
.queue:
    mov r13, [r12 + ubt_conn.tx_head]
.txb:
    test r13, r13
    jz .rx
    mov rdi, r13
    mov esi, [r13 + ubt_txb.size]
    mov r13, [r13 + ubt_txb.next]
    mov edx, 8
    call usb_free
    jmp .txb
.rx:
    mov rdi, [r12 + ubt_conn.rx_buf]
    mov esi, UBT_L2CAP_RX_MAX
    mov edx, 8
    call usb_free
    ; what the controller still had of ours is its again
    mov eax, [r12 + ubt_conn.in_flight]
    cmp byte [r12 + ubt_conn.type], UBT_LINK_LE
    jne .br_credit
    cmp word [rbx + ubt_adapter.le_count], 0
    je .br_credit
    add [rbx + ubt_adapter.le_free], eax
    jmp .release
.br_credit:
    add [rbx + ubt_adapter.acl_free], eax
.release:
    mov rdi, r12                        ; what the upper layers kept
    call ubt_layers_free
    mov rdi, r12
    mov esi, ubt_conn_size
    mov edx, 8
    call usb_free
    add rsp, 8
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; ubt_conn_event — RDI = adapter, RSI = event, EDX = length
; Output: EAX = 1 when it was a link event (the event is still given to
;         event_fn afterwards)
; -----------------------------------------------------------------------------
global ubt_conn_event
ubt_conn_event:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    movzx eax, byte [r12]
    cmp eax, HCI_EV_CONN_COMPLETE
    je .complete
    cmp eax, HCI_EV_CONN_REQUEST
    je .request
    cmp eax, HCI_EV_DISCONNECT
    je .disconnect
    cmp eax, HCI_EV_NUM_COMPLETED
    je .completed
    cmp eax, HCI_EV_LE_META
    je .le
    xor eax, eax
    jmp .out

.request:
    ; an ACL link asked for: accepted, staying peripheral
    cmp r13d, 2 + 10
    jb .handled
    cmp byte [r12 + 2 + 9], 1           ; link type ACL
    jne .handled
    sub rsp, 16
    mov eax, [r12 + 2]
    mov [rsp], eax
    mov ax, [r12 + 6]
    mov [rsp + 4], ax
    mov byte [rsp + 6], 1
    mov rdi, rbx
    mov esi, HCI_ACCEPT_CONN
    mov rdx, rsp
    mov ecx, 7
    call ubt_hci_async
    add rsp, 16
    jmp .handled

.complete:
    ; status, handle, address, link type, encryption
    cmp r13d, 2 + 11
    jb .handled
    cmp byte [r12 + 2 + 9], 1
    jne .handled                        ; SCO: not here
    ; ours if it is the address we were connecting to
    xor r14d, r14d
    cmp byte [rbx + ubt_adapter.connecting_on], 0
    je .who
    mov eax, [r12 + 5]
    cmp eax, [rbx + ubt_adapter.connecting]
    jne .who
    mov ax, [r12 + 9]
    cmp ax, [rbx + ubt_adapter.connecting + 4]
    jne .who
    mov r14d, 1                         ; we asked for it
    mov byte [rbx + ubt_adapter.connecting_on], 0
.who:
    cmp byte [r12 + 2], 0
    jne .failed
    movzx edi, word [r12 + 3]
    mov esi, UBT_LINK_BREDR
    mov edx, r14d
    xor edx, 1                          ; we asked: central (0)
    lea rcx, [r12 + 5]
    xor r8d, r8d
    call ubt_conn_add
    test rax, rax
    jz .handled
    mov r15, rax
    mov esi, UBT_CONN_UP
    mov rdx, r15
    call ubt_conn_notify
    mov rdi, r15
    call l2cap_conn_up
    jmp .handled
.failed:
    test r14d, r14d
    jz .handled
    mov esi, UBT_CONN_FAILED
    xor edx, edx
    call ubt_conn_notify
    jmp .handled

.le:
    cmp r13d, 2 + 19
    jb .not_ours
    movzx eax, byte [r12 + 2]
    cmp eax, HCI_LE_EV_CONN_COMPLETE
    je .le_complete
    cmp eax, HCI_LE_EV_ENH_CONN_COMPLETE
    jne .not_ours
.le_complete:
    ; subevent, status, handle, role, peer type, peer address, ...
    cmp byte [r12 + 3], 0
    jne .le_failed
    movzx edi, word [r12 + 4]
    mov esi, UBT_LINK_LE
    movzx edx, byte [r12 + 6]
    lea rcx, [r12 + 8]
    movzx r8d, byte [r12 + 7]
    call ubt_conn_add
    test rax, rax
    jz .handled
    mov r15, rax
    mov esi, UBT_CONN_UP
    mov rdx, r15
    call ubt_conn_notify
    mov rdi, r15
    call l2cap_conn_up
    jmp .handled
.le_failed:
    mov esi, UBT_CONN_FAILED
    xor edx, edx
    call ubt_conn_notify
    jmp .handled

.disconnect:
    ; status, handle, reason
    cmp r13d, 2 + 4
    jb .handled
    cmp byte [r12 + 2], 0
    jne .handled
    mov rdi, rbx
    movzx esi, word [r12 + 3]
    call ubt_conn_find
    test rax, rax
    jz .handled
    mov r15, rax
    mov rdi, r15
    call l2cap_conn_down                ; its channels closed
    mov esi, UBT_CONN_DOWN
    mov rdx, r15
    call ubt_conn_notify
    mov rdi, r15
    call ubt_conn_free
    call .pump
    jmp .handled

.completed:
    ; number of handles, then each handle and its count
    cmp r13d, 3
    jb .handled
    movzx r14d, byte [r12 + 2]
    lea r15, [r12 + 3]
.pair:
    test r14d, r14d
    jz .pumped
    lea rax, [r15 + 4]
    lea rcx, [r12 + r13]
    cmp rax, rcx
    ja .pumped                          ; shorter than it says
    mov rdi, rbx
    movzx esi, word [r15]
    call ubt_conn_find
    movzx ecx, word [r15 + 2]
    test rax, rax
    jz .pair_next
    sub [rax + ubt_conn.in_flight], ecx
    jns .credit
    mov dword [rax + ubt_conn.in_flight], 0
.credit:
    cmp byte [rax + ubt_conn.type], UBT_LINK_LE
    jne .credit_br
    cmp word [rbx + ubt_adapter.le_count], 0
    je .credit_br
    add [rbx + ubt_adapter.le_free], ecx
    jmp .pair_next
.credit_br:
    add [rbx + ubt_adapter.acl_free], ecx
.pair_next:
    add r15, 4
    dec r14d
    jmp .pair
.pumped:
    call .pump
.handled:
    mov eax, 1
    jmp .out
.not_ours:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.pump:
    sub rsp, 8
    mov rdi, rbx
    call ubt_conn_pump
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_conn_send — RDI = conn, RSI = an L2CAP frame, EDX = its length
; Output: EAX = 0, or -UBT_ENOMEM (nothing queued then)
; -----------------------------------------------------------------------------
global ubt_conn_send
ubt_conn_send:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24                         ; [rsp] first fragment, [+8] last
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov rbx, [r12 + ubt_conn.adapter]
    ; the controller's buffer size for this link
    movzx ebp, word [rbx + ubt_adapter.acl_mtu]
    cmp byte [r12 + ubt_conn.type], UBT_LINK_LE
    jne .mtu
    cmp word [rbx + ubt_adapter.le_count], 0
    je .mtu
    movzx ebp, word [rbx + ubt_adapter.le_mtu]
.mtu:
    test ebp, ebp
    jnz .mtu_ok
    mov ebp, 27                         ; the smallest any controller has
.mtu_ok:
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    xor r15d, r15d                      ; offset in the frame
.fragment:
    mov ecx, r14d
    sub ecx, r15d
    jz .queue
    cmp ecx, ebp
    jbe .size
    mov ecx, ebp
.size:
    mov [rsp + 16], ecx
    lea edi, [rcx + ubt_txb_size + 4]
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .nomem
    mov ecx, [rsp + 16]
    lea edi, [rcx + ubt_txb_size + 4]
    mov [rax + ubt_txb.size], edi
    lea edi, [rcx + 4]
    mov [rax + ubt_txb.len], edi
    mov qword [rax + ubt_txb.next], 0
    ; the ACL header: handle and boundary flags, then the length
    movzx edi, word [r12 + ubt_conn.handle]
    mov edx, ACL_PB_CONT << 12
    test r15d, r15d
    jnz .flags
    mov edx, ACL_PB_START_AUTO << 12
    cmp byte [r12 + ubt_conn.type], UBT_LINK_LE
    jne .flags
    mov edx, ACL_PB_START_NOFLUSH << 12
.flags:
    or edi, edx
    mov [rax + ubt_txb.data], di
    mov [rax + ubt_txb.data + 2], cx
    lea rdi, [rax + ubt_txb.data + 4]
    lea rsi, [r13 + r15]
    add r15d, ecx
    rep movsb
    ; onto this frame's list
    mov rcx, [rsp + 8]
    test rcx, rcx
    jz .first
    mov [rcx + ubt_txb.next], rax
    jmp .linked
.first:
    mov [rsp], rax
.linked:
    mov [rsp + 8], rax
    jmp .fragment
.queue:
    ; the whole frame onto the link's queue
    mov rax, [rsp]
    test rax, rax
    jz .sent
    mov rcx, [r12 + ubt_conn.tx_tail]
    test rcx, rcx
    jz .empty
    mov [rcx + ubt_txb.next], rax
    jmp .tail
.empty:
    mov [r12 + ubt_conn.tx_head], rax
.tail:
    mov rax, [rsp + 8]
    mov [r12 + ubt_conn.tx_tail], rax
    mov rdi, rbx
    call ubt_conn_pump
.sent:
    xor eax, eax
    jmp .out
.nomem:
    ; give back the fragments already made: nothing goes half
    mov r15, [rsp]
.unmake:
    test r15, r15
    jz .nomem_out
    mov rdi, r15
    mov esi, [r15 + ubt_txb.size]
    mov r15, [r15 + ubt_txb.next]
    mov edx, 8
    call usb_free
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

; -----------------------------------------------------------------------------
; ubt_conn_pump — RDI = adapter: fragments out while the controller has
; buffers and the transport takes them, one link after another
; -----------------------------------------------------------------------------
global ubt_conn_pump
ubt_conn_pump:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
.round:
    xor r15d, r15d                      ; anything sent this round
    xor r12d, r12d
.conn:
    cmp r12d, UBT_MAX_CONNS
    jae .round_end
    mov r13, [rbx + ubt_adapter.conns + r12 * 8]
    inc r12d
    test r13, r13
    jz .conn
    mov r14, [r13 + ubt_conn.tx_head]
    test r14, r14
    jz .conn
    ; a buffer of the right pool?
    lea rax, [rbx + ubt_adapter.acl_free]
    cmp byte [r13 + ubt_conn.type], UBT_LINK_LE
    jne .pool
    cmp word [rbx + ubt_adapter.le_count], 0
    je .pool
    lea rax, [rbx + ubt_adapter.le_free]
.pool:
    cmp dword [rax], 0
    jle .conn
    push rax
    sub rsp, 8
    mov rdi, rbx
    lea rsi, [r14 + ubt_txb.data]
    mov edx, [r14 + ubt_txb.len]
    call [rbx + ubt_adapter.tr_acl]
    test eax, eax
    jnz .not_sent                       ; (busy: it goes again later)
    mov rdi, rbx
    lea rsi, [r14 + ubt_txb.data]
    mov edx, [r14 + ubt_txb.len]
    call ubt_snoop_acl_out              ; (every register kept)
.not_sent:
    add rsp, 8
    pop rcx
    test eax, eax
    jnz .out                            ; the transport is busy: later
    dec dword [rcx]
    inc dword [r13 + ubt_conn.in_flight]
    mov rax, [r14 + ubt_txb.next]
    mov [r13 + ubt_conn.tx_head], rax
    test rax, rax
    jnz .unlinked
    mov qword [r13 + ubt_conn.tx_tail], 0
.unlinked:
    mov rdi, r14
    mov esi, [r14 + ubt_txb.size]
    mov edx, 8
    call usb_free
    mov r15d, 1
    jmp .conn
.round_end:
    test r15d, r15d
    jnz .round
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_acl_input — RDI = adapter, RSI = an ACL packet, EDX = its length
; -----------------------------------------------------------------------------
global ubt_acl_input
ubt_acl_input:
    call ubt_snoop_acl_in               ; (every register kept)
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    inc dword [rbx + ubt_adapter.acl_rx]
    mov rax, [rbx + ubt_adapter.acl_fn]
    test rax, rax
    jz .link
    mov rdi, rbx                        ; the raw packet first, to whoever asked
    mov rsi, r12
    mov edx, r13d
    call rax
.link:
    cmp r13d, 4
    jb .drop
    movzx eax, word [r12 + 2]
    add eax, 4
    cmp eax, r13d
    ja .drop
    mov r13d, eax                       ; what the header says, no more
    mov rdi, rbx
    movzx esi, word [r12]
    call ubt_conn_find
    test rax, rax
    jz .drop
    mov r14, rax
    movzx r15d, word [r12]
    shr r15d, 12
    and r15d, 3                         ; boundary flags
    lea rsi, [r12 + 4]
    lea ecx, [r13d - 4]                 ; the data
    cmp r15d, ACL_PB_CONT
    je .continue
    ; a frame starts: a half-made one is lost
    cmp dword [r14 + ubt_conn.rx_need], 0
    je .start
    inc dword [rel ubt_conn_dropped]
    mov dword [r14 + ubt_conn.rx_need], 0
.start:
    cmp ecx, 4
    jb .drop                            ; no room for even the L2CAP header
    movzx eax, word [rsi]
    add eax, 4                          ; the whole frame
    cmp ecx, eax
    jb .partial
    ; all of it here: straight on
    mov rdi, r14
    mov edx, eax
    call l2cap_recv
    jmp .out
.partial:
    cmp eax, UBT_L2CAP_RX_MAX
    ja .drop
    mov [r14 + ubt_conn.rx_need], eax
    mov dword [r14 + ubt_conn.rx_len], 0
    cmp qword [r14 + ubt_conn.rx_buf], 0
    jne .append
    push rsi
    push rcx
    mov edi, UBT_L2CAP_RX_MAX
    mov esi, 8
    call usb_alloc
    pop rcx
    pop rsi
    test rax, rax
    jz .lost
    mov [r14 + ubt_conn.rx_buf], rax
    jmp .append
.continue:
    cmp dword [r14 + ubt_conn.rx_need], 0
    je .drop                            ; nothing started
.append:
    mov eax, [r14 + ubt_conn.rx_len]
    lea edx, [eax + ecx]
    cmp edx, [r14 + ubt_conn.rx_need]
    ja .lost                            ; more than the frame said
    mov rdi, [r14 + ubt_conn.rx_buf]
    add rdi, rax
    mov [r14 + ubt_conn.rx_len], edx
    rep movsb
    cmp edx, [r14 + ubt_conn.rx_need]
    jb .out
    mov dword [r14 + ubt_conn.rx_need], 0
    mov rdi, r14
    mov rsi, [r14 + ubt_conn.rx_buf]
    call l2cap_recv
    jmp .out
.lost:
    mov dword [r14 + ubt_conn.rx_need], 0
.drop:
    inc dword [rel ubt_conn_dropped]
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_acl_send — RDI = adapter, RSI = ACL packet, EDX = length: straight to
;                the transport. EAX = 0, -UBT_EDOWN, -UBT_EBUSY, -UBT_EIO
; -----------------------------------------------------------------------------
global ubt_acl_send
ubt_acl_send:
    mov eax, -UBT_EDOWN
    cmp dword [rdi + ubt_adapter.state], UBT_UP
    jne .out
    call ubt_snoop_acl_out
    jmp [rdi + ubt_adapter.tr_acl]
.out:
    ret

; -----------------------------------------------------------------------------
; ubt_conns_drop — RBX = adapter (gone): every link's channels closed and
;                  the link freed
; -----------------------------------------------------------------------------
global ubt_conns_drop
ubt_conns_drop:
    push r12
    push r13
    sub rsp, 8
    xor r12d, r12d
.next:
    cmp r12d, UBT_MAX_CONNS
    jae .out
    mov r13, [rbx + ubt_adapter.conns + r12 * 8]
    inc r12d
    test r13, r13
    jz .next
    mov rdi, r13
    call l2cap_conn_down
    mov rdi, r13
    call ubt_conn_free
    jmp .next
.out:
    add rsp, 8
    pop r13
    pop r12
    ret

%endif ; LIB_UBT_HCI_CONN_ASM
