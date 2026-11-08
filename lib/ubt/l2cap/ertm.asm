; =============================================================================
; Utkarsha OS — lib/ubt/l2cap/ertm.asm — Enhanced Retransmission and
; Streaming modes
; =============================================================================
;   l2cap_ertm_open(chan)           the mode's state, from what configuration
;                                   agreed (the peer's window, retransmit
;                                   count, payload size; the timeouts)
;   l2cap_ertm_free(chan)
;   l2cap_ertm_send(chan, sdu, len) cut to the peer's payload size, queued,
;                                   sent while its window allows
;   l2cap_ertm_recv(chan, payload, len)  one I- or S-frame
;   l2cap_ertm_tick(chan, now)      retransmission and monitor timers
;
; Frames: the 2-byte standard control field and a CRC-16 FCS on every
; frame. ERTM: every I-frame kept until acknowledged; acknowledgements on
; outgoing I-frames or Receiver Ready; the retransmission timer polls (RR
; with P), the monitor timer repeats the poll MaxTransmit times and then
; closes the channel; Reject retransmits from its ReqSeq, Selective Reject
; one frame, Receiver Not Ready pauses; a frame retransmitted MaxTransmit
; times closes the channel. Received I-frames are taken in order, a gap
; answered once with Reject, duplicates dropped. Streaming: no
; acknowledgements, no retransmission; a gap drops the SDU being built.
; =============================================================================

%ifndef LIB_UBT_L2CAP_ERTM_ASM
%define LIB_UBT_L2CAP_ERTM_ASM


%define EF_REMOTE_BUSY      (1 << 0)
%define EF_WAIT_F           (1 << 1)    ; polled, waiting for the F bit
%define EF_REJ_SENT         (1 << 2)
%define EF_STREAM           (1 << 3)    ; streaming mode

; S-frame kinds
%define S_RR                0
%define S_REJ               1
%define S_RNR               2
%define S_SREJ              3

; SAR
%define SAR_UNSEG           0
%define SAR_START           1
%define SAR_END             2
%define SAR_CONT            3

struc l2cap_seg
    .next:          resq 1
    .size:          resd 1          ; the block's size
    .len:           resd 1          ; payload bytes (the SDU length included
                                    ; in a start frame)
    .sar:           resb 1
    .seq:           resb 1
    .retries:       resb 1
    .pad:           resb 5
    .data:
endstruc

struc l2cap_ertm
    .txwin:         resd 1          ; the peer's window: unacknowledged at most
    .maxtx:         resd 1          ; the peer's MaxTransmit (0: no limit)
    .mps:           resd 1          ; the peer's payload size
    .retrans_ms:    resd 1
    .monitor_ms:    resd 1
    .next_tx:       resd 1          ; TxSeq of the next I-frame
    .exp_ack:       resd 1          ; the oldest unacknowledged
    .exp_tx:        resd 1          ; the next TxSeq we expect
    .unacked:       resd 1
    .retry:         resd 1          ; polls sent while waiting for F
    .flags:         resd 1
    .pad:           resd 1
    .retrans_at:    resq 1
    .monitor_at:    resq 1
    .txq:           resq 1          ; segments waiting for the window
    .txq_tail:      resq 1
    .sent:          resq 64         ; by TxSeq, until acknowledged
    .sdu:           resq 1          ; the SDU being put together (imtu bytes)
    .sdu_len:       resd 1
    .sdu_got:       resd 1
    .sdu_on:        resd 1          ; a start was taken
    .pad2:          resd 1
endstruc

section .text

; -----------------------------------------------------------------------------
; l2cap_crc16 — L2CAP's FCS: x^16 + x^15 + x^2 + 1, least significant bit
;               first, from 0. RSI = bytes, ECX = count, EAX = so far → EAX
; -----------------------------------------------------------------------------
global l2cap_crc16
l2cap_crc16:
    test ecx, ecx
    jz .out
.byte:
    movzx edx, byte [rsi]
    xor eax, edx
    mov edx, 8
.bit:
    shr eax, 1
    jnc .no
    xor eax, 0xA001
.no:
    dec edx
    jnz .bit
    inc rsi
    dec ecx
    jnz .byte
.out:
    and eax, 0xFFFF
    ret

; -----------------------------------------------------------------------------
; l2cap_ertm_open — RDI = chan → EAX = 0, or -UBT_ENOMEM
; -----------------------------------------------------------------------------
global l2cap_ertm_open
l2cap_ertm_open:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov edi, l2cap_ertm_size
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .nomem
    mov r12, rax
    mov [rbx + l2cap_chan.ertm], r12
    movzx edi, word [rbx + l2cap_chan.imtu]
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .nomem_free
    mov [r12 + l2cap_ertm.sdu], rax
    movzx eax, byte [rbx + l2cap_chan.peer_txwin]
    test eax, eax
    jnz .win
    mov eax, 1
.win:
    cmp eax, 63
    jbe .win_ok
    mov eax, 63
.win_ok:
    mov [r12 + l2cap_ertm.txwin], eax
    movzx eax, byte [rbx + l2cap_chan.peer_maxtx]
    mov [r12 + l2cap_ertm.maxtx], eax
    movzx eax, word [rbx + l2cap_chan.peer_mps]
    cmp eax, 8
    jae .mps
    mov eax, L2CAP_MIN_MTU              ; none said: the smallest there is
.mps:
    cmp eax, ERTM_MPS
    jbe .mps_ok
    mov eax, ERTM_MPS                   ; and never more than one ACL frame
.mps_ok:
    mov [r12 + l2cap_ertm.mps], eax
    movzx eax, word [rbx + l2cap_chan.retrans_ms]
    test eax, eax
    jnz .retrans
    mov eax, ERTM_RETRANS_MS
.retrans:
    mov [r12 + l2cap_ertm.retrans_ms], eax
    movzx eax, word [rbx + l2cap_chan.monitor_ms]
    test eax, eax
    jnz .monitor
    mov eax, ERTM_MONITOR_MS
.monitor:
    mov [r12 + l2cap_ertm.monitor_ms], eax
    cmp byte [rbx + l2cap_chan.mode], L2CAP_MODE_STREAMING
    jne .ok
    mov dword [r12 + l2cap_ertm.flags], EF_STREAM
.ok:
    xor eax, eax
    jmp .out
.nomem_free:
    mov rdi, r12
    mov esi, l2cap_ertm_size
    mov edx, 8
    call usb_free
    mov qword [rbx + l2cap_chan.ertm], 0
.nomem:
    mov eax, -UBT_ENOMEM
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; l2cap_seg_free — RDI = segment (0: nothing)
l2cap_seg_free:
    test rdi, rdi
    jz .out
    mov esi, [rdi + l2cap_seg.size]
    mov edx, 8
    jmp usb_free
.out:
    ret

; -----------------------------------------------------------------------------
; l2cap_ertm_free — RDI = chan: everything queued, sent and half-built given
;                   back
; -----------------------------------------------------------------------------
global l2cap_ertm_free
l2cap_ertm_free:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, [rbx + l2cap_chan.ertm]
    test r12, r12
    jz .out
    mov r13, [r12 + l2cap_ertm.txq]
.queued:
    test r13, r13
    jz .sent
    mov rdi, r13
    mov r13, [r13 + l2cap_seg.next]
    call l2cap_seg_free
    jmp .queued
.sent:
    xor r13d, r13d
.slot:
    mov rdi, [r12 + l2cap_ertm.sent + r13 * 8]
    call l2cap_seg_free
    inc r13d
    cmp r13d, 64
    jb .slot
    mov rdi, [r12 + l2cap_ertm.sdu]
    movzx esi, word [rbx + l2cap_chan.imtu]
    mov edx, 8
    call usb_free
    mov rdi, r12
    mov esi, l2cap_ertm_size
    mov edx, 8
    call usb_free
    mov qword [rbx + l2cap_chan.ertm], 0
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_ertm_frame — RBX = chan, R12 = state: one frame out
; Input:  EDI = control field, RSI = payload (0), EDX = its length
; -----------------------------------------------------------------------------
l2cap_ertm_frame:
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8
    mov r13d, edi
    mov r14, rsi
    mov r15d, edx
    lea edi, [r15d + 8]                 ; header, control, payload, FCS
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .out
    mov rbp, rax
    lea eax, [r15d + 4]
    mov [rbp], ax                       ; control, payload, FCS
    mov ax, [rbx + l2cap_chan.dcid]
    mov [rbp + 2], ax
    mov [rbp + 4], r13w
    lea rdi, [rbp + 6]
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    mov rsi, rbp
    lea ecx, [r15d + 6]
    xor eax, eax
    call l2cap_crc16
    mov [rbp + r15 + 6], ax
    mov rdi, [rbx + l2cap_chan.conn]
    mov rsi, rbp
    lea edx, [r15d + 8]
    call ubt_conn_send
    mov rdi, rbp
    lea esi, [r15d + 8]
    mov edx, 8
    call usb_free
.out:
    add rsp, 8
    pop rbp
    pop r15
    pop r14
    pop r13
    ret

; l2cap_ertm_iframe — RBX = chan, R12 = state, RDI = segment, ESI = F bit
l2cap_ertm_iframe:
    sub rsp, 8
    movzx eax, byte [rdi + l2cap_seg.seq]
    shl eax, 1
    shl esi, 7
    or eax, esi
    test dword [r12 + l2cap_ertm.flags], EF_STREAM
    jnz .no_ack                         ; streaming: ReqSeq is 0
    mov ecx, [r12 + l2cap_ertm.exp_tx]
    shl ecx, 8
    or eax, ecx
.no_ack:
    movzx ecx, byte [rdi + l2cap_seg.sar]
    shl ecx, 14
    or eax, ecx
    mov edx, [rdi + l2cap_seg.len]
    lea rsi, [rdi + l2cap_seg.data]
    mov edi, eax
    call l2cap_ertm_frame
    add rsp, 8
    ret

; l2cap_ertm_sframe — RBX = chan, R12 = state, EDI = kind, ESI = P, EDX = F
global l2cap_ertm_sframe
l2cap_ertm_sframe:
    sub rsp, 8
    shl edi, 2
    or edi, 1
    shl esi, 4
    or edi, esi
    shl edx, 7
    or edi, edx
    mov eax, [r12 + l2cap_ertm.exp_tx]
    shl eax, 8
    or edi, eax
    xor esi, esi
    xor edx, edx
    call l2cap_ertm_frame
    add rsp, 8
    ret

; l2cap_ertm_retrans_timer — RBX = chan, R12 = state: running from now
; while frames are unacknowledged, else stopped
l2cap_ertm_retrans_timer:
    mov qword [r12 + l2cap_ertm.retrans_at], 0
    cmp dword [r12 + l2cap_ertm.unacked], 0
    je .out
    sub rsp, 8
    call ubt_now
    add rsp, 8
    test rax, rax
    jz .out
    mov ecx, [r12 + l2cap_ertm.retrans_ms]
    add rax, rcx
    mov [r12 + l2cap_ertm.retrans_at], rax
.out:
    ret

; -----------------------------------------------------------------------------
; l2cap_ertm_push — RBX = chan, R12 = state: queued segments out while the
;                   window allows. EAX = I-frames sent
; -----------------------------------------------------------------------------
l2cap_ertm_push:
    push r13
    push r14
    sub rsp, 8
    xor r14d, r14d
.next:
    mov r13, [r12 + l2cap_ertm.txq]
    test r13, r13
    jz .out
    test dword [r12 + l2cap_ertm.flags], EF_STREAM
    jnz .go
    test dword [r12 + l2cap_ertm.flags], EF_REMOTE_BUSY | EF_WAIT_F
    jnz .out
    mov eax, [r12 + l2cap_ertm.unacked]
    cmp eax, [r12 + l2cap_ertm.txwin]
    jae .out
.go:
    mov rax, [r13 + l2cap_seg.next]
    mov [r12 + l2cap_ertm.txq], rax
    test rax, rax
    jnz .linked
    mov qword [r12 + l2cap_ertm.txq_tail], 0
.linked:
    mov eax, [r12 + l2cap_ertm.next_tx]
    mov [r13 + l2cap_seg.seq], al
    inc eax
    and eax, 63
    mov [r12 + l2cap_ertm.next_tx], eax
    mov rdi, r13
    xor esi, esi
    call l2cap_ertm_iframe
    inc r14d
    test dword [r12 + l2cap_ertm.flags], EF_STREAM
    jz .keep
    mov rdi, r13                        ; streaming keeps nothing
    call l2cap_seg_free
    jmp .next
.keep:
    movzx eax, byte [r13 + l2cap_seg.seq]
    mov [r12 + l2cap_ertm.sent + rax * 8], r13
    inc dword [r12 + l2cap_ertm.unacked]
    cmp qword [r12 + l2cap_ertm.retrans_at], 0
    jne .next
    call l2cap_ertm_retrans_timer
    jmp .next
.out:
    mov eax, r14d
    add rsp, 8
    pop r14
    pop r13
    ret

; -----------------------------------------------------------------------------
; l2cap_ertm_send — RDI = chan, RSI = SDU, EDX = length → EAX = 0 or negative
; -----------------------------------------------------------------------------
global l2cap_ertm_send
l2cap_ertm_send:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24                         ; [rsp] first, [+8] last, [+16] SAR
    mov rbx, rdi
    mov r12, [rbx + l2cap_chan.ertm]
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
    mov ebp, [r12 + l2cap_ertm.mps]     ; payload room
    mov ecx, r14d
    sub ecx, r15d
    ; SAR, and how much of the SDU this one carries
    test r15d, r15d
    jnz .later
    cmp ecx, ebp
    ja .start
    mov dword [rsp + 16], SAR_UNSEG
    jmp .make
.start:
    mov dword [rsp + 16], SAR_START
    lea ecx, [rbp - 2]                  ; room after the SDU length
    jmp .make
.later:
    mov dword [rsp + 16], SAR_END
    cmp ecx, ebp
    jbe .make
    mov dword [rsp + 16], SAR_CONT
    mov ecx, ebp
.make:
    push rcx
    sub rsp, 8
    lea edi, [rcx + l2cap_seg_size + 2]
    mov esi, 8
    call usb_alloc
    add rsp, 8
    pop rcx
    test rax, rax
    jz .nomem
    lea edx, [rcx + l2cap_seg_size + 2]
    mov [rax + l2cap_seg.size], edx
    mov qword [rax + l2cap_seg.next], 0
    mov edx, [rsp + 16]
    mov [rax + l2cap_seg.sar], dl
    mov byte [rax + l2cap_seg.retries], 0
    lea rdi, [rax + l2cap_seg.data]
    mov [rax + l2cap_seg.len], ecx
    cmp edx, SAR_START
    jne .copy
    mov [rdi], r14w                     ; the SDU's whole length first
    add rdi, 2
    add dword [rax + l2cap_seg.len], 2
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
    ; queued whole, then out as the window lets it
    mov rax, [rsp]
    mov rcx, [r12 + l2cap_ertm.txq_tail]
    test rcx, rcx
    jz .empty
    mov [rcx + l2cap_seg.next], rax
    jmp .tail
.empty:
    mov [r12 + l2cap_ertm.txq], rax
.tail:
    mov rax, [rsp + 8]
    mov [r12 + l2cap_ertm.txq_tail], rax
    call l2cap_ertm_push
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

; -----------------------------------------------------------------------------
; l2cap_ertm_ack — RBX = chan, R12 = state, EDI = ReqSeq: frames before it
;                  acknowledged. CF = 1 when it acknowledges what was never
;                  sent (the peer is out of step)
; -----------------------------------------------------------------------------
l2cap_ertm_ack:
    push r13
    push r14
    sub rsp, 8
    mov r13d, edi
    mov eax, r13d
    sub eax, [r12 + l2cap_ertm.exp_ack]
    and eax, 63
    cmp eax, [r12 + l2cap_ertm.unacked]
    ja .bad
    mov r14d, eax
    test r14d, r14d
    jz .done
.free:
    mov eax, [r12 + l2cap_ertm.exp_ack]
    mov rdi, [r12 + l2cap_ertm.sent + rax * 8]
    mov qword [r12 + l2cap_ertm.sent + rax * 8], 0
    inc eax
    and eax, 63
    mov [r12 + l2cap_ertm.exp_ack], eax
    call l2cap_seg_free
    dec dword [r12 + l2cap_ertm.unacked]
    dec r14d
    jnz .free
    call l2cap_ertm_retrans_timer
.done:
    clc
    jmp .out
.bad:
    stc
.out:
    lea rsp, [rsp + 8]                  ; keeps CF
    pop r14
    pop r13
    ret

; -----------------------------------------------------------------------------
; l2cap_ertm_resend — RBX = chan, R12 = state, EDI = first TxSeq, ESI = 1
;                     for that frame only: unacknowledged frames again.
;                     CF = 1 when one has been sent MaxTransmit times
; -----------------------------------------------------------------------------
l2cap_ertm_resend:
    push r13
    push r14
    sub rsp, 8
    mov r13d, edi
    mov r14d, esi
.next:
    cmp r13d, [r12 + l2cap_ertm.next_tx]
    je .done
    mov rdi, [r12 + l2cap_ertm.sent + r13 * 8]
    test rdi, rdi
    jz .skip
    mov eax, [r12 + l2cap_ertm.maxtx]
    test eax, eax
    jz .again                           ; no limit
    movzx ecx, byte [rdi + l2cap_seg.retries]
    cmp ecx, eax
    jae .too_many
.again:
    inc byte [rdi + l2cap_seg.retries]
    xor esi, esi
    call l2cap_ertm_iframe
.skip:
    test r14d, r14d
    jnz .done
    inc r13d
    and r13d, 63
    jmp .next
.done:
    call l2cap_ertm_retrans_timer
    clc
    jmp .out
.too_many:
    stc
.out:
    lea rsp, [rsp + 8]                  ; keeps CF
    pop r14
    pop r13
    ret

; -----------------------------------------------------------------------------
; l2cap_ertm_sar — RBX = chan, R12 = state, RSI = I-frame payload, EDX =
;                  its length, ECX = SAR: an SDU whole, to the user
; -----------------------------------------------------------------------------
l2cap_ertm_sar:
    push r13
    push r14
    sub rsp, 8
    movzx r13d, word [rbx + l2cap_chan.imtu]
    cmp ecx, SAR_UNSEG
    je .unseg
    cmp ecx, SAR_START
    je .start
    ; continuation or end: after a start, inside its length
    cmp dword [r12 + l2cap_ertm.sdu_on], 0
    je .bad
    mov eax, [r12 + l2cap_ertm.sdu_got]
    lea r8d, [rax + rdx]
    cmp r8d, [r12 + l2cap_ertm.sdu_len]
    ja .bad
    mov rdi, [r12 + l2cap_ertm.sdu]
    add rdi, rax
    mov [r12 + l2cap_ertm.sdu_got], r8d
    mov r14d, ecx
    mov ecx, edx
    rep movsb
    cmp r14d, SAR_END
    jne .out
    mov eax, [r12 + l2cap_ertm.sdu_got]
    cmp eax, [r12 + l2cap_ertm.sdu_len]
    jne .bad
    mov dword [r12 + l2cap_ertm.sdu_on], 0
    mov rsi, [r12 + l2cap_ertm.sdu]
    mov edx, eax
    jmp .deliver
.start:
    cmp edx, 2
    jb .bad
    movzx eax, word [rsi]
    cmp eax, r13d
    ja .bad
    lea r8d, [rdx - 2]
    cmp r8d, eax
    jae .bad                            ; a start holds less than the SDU
    mov [r12 + l2cap_ertm.sdu_len], eax
    mov [r12 + l2cap_ertm.sdu_got], r8d
    mov dword [r12 + l2cap_ertm.sdu_on], 1
    mov rdi, [r12 + l2cap_ertm.sdu]
    add rsi, 2
    mov ecx, r8d
    rep movsb
    jmp .out
.unseg:
    mov dword [r12 + l2cap_ertm.sdu_on], 0
    cmp edx, r13d
    ja .bad
.deliver:
    mov rax, [rbx + l2cap_chan.ops]
    test rax, rax
    jz .out
    mov rax, [rax + l2cap_ops.recv]
    test rax, rax
    jz .out
    mov rdi, rbx
    call rax
    jmp .out
.bad:
    mov dword [r12 + l2cap_ertm.sdu_on], 0
    inc dword [rel l2cap_dropped]
.out:
    add rsp, 8
    pop r14
    pop r13
    ret

; -----------------------------------------------------------------------------
; l2cap_ertm_recv — RDI = chan, RSI = the frame's payload (control first;
;                   the basic header is the 4 bytes before it), EDX = length
; -----------------------------------------------------------------------------
global l2cap_ertm_recv
l2cap_ertm_recv:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8
    mov rbx, rdi
    mov r12, [rbx + l2cap_chan.ertm]
    test r12, r12
    jz .drop
    mov r13, rsi
    mov r14d, edx
    cmp r14d, 4
    jb .drop
    ; the FCS, over the basic header, control and payload
    lea rsi, [r13 - 4]
    lea ecx, [r14d + 2]                 ; 4 header bytes, less the 2 of the FCS
    xor eax, eax
    call l2cap_crc16
    cmp ax, [r13 + r14 - 2]
    jne .drop
    movzx r15d, word [r13]              ; control
    lea rbp, [r13 + 2]                  ; payload
    sub r14d, 4                         ; its length
    test dword [r12 + l2cap_ertm.flags], EF_STREAM
    jnz .stream
    ; acknowledged frames: every frame's ReqSeq, except a Selective Reject
    ; without P, whose ReqSeq only names the frame wanted again
    mov eax, r15d
    and eax, 0x1D                       ; S-frame bit, kind, P
    cmp eax, 1 | (S_SREJ << 2)
    je .acked
    mov edi, r15d
    shr edi, 8
    and edi, 63
    call l2cap_ertm_ack
    jc .broken
.acked:
    ; the answer to our poll
    test r15d, 1 << 7
    jz .kind
    test dword [r12 + l2cap_ertm.flags], EF_WAIT_F
    jz .kind
    and dword [r12 + l2cap_ertm.flags], ~EF_WAIT_F
    mov qword [r12 + l2cap_ertm.monitor_at], 0
    mov dword [r12 + l2cap_ertm.retry], 0
    mov edi, [r12 + l2cap_ertm.exp_ack]
    xor esi, esi
    call l2cap_ertm_resend              ; what is still unacknowledged
    jc .broken
.kind:
    test r15d, 1
    jnz .sframe

    ; ---- an I-frame ----
    mov eax, r15d
    shr eax, 1
    and eax, 63                         ; TxSeq
    mov ecx, eax
    sub ecx, [r12 + l2cap_ertm.exp_tx]
    and ecx, 63
    test ecx, ecx
    jz .in_order
    cmp ecx, 64 - ERTM_TXWIN
    jae .ack_only                       ; a duplicate: already had it
    cmp ecx, ERTM_TXWIN
    jae .broken                         ; outside any window
    ; a gap: Reject once
    test dword [r12 + l2cap_ertm.flags], EF_REJ_SENT
    jnz .push
    or dword [r12 + l2cap_ertm.flags], EF_REJ_SENT
    mov edi, S_REJ
    xor esi, esi
    xor edx, edx
    call l2cap_ertm_sframe
    jmp .push
.in_order:
    and dword [r12 + l2cap_ertm.flags], ~EF_REJ_SENT
    inc eax
    and eax, 63
    mov [r12 + l2cap_ertm.exp_tx], eax
    mov rsi, rbp
    mov edx, r14d
    mov ecx, r15d
    shr ecx, 14
    call l2cap_ertm_sar
.ack_only:
    ; acknowledged on an I-frame going out, or by Receiver Ready
    call l2cap_ertm_push
    test eax, eax
    jnz .out
    mov edi, S_RR
    xor esi, esi
    xor edx, edx
    call l2cap_ertm_sframe
    jmp .out

    ; ---- an S-frame ----
.sframe:
    mov eax, r15d
    shr eax, 2
    and eax, 3
    cmp eax, S_REJ
    je .rej
    cmp eax, S_SREJ
    je .srej
    cmp eax, S_RNR
    je .rnr
    and dword [r12 + l2cap_ertm.flags], ~EF_REMOTE_BUSY
    jmp .poll
.rnr:
    or dword [r12 + l2cap_ertm.flags], EF_REMOTE_BUSY
    jmp .poll
.rej:
    and dword [r12 + l2cap_ertm.flags], ~EF_REMOTE_BUSY
    mov edi, r15d
    shr edi, 8
    and edi, 63
    xor esi, esi
    call l2cap_ertm_resend
    jc .broken
    jmp .poll
.srej:
    mov edi, r15d
    shr edi, 8
    and edi, 63
    mov esi, 1
    call l2cap_ertm_resend
    jc .broken
.poll:
    ; polled: Receiver Ready with F
    test r15d, 1 << 4
    jz .push
    mov edi, S_RR
    xor esi, esi
    mov edx, 1
    call l2cap_ertm_sframe
.push:
    call l2cap_ertm_push
    jmp .out

    ; ---- streaming: in order or the SDU is lost ----
.stream:
    test r15d, 1
    jnz .out                            ; no S-frames in streaming mode
    mov eax, r15d
    shr eax, 1
    and eax, 63
    cmp eax, [r12 + l2cap_ertm.exp_tx]
    je .stream_ok
    mov dword [r12 + l2cap_ertm.sdu_on], 0      ; something was lost
.stream_ok:
    inc eax
    and eax, 63
    mov [r12 + l2cap_ertm.exp_tx], eax
    mov rsi, rbp
    mov edx, r14d
    mov ecx, r15d
    shr ecx, 14
    call l2cap_ertm_sar
    jmp .out

.broken:
    ; the peer is out of step, or will not take a frame: the channel goes
    mov rdi, rbx
    call l2cap_disconnect
    jmp .out
.drop:
    inc dword [rel l2cap_dropped]
.out:
    add rsp, 8
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; l2cap_ertm_tick — RDI = chan, RSI = now (ms)
; -----------------------------------------------------------------------------
global l2cap_ertm_tick
l2cap_ertm_tick:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r13, rsi
    mov r12, [rbx + l2cap_chan.ertm]
    test r12, r12
    jz .out
    test dword [r12 + l2cap_ertm.flags], EF_STREAM
    jnz .out
    ; nothing acknowledged in time: poll
    mov rax, [r12 + l2cap_ertm.retrans_at]
    test rax, rax
    jz .monitor
    cmp r13, rax
    jb .monitor
    mov qword [r12 + l2cap_ertm.retrans_at], 0
    test dword [r12 + l2cap_ertm.flags], EF_WAIT_F
    jnz .monitor
    or dword [r12 + l2cap_ertm.flags], EF_WAIT_F
    mov dword [r12 + l2cap_ertm.retry], 1
    jmp .poll
.monitor:
    mov rax, [r12 + l2cap_ertm.monitor_at]
    test rax, rax
    jz .out
    cmp r13, rax
    jb .out
    mov eax, [r12 + l2cap_ertm.maxtx]
    test eax, eax
    jz .again
    cmp [r12 + l2cap_ertm.retry], eax
    jae .give_up
.again:
    inc dword [r12 + l2cap_ertm.retry]
.poll:
    mov edi, S_RR
    mov esi, 1
    xor edx, edx
    call l2cap_ertm_sframe
    mov eax, [r12 + l2cap_ertm.monitor_ms]
    add rax, r13
    mov [r12 + l2cap_ertm.monitor_at], rax
    jmp .out
.give_up:
    mov qword [r12 + l2cap_ertm.monitor_at], 0
    mov rdi, rbx
    call l2cap_disconnect
.out:
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_UBT_L2CAP_ERTM_ASM
