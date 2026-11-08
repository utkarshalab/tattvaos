; =============================================================================
; Utkarsha OS — lib/ubt/rfcomm/rfcomm.asm — RFCOMM (TS 07.10 over L2CAP)
; =============================================================================
;   ubt_rfcomm_init()                      the session server on PSM 3
;   ubt_rfcomm_server(channel, ops, user)  take connections to a channel (1-30)
;   ubt_rfcomm_connect(conn, channel, ops, user) → dlc (0: no room)
;   ubt_rfcomm_send(dlc, data, len) → EAX = 0, or negative
;   ubt_rfcomm_close(dlc)
; ops: recv(dlc, data, len); event(dlc, ESI = RFC_EV_*, EDX = why)
;
; One session per link (an L2CAP basic channel on PSM 3), the multiplexer
; control channel (DLCI 0) first, then data channels: Parameter
; Negotiation asking for credit-based flow control, SABM / UA, Modem
; Status both ways, data in UIH frames as credits allow, credits given
; back as they are used. Remote Port Negotiation, Remote Line Status and
; Test are answered, Flow Control On / Off followed; other multiplexer
; commands get Non Supported Command. Frames with a bad FCS are dropped;
; a channel nobody serves is refused (DM).
; =============================================================================

%ifndef LIB_UBT_RFCOMM_RFCOMM_ASM
%define LIB_UBT_RFCOMM_RFCOMM_ASM

%define RFC_PSM             3
%define RFC_SESSIONS        8
%define RFC_DLCS            16          ; data channels open at once (all links)
%define RFC_SERVERS         8
%define RFC_MTU             1000        ; the frame size we ask for and take
%define RFC_CREDITS         7           ; credits we give

; frame types (P/F bit 0x10 apart)
%define RFC_SABM            0x2F
%define RFC_UA              0x63
%define RFC_DM              0x0F
%define RFC_DISC            0x43
%define RFC_UIH             0xEF
%define RFC_PF              0x10

; multiplexer commands (type << 2, without C/R and EA)
%define MUX_PN              0x80
%define MUX_TEST            0x20
%define MUX_FCON            0xA0
%define MUX_FCOFF           0x60
%define MUX_MSC             0xE0
%define MUX_NSC             0x10
%define MUX_RPN             0x90
%define MUX_RLS             0x50

; events
%define RFC_EV_OPEN         1
%define RFC_EV_CLOSED       2
%define RFC_EV_REFUSED      3

; states
%define RFC_CLOSED          0
%define RFC_OPENING         1           ; session: L2CAP or SABM 0; dlc: PN, SABM
%define RFC_OPEN            2
%define RFC_CLOSING         3

struc ubt_rfc_session
    .conn:          resq 1
    .chan:          resq 1          ; L2CAP
    .state:         resb 1
    .initiator:     resb 1          ; we opened the L2CAP channel
    .pad:           resw 1
    .mtu:           resd 1          ; L2CAP's: the largest frame
endstruc

struc ubt_rfc_dlc
    .session:       resq 1
    .ops:           resq 1
    .user:          resq 1
    .dlci:          resb 1
    .state:         resb 1
    .cfc:           resb 1          ; credit-based flow control agreed
    .stopped:       resb 1          ; the peer said Flow Control Off
    .mtu:           resd 1          ; agreed frame size
    .tx_credits:    resd 1
    .rx_credits:    resd 1
    .sent_msc:      resb 1
    .got_msc:       resb 1
    .pad:           resw 1
    .pad2:          resd 1
    .txq:           resq 1          ; ubt_txb-style blocks: next, len, size, data
    .txq_tail:      resq 1
endstruc

struc rfc_srv
    .channel:       resd 1
    .pad:           resd 1
    .ops:           resq 1
    .user:          resq 1
endstruc

section .bss
alignb 8
ubt_rfc_sessions:   resq RFC_SESSIONS
global ubt_rfc_dlcs
ubt_rfc_dlcs:       resq RFC_DLCS
ubt_rfc_servers:    resb RFC_SERVERS * rfc_srv_size
global ubt_rfc_dropped
ubt_rfc_dropped:    resd 1          ; frames that did not check out

section .data
align 8
ubt_rfc_l2_ops:     dq ubt_rfc_l2_recv, ubt_rfc_l2_event

section .rodata
global ubt_rfc_layout
ubt_rfc_layout:
    dd ubt_rfc_session_size, ubt_rfc_dlc_size, ubt_rfc_dlc.tx_credits, ubt_rfc_dlc.rx_credits
    dd ubt_rfc_dlc.mtu, ubt_rfc_dlc.state, ubt_rfc_dlc.dlci, 0

section .text

; -----------------------------------------------------------------------------
; ubt_rfc_fcs — RSI = bytes, ECX = count → EAX = the FCS (CRC-8, x^8 + x^2 +
;               x + 1 reflected, from 0xFF, the result complemented)
; -----------------------------------------------------------------------------
global ubt_rfc_fcs
ubt_rfc_fcs:
    mov eax, 0xFF
    test ecx, ecx
    jz .done
.byte:
    movzx edx, byte [rsi]
    xor eax, edx
    mov edx, 8
.bit:
    shr eax, 1
    jnc .no
    xor eax, 0xE0
.no:
    dec edx
    jnz .bit
    inc rsi
    dec ecx
    jnz .byte
.done:
    xor eax, 0xFF
    ret

; -----------------------------------------------------------------------------
; ubt_rfcomm_init — the servers forgotten, the session server on PSM 3
; -----------------------------------------------------------------------------
global ubt_rfcomm_init
ubt_rfcomm_init:
    sub rsp, 8
    lea rdi, [rel ubt_rfc_servers]
    mov ecx, RFC_SERVERS * rfc_srv_size
    xor eax, eax
    rep stosb
    mov edi, RFC_PSM
    mov esi, L2CAP_MODE_BASIC
    lea rdx, [rel ubt_rfc_l2_ops]
    xor ecx, ecx
    call l2cap_server
    add rsp, 8
    ret

; ubt_rfcomm_server — EDI = channel (1-30), RSI = ops, RDX = user → EAX = 0,
; or -UBT_ENOMEM / -UBT_EBUSY
global ubt_rfcomm_server
ubt_rfcomm_server:
    lea r8, [rel ubt_rfc_servers]
    xor ecx, ecx
    xor r9d, r9d
.next:
    cmp ecx, RFC_SERVERS
    jae .add
    cmp [r8 + rfc_srv.channel], edi
    je .busy
    test r9, r9
    jnz .skip
    cmp dword [r8 + rfc_srv.channel], 0
    jne .skip
    mov r9, r8
.skip:
    add r8, rfc_srv_size
    inc ecx
    jmp .next
.add:
    mov eax, -UBT_ENOMEM
    test r9, r9
    jz .out
    mov [r9 + rfc_srv.channel], edi
    mov [r9 + rfc_srv.ops], rsi
    mov [r9 + rfc_srv.user], rdx
    xor eax, eax
.out:
    ret
.busy:
    mov eax, -UBT_EBUSY
    ret

; rfc_server_find — EDI = channel → RAX = its server, or 0
rfc_server_find:
    lea rax, [rel ubt_rfc_servers]
    xor ecx, ecx
.next:
    cmp ecx, RFC_SERVERS
    jae .none
    test edi, edi
    jz .none
    cmp [rax + rfc_srv.channel], edi
    je .out
    add rax, rfc_srv_size
    inc ecx
    jmp .next
.none:
    xor eax, eax
.out:
    ret

; ---- sessions --------------------------------------------------------------

; rfc_session_of — RDI = conn → RAX = its session, or 0
rfc_session_of:
    lea rdx, [rel ubt_rfc_sessions]
    xor ecx, ecx
.next:
    cmp ecx, RFC_SESSIONS
    jae .none
    mov rax, [rdx + rcx * 8]
    inc ecx
    test rax, rax
    jz .next
    cmp [rax + ubt_rfc_session.conn], rdi
    jne .next
    ret
.none:
    xor eax, eax
    ret

; rfc_session_new — RDI = conn, RSI = L2CAP channel (0: not yet) → RAX
rfc_session_new:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    lea rbx, [rel ubt_rfc_sessions]
    xor ecx, ecx
.slot:
    cmp ecx, RFC_SESSIONS
    jae .none
    cmp qword [rbx + rcx * 8], 0
    je .free
    inc ecx
    jmp .slot
.free:
    lea rbx, [rbx + rcx * 8]
    mov edi, ubt_rfc_session_size
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .out
    mov [rbx], rax
    mov [rax + ubt_rfc_session.conn], r12
    mov [rax + ubt_rfc_session.chan], r13
    mov dword [rax + ubt_rfc_session.mtu], RFC_MTU + 6
    jmp .out
.none:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; rfc_session_free — RDI = session: its channels told and freed, it freed
rfc_session_free:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    xor r12d, r12d
.dlc:
    cmp r12d, RFC_DLCS
    jae .self
    lea rax, [rel ubt_rfc_dlcs]
    mov rdi, [rax + r12 * 8]
    inc r12d
    test rdi, rdi
    jz .dlc
    cmp [rdi + ubt_rfc_dlc.session], rbx
    jne .dlc
    mov esi, RFC_EV_CLOSED
    cmp byte [rdi + ubt_rfc_dlc.state], RFC_OPEN
    je .tell
    mov esi, RFC_EV_REFUSED
.tell:
    mov edx, 0x1001                     ; the link or session went
    call rfc_dlc_end
    jmp .dlc
.self:
    lea rax, [rel ubt_rfc_sessions]
    xor ecx, ecx
.unlist:
    cmp ecx, RFC_SESSIONS
    jae .free
    cmp [rax + rcx * 8], rbx
    jne .skip
    mov qword [rax + rcx * 8], 0
.skip:
    inc ecx
    jmp .unlist
.free:
    mov rdi, rbx
    mov esi, ubt_rfc_session_size
    mov edx, 8
    call usb_free
    add rsp, 8
    pop r12
    pop rbx
    ret

; ---- channels ----------------------------------------------------------------

; rfc_dlc_find — RDI = session, ESI = DLCI → RAX = its channel, or 0
rfc_dlc_find:
    lea rdx, [rel ubt_rfc_dlcs]
    xor ecx, ecx
.next:
    cmp ecx, RFC_DLCS
    jae .none
    mov rax, [rdx + rcx * 8]
    inc ecx
    test rax, rax
    jz .next
    cmp [rax + ubt_rfc_dlc.session], rdi
    jne .next
    movzx r8d, byte [rax + ubt_rfc_dlc.dlci]
    cmp r8d, esi
    jne .next
    ret
.none:
    xor eax, eax
    ret

; rfc_dlc_new — RDI = session, ESI = DLCI, RDX = ops, RCX = user → RAX
rfc_dlc_new:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov r15, rcx
    lea rbx, [rel ubt_rfc_dlcs]
    xor ecx, ecx
.slot:
    cmp ecx, RFC_DLCS
    jae .none
    cmp qword [rbx + rcx * 8], 0
    je .free
    inc ecx
    jmp .slot
.free:
    lea rbx, [rbx + rcx * 8]
    mov edi, ubt_rfc_dlc_size
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .out
    mov [rbx], rax
    mov [rax + ubt_rfc_dlc.session], r12
    mov [rax + ubt_rfc_dlc.dlci], r13b
    mov [rax + ubt_rfc_dlc.ops], r14
    mov [rax + ubt_rfc_dlc.user], r15
    mov dword [rax + ubt_rfc_dlc.mtu], 127     ; until negotiated
    jmp .out
.none:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rfc_dlc_end — RDI = dlc, ESI = event, EDX = why: its user told, it freed
rfc_dlc_end:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    lea rax, [rel ubt_rfc_dlcs]
    xor ecx, ecx
.unlist:
    cmp ecx, RFC_DLCS
    jae .tell
    cmp [rax + rcx * 8], rbx
    jne .skip
    mov qword [rax + rcx * 8], 0
.skip:
    inc ecx
    jmp .unlist
.tell:
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    call rfc_event
    ; what waited to be sent
.queue:
    mov rdi, [rbx + ubt_rfc_dlc.txq]
    test rdi, rdi
    jz .free
    mov rax, [rdi]
    mov [rbx + ubt_rfc_dlc.txq], rax
    mov esi, [rdi + 12]
    mov edx, 8
    call usb_free
    jmp .queue
.free:
    mov rdi, rbx
    mov esi, ubt_rfc_dlc_size
    mov edx, 8
    call usb_free
    pop r13
    pop r12
    pop rbx
    ret

; rfc_event — RDI = dlc, ESI = event, EDX = why: to its user
rfc_event:
    mov rax, [rdi + ubt_rfc_dlc.ops]
    test rax, rax
    jz .out
    mov rax, [rax + 8]
    test rax, rax
    jz .out
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; ---- frames out ------------------------------------------------------------------

; rfc_frame — RBX = session, EDI = DLCI, ESI = control (P/F in it), EDX =
; 1 for a command, R8 = data, R9D = its length (with ECX = a credit byte to
; put first when it is not -1, for UIH): one frame out
rfc_frame:
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, RFC_MTU + 40
    mov r12d, edi
    mov r13d, esi
    mov r14, r8
    mov r15d, r9d
    mov ebp, ecx
    ; address: DLCI, C/R, EA. C/R is 1 for the initiator's commands and
    ; the responder's responses
    mov eax, edx
    xor al, [rbx + ubt_rfc_session.initiator]
    xor al, 1                           ; command from initiator: 1
    and eax, 1
    lea ecx, [r12 * 4 + 1]
    lea ecx, [rcx + rax * 2]
    mov [rsp], cl
    mov [rsp + 1], r13b
    ; length (one byte with EA up to 127, else two)
    lea eax, [r15d * 2 + 1]
    mov ecx, 3
    cmp r15d, 127
    jbe .short
    lea eax, [r15d * 2]
    mov [rsp + 2], al
    mov eax, r15d
    shr eax, 7
    mov [rsp + 3], al
    mov ecx, 4
    jmp .len
.short:
    mov [rsp + 2], al
.len:
    mov [rsp + 20 + RFC_MTU], ecx       ; the header's length
    lea rdi, [rsp + rcx]
    cmp ebp, -1
    je .data
    mov [rdi], bpl
    inc rdi
.data:
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    ; FCS: address and control (and length, but for UIH)
    mov ecx, 2
    mov eax, r13d
    and eax, ~RFC_PF
    cmp eax, RFC_UIH
    je .fcs
    mov ecx, [rsp + 20 + RFC_MTU]
.fcs:
    push rdi
    mov rsi, rsp
    add rsi, 8
    call ubt_rfc_fcs
    pop rdi
    mov [rdi], al
    inc rdi
    mov rdx, rdi
    sub rdx, rsp
    mov rdi, [rbx + ubt_rfc_session.chan]
    mov rsi, rsp
    call l2cap_send
    add rsp, RFC_MTU + 40
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; rfc_ctl — RBX = session, EDI = DLCI, ESI = control (SABM, UA, DM, DISC
; with P/F): a frame without data. Commands are SABM and DISC.
rfc_ctl:
    sub rsp, 8
    xor edx, edx
    mov eax, esi
    and eax, ~RFC_PF
    cmp eax, RFC_SABM
    je .command
    cmp eax, RFC_DISC
    jne .send
.command:
    mov edx, 1
.send:
    xor r9d, r9d
    xor r8d, r8d
    mov ecx, -1
    call rfc_frame
    add rsp, 8
    ret

; rfc_mux — RBX = session, EDI = type (MUX_*), ESI = 1 command / 0 response,
; RDX = values, ECX = their length: a multiplexer message on DLCI 0
rfc_mux:
    push r12
    sub rsp, 32
    lea eax, [rdi + 1]                  ; EA
    test esi, esi
    jz .type
    or eax, 2                           ; C/R: a command
.type:
    mov [rsp], al
    lea eax, [rcx * 2 + 1]
    mov [rsp + 1], al
    mov r12d, ecx
    lea rdi, [rsp + 2]
    mov rsi, rdx
    rep movsb
    ; UIH frames on DLCI 0 are commands of the sender
    xor edi, edi
    mov esi, RFC_UIH
    mov edx, 1
    mov r8, rsp
    lea r9d, [r12d + 2]
    mov ecx, -1
    call rfc_frame
    add rsp, 32
    pop r12
    ret

; rfc_pn — RBX = session, RDI = dlc, ESI = 1 command / 0 response: Parameter
; Negotiation for it (credit flow asked for / agreed, our MTU, our credits)
rfc_pn:
    sub rsp, 24
    mov al, [rdi + ubt_rfc_dlc.dlci]
    mov [rsp], al
    mov byte [rsp + 1], 0xF0            ; ask for credit-based flow control
    test esi, esi
    jnz .cl
    mov byte [rsp + 1], 0xE0            ; agreed
.cl:
    mov byte [rsp + 2], 7               ; priority
    mov byte [rsp + 3], 0
    mov eax, [rdi + ubt_rfc_dlc.mtu]
    mov [rsp + 4], ax
    mov byte [rsp + 6], 0
    mov byte [rsp + 7], RFC_CREDITS
    mov dword [rdi + ubt_rfc_dlc.rx_credits], RFC_CREDITS
    mov edi, MUX_PN
    mov rdx, rsp
    mov ecx, 8
    call rfc_mux
    add rsp, 24
    ret

; rfc_msc — RBX = session, EDI = DLCI, ESI = 1 command / 0 response, EDX =
; the V.24 signals: Modem Status
rfc_msc:
    sub rsp, 24
    lea eax, [rdi * 4 + 3]              ; DLCI, a 1, EA
    mov [rsp], al
    mov [rsp + 1], dl
    mov edi, MUX_MSC
    mov rdx, rsp
    mov ecx, 2
    call rfc_mux
    add rsp, 24
    ret

; rfc_give — RBX = session, RDI = dlc: credits topped up when half are used
; (an empty UIH with P/F and the credit byte)
rfc_give:
    cmp byte [rdi + ubt_rfc_dlc.cfc], 0
    je .out
    mov eax, RFC_CREDITS
    sub eax, [rdi + ubt_rfc_dlc.rx_credits]
    cmp eax, RFC_CREDITS / 2
    jb .out
    sub rsp, 8
    mov dword [rdi + ubt_rfc_dlc.rx_credits], RFC_CREDITS
    mov ecx, eax
    movzx edi, byte [rdi + ubt_rfc_dlc.dlci]
    mov esi, RFC_UIH | RFC_PF
    mov edx, 1
    xor r8d, r8d
    xor r9d, r9d
    call rfc_frame
    add rsp, 8
.out:
    ret

; rfc_pump — RBX = session, RDI = dlc: queued data out while credits last
rfc_pump:
    push r12
    push r13
    sub rsp, 8
    mov r12, rdi
.next:
    cmp byte [r12 + ubt_rfc_dlc.state], RFC_OPEN
    jne .out
    cmp byte [r12 + ubt_rfc_dlc.stopped], 0
    jne .out
    mov r13, [r12 + ubt_rfc_dlc.txq]
    test r13, r13
    jz .out
    cmp byte [r12 + ubt_rfc_dlc.cfc], 0
    je .send
    cmp dword [r12 + ubt_rfc_dlc.tx_credits], 0
    je .out
    dec dword [r12 + ubt_rfc_dlc.tx_credits]
.send:
    mov rax, [r13]
    mov [r12 + ubt_rfc_dlc.txq], rax
    test rax, rax
    jnz .frame
    mov qword [r12 + ubt_rfc_dlc.txq_tail], 0
.frame:
    movzx edi, byte [r12 + ubt_rfc_dlc.dlci]
    mov esi, RFC_UIH
    mov edx, 1
    lea r8, [r13 + 16]
    mov r9d, [r13 + 8]
    mov ecx, -1
    call rfc_frame
    mov rdi, r13
    mov esi, [r13 + 12]
    mov edx, 8
    call usb_free
    jmp .next
.out:
    add rsp, 8
    pop r13
    pop r12
    ret

; ---- the API ------------------------------------------------------------------

; -----------------------------------------------------------------------------
; ubt_rfcomm_connect — RDI = conn, ESI = the peer's server channel, RDX = ops,
;   RCX = user → RAX = the dlc (opening; ops.event says OPEN or REFUSED), or 0
; -----------------------------------------------------------------------------
global ubt_rfcomm_connect
ubt_rfcomm_connect:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov r15, rcx
    xor eax, eax
    test r13d, r13d
    jz .out
    cmp r13d, 30
    ja .out
    call rfc_session_of
    mov rbx, rax
    test rbx, rbx
    jnz .have
    ; a new session: L2CAP first
    mov rdi, r12
    xor esi, esi
    call rfc_session_new
    test rax, rax
    jz .out
    mov rbx, rax
    mov byte [rbx + ubt_rfc_session.initiator], 1
    mov byte [rbx + ubt_rfc_session.state], RFC_OPENING
    mov rdi, r12
    mov esi, RFC_PSM
    mov edx, L2CAP_MODE_BASIC
    lea rcx, [rel ubt_rfc_l2_ops]
    mov r8, rbx
    call l2cap_connect
    mov [rbx + ubt_rfc_session.chan], rax
    test rax, rax
    jnz .have
    mov rdi, rbx
    call rfc_session_free
    xor eax, eax
    jmp .out
.have:
    ; the DLCI: the server channel, the direction bit 0 for the initiator's
    ; peer's servers
    lea esi, [r13d * 2]
    movzx eax, byte [rbx + ubt_rfc_session.initiator]
    xor eax, 1
    or esi, eax
    mov rdi, rbx
    mov rdx, r14
    mov rcx, r15
    call rfc_dlc_new
    test rax, rax
    jz .out
    mov byte [rax + ubt_rfc_dlc.state], RFC_OPENING
    mov dword [rax + ubt_rfc_dlc.mtu], RFC_MTU
    cmp byte [rbx + ubt_rfc_session.state], RFC_OPEN
    jne .out                            ; asked once the session is up
    push rax
    sub rsp, 8
    mov rdi, rax
    mov esi, 1
    call rfc_pn
    add rsp, 8
    pop rax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_rfcomm_send — RDI = an open dlc, RSI = data, EDX = length
;   → EAX = 0 (queued, sent as credits allow), or negative
; -----------------------------------------------------------------------------
global ubt_rfcomm_send
ubt_rfcomm_send:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov eax, -UBT_EDOWN
    cmp byte [r12 + ubt_rfc_dlc.state], RFC_OPEN
    jne .out
    mov rbx, [r12 + ubt_rfc_dlc.session]
.piece:
    test r14d, r14d
    jz .sent
    mov r15d, [r12 + ubt_rfc_dlc.mtu]
    cmp r14d, r15d
    jae .room
    mov r15d, r14d
.room:
    lea edi, [r15d + 16]
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .nomem
    mov qword [rax], 0
    mov [rax + 8], r15d
    lea ecx, [r15d + 16]
    mov [rax + 12], ecx
    lea rdi, [rax + 16]
    mov rsi, r13
    mov ecx, r15d
    rep movsb
    add r13, r15
    sub r14d, r15d
    mov rcx, [r12 + ubt_rfc_dlc.txq_tail]
    test rcx, rcx
    jz .first
    mov [rcx], rax
    jmp .tail
.first:
    mov [r12 + ubt_rfc_dlc.txq], rax
.tail:
    mov [r12 + ubt_rfc_dlc.txq_tail], rax
    jmp .piece
.sent:
    mov rdi, r12
    call rfc_pump
    xor eax, eax
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

; ubt_rfcomm_close — RDI = dlc: DISC; closed when UA comes
global ubt_rfcomm_close
ubt_rfcomm_close:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    mov rbx, [r12 + ubt_rfc_dlc.session]
    cmp byte [r12 + ubt_rfc_dlc.state], RFC_OPEN
    jne .now
    mov byte [r12 + ubt_rfc_dlc.state], RFC_CLOSING
    movzx edi, byte [r12 + ubt_rfc_dlc.dlci]
    mov esi, RFC_DISC | RFC_PF
    call rfc_ctl
    jmp .out
.now:
    mov rdi, r12
    mov esi, RFC_EV_CLOSED
    xor edx, edx
    call rfc_dlc_end
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ---- L2CAP's side ---------------------------------------------------------------

; ubt_rfc_l2_event — RDI = L2CAP channel, ESI = event, EDX = why
ubt_rfc_l2_event:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    mov rbx, [r12 + l2cap_chan.user]
    test rbx, rbx
    jnz .known
    ; a session the peer opened: made now
    cmp esi, L2CAP_EV_OPEN
    jne .out
    mov rdi, [r12 + l2cap_chan.conn]
    mov rsi, r12
    call rfc_session_new
    test rax, rax
    jz .out
    mov rbx, rax
    mov [r12 + l2cap_chan.user], rbx
    mov byte [rbx + ubt_rfc_session.state], RFC_OPENING
    jmp .mtu
.known:
    cmp esi, L2CAP_EV_OPEN
    jne .gone
    ; ours: SABM on the control channel
.mtu:
    movzx eax, word [r12 + l2cap_chan.omtu]
    mov [rbx + ubt_rfc_session.mtu], eax
    cmp byte [rbx + ubt_rfc_session.initiator], 0
    je .out
    xor edi, edi
    mov esi, RFC_SABM | RFC_PF
    call rfc_ctl
    jmp .out
.gone:
    mov rdi, rbx
    call rfc_session_free
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_rfc_l2_recv — RDI = L2CAP channel, RSI = an RFCOMM frame, EDX = length
; -----------------------------------------------------------------------------
ubt_rfc_l2_recv:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 40
    mov rbx, [rdi + l2cap_chan.user]
    test rbx, rbx
    jz .out
    mov r12, rsi
    mov r13d, edx
    cmp r13d, 4
    jb .drop
    ; address, control, length (1 or 2 bytes)
    movzx r14d, byte [r12]
    shr r14d, 2                         ; DLCI
    movzx r15d, byte [r12 + 1]          ; control
    movzx eax, byte [r12 + 2]
    mov ebp, 3                          ; the header's length
    test eax, 1
    jnz .len1
    movzx ecx, byte [r12 + 3]
    shl ecx, 7
    shr eax, 1
    or eax, ecx
    mov ebp, 4
    jmp .len
.len1:
    shr eax, 1
.len:
    mov [rsp], eax                      ; the information's length
    ; a credit byte first in UIH with P/F when credit flow is on
    mov dword [rsp + 4], 0              ; credits in it
    mov ecx, r15d
    and ecx, ~RFC_PF
    cmp ecx, RFC_UIH
    jne .check_len
    test r15d, RFC_PF
    jz .check_len
    test r14d, r14d
    jz .check_len
    mov rdi, rbx
    mov esi, r14d
    call rfc_dlc_find
    test rax, rax
    jz .check_len
    cmp byte [rax + ubt_rfc_dlc.cfc], 0
    je .check_len
    lea ecx, [rbp + 1]
    cmp ecx, r13d
    jae .drop
    movzx ecx, byte [r12 + rbp]
    mov [rsp + 4], ecx
    inc ebp
.check_len:
    mov eax, [rsp]
    lea ecx, [rbp + rax + 1]
    cmp ecx, r13d
    jne .drop
    ; FCS over address and control (and length, but for UIH)
    mov ecx, 2
    mov eax, r15d
    and eax, ~RFC_PF
    cmp eax, RFC_UIH
    je .fcs
    mov ecx, 3
    test byte [r12 + 2], 1
    jnz .fcs
    mov ecx, 4
.fcs:
    mov rsi, r12
    call ubt_rfc_fcs
    lea ecx, [r13d - 1]
    cmp al, [r12 + rcx]
    jne .drop
    lea rax, [r12 + rbp]
    mov [rsp + 8], rax                  ; the information
    mov eax, r15d
    and eax, ~RFC_PF
    cmp eax, RFC_SABM
    je .sabm
    cmp eax, RFC_UA
    je .ua
    cmp eax, RFC_DM
    je .dm
    cmp eax, RFC_DISC
    je .disc
    cmp eax, RFC_UIH
    je .uih
.drop:
    inc dword [rel ubt_rfc_dropped]
.out:
    add rsp, 40
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.sabm:
    test r14d, r14d
    jnz .sabm_dlc
    ; the session: UA
    mov byte [rbx + ubt_rfc_session.state], RFC_OPEN
    xor edi, edi
    mov esi, RFC_UA | RFC_PF
    call rfc_ctl
    jmp .out
.sabm_dlc:
    ; a data channel: UA when negotiated (or a served channel), else DM
    mov rdi, rbx
    mov esi, r14d
    call rfc_dlc_find
    test rax, rax
    jnz .sabm_ok
    mov edi, r14d
    shr edi, 1
    call rfc_server_find
    test rax, rax
    jz .sabm_refuse
    mov rdi, rbx
    mov esi, r14d
    mov rdx, [rax + rfc_srv.ops]
    mov rcx, [rax + rfc_srv.user]
    call rfc_dlc_new
    test rax, rax
    jz .sabm_refuse
    mov dword [rax + ubt_rfc_dlc.mtu], RFC_MTU
.sabm_ok:
    mov [rsp + 16], rax
    mov byte [rax + ubt_rfc_dlc.state], RFC_OPENING
    mov edi, r14d
    mov esi, RFC_UA | RFC_PF
    call rfc_ctl
    ; then our Modem Status
    mov rax, [rsp + 16]
    mov byte [rax + ubt_rfc_dlc.sent_msc], 1
    mov edi, r14d
    mov esi, 1
    mov edx, 0x8D                       ; RTC, RTR, DV, EA
    call rfc_msc
    mov rax, [rsp + 16]
    cmp byte [rax + ubt_rfc_dlc.got_msc], 0
    jne .maybe_open
    jmp .out
.sabm_refuse:
    mov edi, r14d
    mov esi, RFC_DM | RFC_PF
    call rfc_ctl
    jmp .out

.ua:
    test r14d, r14d
    jnz .ua_dlc
    ; the session is up: every channel waiting negotiates
    mov byte [rbx + ubt_rfc_session.state], RFC_OPEN
    xor ebp, ebp
.ua_next:
    cmp ebp, RFC_DLCS
    jae .out
    lea rax, [rel ubt_rfc_dlcs]
    mov rdi, [rax + rbp * 8]
    inc ebp
    test rdi, rdi
    jz .ua_next
    cmp [rdi + ubt_rfc_dlc.session], rbx
    jne .ua_next
    mov esi, 1
    call rfc_pn
    jmp .ua_next
.ua_dlc:
    mov rdi, rbx
    mov esi, r14d
    call rfc_dlc_find
    test rax, rax
    jz .out
    cmp byte [rax + ubt_rfc_dlc.state], RFC_CLOSING
    je .closed
    ; opened: our Modem Status
    mov [rsp + 16], rax
    mov byte [rax + ubt_rfc_dlc.sent_msc], 1
    mov edi, r14d
    mov esi, 1
    mov edx, 0x8D
    call rfc_msc
    mov rax, [rsp + 16]
    cmp byte [rax + ubt_rfc_dlc.got_msc], 0
    jne .maybe_open
    jmp .out
.closed:
    mov rdi, rax
    mov esi, RFC_EV_CLOSED
    xor edx, edx
    call rfc_dlc_end
    jmp .out

.dm:
    mov rdi, rbx
    mov esi, r14d
    call rfc_dlc_find
    test rax, rax
    jz .out
    mov rdi, rax
    mov esi, RFC_EV_REFUSED
    cmp byte [rax + ubt_rfc_dlc.state], RFC_OPEN
    jne .dm_tell
    mov esi, RFC_EV_CLOSED
.dm_tell:
    xor edx, edx
    call rfc_dlc_end
    jmp .out

.disc:
    ; UA, then the channel (or the session) is gone
    mov edi, r14d
    mov esi, RFC_UA | RFC_PF
    call rfc_ctl
    test r14d, r14d
    jz .disc_session
    mov rdi, rbx
    mov esi, r14d
    call rfc_dlc_find
    test rax, rax
    jz .out
    mov rdi, rax
    mov esi, RFC_EV_CLOSED
    mov edx, 0x1002                     ; the peer closed it
    call rfc_dlc_end
    jmp .out
.disc_session:
    mov rdi, [rbx + ubt_rfc_session.chan]
    call l2cap_disconnect
    jmp .out

.uih:
    test r14d, r14d
    jz .mux
    mov rdi, rbx
    mov esi, r14d
    call rfc_dlc_find
    test rax, rax
    jz .out
    mov rbp, rax
    mov ecx, [rsp + 4]
    add [rbp + ubt_rfc_dlc.tx_credits], ecx
    mov eax, [rsp]
    test eax, eax
    jz .uih_pump
    cmp byte [rbp + ubt_rfc_dlc.state], RFC_OPEN
    jne .out
    cmp byte [rbp + ubt_rfc_dlc.cfc], 0
    je .uih_deliver
    cmp dword [rbp + ubt_rfc_dlc.rx_credits], 0
    je .drop                            ; sent without a credit
    dec dword [rbp + ubt_rfc_dlc.rx_credits]
.uih_deliver:
    mov rax, [rbp + ubt_rfc_dlc.ops]
    test rax, rax
    jz .uih_credit
    mov rax, [rax]
    test rax, rax
    jz .uih_credit
    mov rdi, rbp
    mov rsi, [rsp + 8]
    mov edx, [rsp]
    call rax
.uih_credit:
    mov rdi, rbp
    call rfc_give
.uih_pump:
    mov rdi, rbp
    call rfc_pump
    jmp .out

; ---- the multiplexer (DLCI 0): type, length, values ----------------------
.mux:
    mov rsi, [rsp + 8]
    mov eax, [rsp]
    cmp eax, 2
    jb .out
    movzx r15d, byte [rsi]              ; type with C/R and EA
    movzx ecx, byte [rsi + 1]
    shr ecx, 1                          ; its values' length
    lea edx, [rcx + 2]
    cmp edx, eax
    ja .out
    mov [rsp + 24], ecx
    lea rax, [rsi + 2]
    mov [rsp + 16], rax                 ; the values
    mov eax, r15d
    and eax, ~3
    test r15d, 2
    jz .mux_response
    cmp eax, MUX_PN
    je .pn_cmd
    cmp eax, MUX_MSC
    je .msc_cmd
    cmp eax, MUX_RPN
    je .echo
    cmp eax, MUX_RLS
    je .echo
    cmp eax, MUX_TEST
    je .echo
    cmp eax, MUX_FCON
    je .fcon
    cmp eax, MUX_FCOFF
    je .fcoff
    ; not one we know: Non Supported Command, naming it
    mov [rsp + 32], r15b
    mov edi, MUX_NSC
    xor esi, esi
    lea rdx, [rsp + 32]
    mov ecx, 1
    call rfc_mux
    jmp .out
.echo:
    ; answered with the same values
    mov edi, eax
    xor esi, esi
    mov rdx, [rsp + 16]
    mov ecx, [rsp + 24]
    call rfc_mux
    jmp .out
.fcon:
.fcoff:
    ; all channels of the session stopped or going again
    mov ecx, 1
    cmp eax, MUX_FCOFF
    je .fc_set
    xor ecx, ecx
.fc_set:
    mov [rsp + 32], ecx
    mov edi, eax
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call rfc_mux
    xor ebp, ebp
.fc_next:
    cmp ebp, RFC_DLCS
    jae .out
    lea rax, [rel ubt_rfc_dlcs]
    mov rdi, [rax + rbp * 8]
    inc ebp
    test rdi, rdi
    jz .fc_next
    cmp [rdi + ubt_rfc_dlc.session], rbx
    jne .fc_next
    mov eax, [rsp + 32]
    mov [rdi + ubt_rfc_dlc.stopped], al
    call rfc_pump
    jmp .fc_next

.pn_cmd:
    ; their offer for a DLCI: a served channel takes it, credit flow agreed
    cmp dword [rsp + 24], 8
    jb .out
    mov rsi, [rsp + 16]
    movzx r14d, byte [rsi]
    and r14d, 0x3F
    mov rdi, rbx
    mov esi, r14d
    call rfc_dlc_find
    test rax, rax
    jnz .pn_have
    mov edi, r14d
    shr edi, 1
    call rfc_server_find
    test rax, rax
    jz .pn_refuse
    mov rdi, rbx
    mov esi, r14d
    mov rdx, [rax + rfc_srv.ops]
    mov rcx, [rax + rfc_srv.user]
    call rfc_dlc_new
    test rax, rax
    jz .pn_refuse
.pn_have:
    mov rbp, rax
    mov byte [rbp + ubt_rfc_dlc.state], RFC_OPENING
    call .pn_take
    mov rdi, rbp
    xor esi, esi
    call rfc_pn
    jmp .out
.pn_refuse:
    mov edi, r14d
    mov esi, RFC_DM | RFC_PF
    call rfc_ctl
    jmp .out
; .pn_take — RBP = dlc, [rsp + 8 + 16] = the values (one call deep): their
; frame size (the smaller is used), credit flow, their credits
.pn_take:
    mov rsi, [rsp + 8 + 16]
    movzx eax, word [rsi + 4]
    mov ecx, RFC_MTU
    cmp eax, ecx
    jbe .pt_mtu
    mov eax, ecx
.pt_mtu:
    cmp eax, 23
    jae .pt_set
    mov eax, 23
.pt_set:
    ; one more frame header must fit L2CAP's MTU
    mov ecx, [rbx + ubt_rfc_session.mtu]
    sub ecx, 6
    cmp eax, ecx
    jbe .pt_fits
    mov eax, ecx
.pt_fits:
    mov [rbp + ubt_rfc_dlc.mtu], eax
    movzx eax, byte [rsi + 1]
    and eax, 0xF0
    xor ecx, ecx
    cmp eax, 0xF0
    je .pt_cfc
    cmp eax, 0xE0
    jne .pt_done
.pt_cfc:
    mov byte [rbp + ubt_rfc_dlc.cfc], 1
    movzx ecx, byte [rsi + 7]
    and ecx, 7
.pt_done:
    mov [rbp + ubt_rfc_dlc.tx_credits], ecx
    ret

.msc_cmd:
    ; their Modem Status: answered; the channel is open once both are
    cmp dword [rsp + 24], 2
    jb .out
    mov rsi, [rsp + 16]
    movzx r14d, byte [rsi]
    shr r14d, 2
    mov edi, MUX_MSC
    xor esi, esi
    mov rdx, [rsp + 16]
    mov ecx, [rsp + 24]
    call rfc_mux
    mov rdi, rbx
    mov esi, r14d
    call rfc_dlc_find
    test rax, rax
    jz .out
    mov byte [rax + ubt_rfc_dlc.got_msc], 1
    jmp .maybe_open

.mux_response:
    cmp eax, MUX_PN
    je .pn_rsp
    cmp eax, MUX_MSC
    je .msc_rsp
    jmp .out
.pn_rsp:
    cmp dword [rsp + 24], 8
    jb .out
    mov rsi, [rsp + 16]
    movzx r14d, byte [rsi]
    and r14d, 0x3F
    mov rdi, rbx
    mov esi, r14d
    call rfc_dlc_find
    test rax, rax
    jz .out
    mov rbp, rax
    call .pn_take
    ; then SABM for it
    mov edi, r14d
    mov esi, RFC_SABM | RFC_PF
    call rfc_ctl
    jmp .out
.msc_rsp:
    jmp .out
.maybe_open:
    cmp byte [rax + ubt_rfc_dlc.sent_msc], 0
    je .out
    cmp byte [rax + ubt_rfc_dlc.state], RFC_OPENING
    jne .out
    mov byte [rax + ubt_rfc_dlc.state], RFC_OPEN
    mov rbp, rax
    mov rdi, rax
    mov esi, RFC_EV_OPEN
    xor edx, edx
    call rfc_event
    mov rdi, rbp
    call rfc_pump
    jmp .out

%endif ; LIB_UBT_RFCOMM_RFCOMM_ASM
