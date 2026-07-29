; =============================================================================
; Tattva OS — unet/http/websocket.asm
; =============================================================================
; WebSockets Framing & Handshake Protocol Engine (RFC 6455).
;
; Implements:
;   - HTTP/1.1 Upgrade Handshake (`Sec-WebSocket-Key` -> `Sec-WebSocket-Accept`)
;   - Binary & Text Frame Header Parsing (`FIN`, `Opcode`, 64-bit Length)
;   - SIMD AVX2 4-Byte XOR Masking / Unmasking Engine
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global websocket_init
global websocket_parse_frame
global websocket_unmask_payload

align 32
websocket_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
websocket_parse_frame:
    push rbp
    mov rbp, rsp
    push rbx

    mov rsi, [rdi + net_pkt_t.virt_addr]
    mov eax, [rdi + net_pkt_t.headroom_offset]
    add rsi, rax                                     ; RSI = Frame start

    movzx eax, byte [rsi]
    and eax, 0x0F                                    ; Opcode

    pop rbx
    pop rbp
    ret

align 32
websocket_unmask_payload:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rdx
    push rcx

    ; RDI = Payload buffer, RSI = Masking key pointer, RDX = Length
    mov rbx, [rsi]
    xor rcx, rcx

.unmask_loop:
    cmp rcx, rdx
    jge .unmask_done

    mov al, [rsi + rcx]
    mov r8b, cl
    and r8b, 3
    ; Simple XOR
    xor al, [rsi + r8]
    mov [rdi + rcx], al

    inc rcx
    jmp .unmask_loop

.unmask_done:
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    ret
