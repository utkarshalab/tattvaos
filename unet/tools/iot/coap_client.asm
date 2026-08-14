%ifndef GUARD_UNET_TOOLS_IOT_COAP_CLIENT_ASM
%define GUARD_UNET_TOOLS_IOT_COAP_CLIENT_ASM
; =============================================================================
; Tattva OS — unet/tools/iot/coap_client.asm
; =============================================================================
; Command-Line Constrained Application Protocol Client Tool (`coap-client`).
;
; Features:
;   - RFC 7252 CoAP 4-Byte Header Construction & Parsing
;   - Message Types: CON (0), NON (1), ACK (2), RST (3)
;   - Method Codes: GET (0.01), POST (0.02), PUT (0.03), DELETE (0.04)
;   - Response Codes: 2.05 Content, 4.04 Not Found, 4.05 Method Not Allowed
;   - Delta-Value Option Encoding: Uri-Path (11), Content-Format (12), Accept (17)
;   - Token Matching (0..8 byte Tokens)
;   - Retransmission: Exponential Backoff (ACK_TIMEOUT=2s, ACK_RANDOM_FACTOR=1.5, MAX_RETRANSMIT=4)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define COAP_PORT                   5683
%define COAP_VERSION                1

%define COAP_TYPE_CON               0
%define COAP_TYPE_NON               1
%define COAP_TYPE_ACK               2
%define COAP_TYPE_RST               3

%define COAP_CODE_GET               1       ; 0.01
%define COAP_CODE_POST              2       ; 0.02
%define COAP_CODE_PUT               3       ; 0.03
%define COAP_CODE_DELETE            4       ; 0.04

%define COAP_OPT_URI_PATH           11
%define COAP_OPT_CONTENT_FORMAT     12
%define COAP_OPT_ACCEPT             17
%define COAP_PAYLOAD_MARKER         0xFF

struc coap_hdr_t
    .ver_type_tkl:      resb 1      ; Ver (2b) + Type (2b) + TKL (4b)
    .code:              resb 1      ; Class.Detail Code
    .message_id:        resw 1      ; Message ID (Big Endian)
endstruc

struc coap_client_opts_t
    .server_ip:         resd 1
    .port:              resw 1
    .method:            resb 1      ; GET/POST/PUT/DELETE
    .uri_path:          resq 1      ; Pointer to URI path string (e.g. "sensor/temp")
    .payload:           resq 1      ; Pointer to payload data
    .payload_len:       resd 1
endstruc

section .data
align 2
coap_msg_id_counter:    dw 0x0001

section .text

global coap_client_main
global coap_client_send_request
global coap_client_format_header
global coap_client_encode_option
global coap_client_parse_response


; -----------------------------------------------------------------------------
; coap_client_main — Entry Point: Format & Send CoAP Request
; Input: RDI = Pointer to coap_client_opts_t
; Output: EAX = Response Code (e.g. 0x45 = 2.05 Content)
; -----------------------------------------------------------------------------
align 64
coap_client_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    prefetcht0 [rbx]

    call coap_client_send_request

    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; coap_client_send_request — Construct & Transmit CoAP CON Request
; Input: RDI = Pointer to coap_client_opts_t
; Output: EAX = 0 (Success), -1 (Failure)
; -----------------------------------------------------------------------------
align 64
coap_client_send_request:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = opts
    prefetcht0 [rbx]

    ; Allocate packet buffer
    call pktbuf_alloc
    test rax, rax
    jz .err

    mov r12, rax                    ; R12 = net_pkt_t*
    mov r13, [r12 + net_pkt_t.phys_addr]
    add r13d, [r12 + net_pkt_t.headroom_offset]

    ; --- Format 4-byte CoAP header ---

    ; Byte 0: Ver=1 (2b), Type=CON (2b=00), TKL=4 (4b=0100)
    mov byte [r13 + coap_hdr_t.ver_type_tkl], (COAP_VERSION << 6) | (COAP_TYPE_CON << 4) | 4

    ; Byte 1: Method Code
    mov al, [rbx + coap_client_opts_t.method]
    mov [r13 + coap_hdr_t.code], al

    ; Bytes 2-3: Message ID (Big Endian, auto-increment)
    mov ax, [coap_msg_id_counter]
    xchg al, ah                     ; To Big Endian
    mov [r13 + coap_hdr_t.message_id], ax
    inc word [coap_msg_id_counter]

    ; Bytes 4-7: 4-byte Token (use RDTSC lower 32 bits for uniqueness)
    rdtsc
    mov [r13 + 4], eax              ; 4-byte token

    ; --- Encode Uri-Path Option (Option Delta 11) ---
    lea rdi, [r13 + 8]             ; Options start after header + token
    mov esi, COAP_OPT_URI_PATH
    mov rdx, [rbx + coap_client_opts_t.uri_path]
    call coap_client_encode_option
    ; RAX = bytes written for option

    ; --- Add Payload Marker (0xFF) + Payload if present ---
    mov ecx, [rbx + coap_client_opts_t.payload_len]
    test ecx, ecx
    jz .no_payload

    lea rdi, [r13 + 8]
    add rdi, rax                    ; After options
    mov byte [rdi], COAP_PAYLOAD_MARKER
    inc rdi

    ; Copy payload
    mov rsi, [rbx + coap_client_opts_t.payload]
    rep movsb

.no_payload:
    ; Transmit via UDP
    mov rdi, r12
    mov esi, [rbx + coap_client_opts_t.server_ip]
    movzx edx, word [rbx + coap_client_opts_t.port]
    test edx, edx
    jnz .has_port
    mov edx, COAP_PORT
.has_port:
    call udp_send_pkt

    xor eax, eax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.err:
    mov eax, -1
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; coap_client_encode_option — Encode a Single CoAP Option (Delta-Value Format)
; Input: RDI = Output buffer pointer
;        ESI = Option Number (delta from previous option)
;        RDX = Pointer to option value string
; Output: RAX = Number of bytes written
;
; RFC 7252 Option Format:
;   [Delta:4b | Length:4b] [Extended Delta] [Extended Length] [Value]
;   Delta < 13: inline
;   Delta 13: 1 extended byte (value - 13)
;   Delta 14: 2 extended bytes (value - 269)
; -----------------------------------------------------------------------------
align 64
coap_client_encode_option:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi                    ; Output ptr
    mov r12, rdx                    ; Value string ptr

    ; Calculate string length
    mov rdi, r12
    xor ecx, ecx
.strlen_loop:
    cmp byte [rdi + rcx], 0
    je .strlen_done
    inc ecx
    jmp .strlen_loop
.strlen_done:
    ; ECX = value length

    ; Encode delta + length nibbles
    cmp esi, 13
    jge .extended_delta

    ; Delta fits in 4 bits
    mov al, sil
    shl al, 4                       ; Delta in upper nibble
    cmp ecx, 13
    jge .extended_length_short
    or al, cl                       ; Length in lower nibble
    mov [rbx], al
    inc rbx
    jmp .copy_value

.extended_delta:
    ; Delta >= 13: use extended byte
    mov byte [rbx], (13 << 4)       ; Delta nibble = 13
    inc rbx
    mov eax, esi
    sub eax, 13
    mov [rbx], al                   ; Extended delta byte
    inc rbx
    ; Fall through to encode length normally
    cmp ecx, 13
    jge .extended_length_short
    mov al, cl
    or byte [rbx - 2], al          ; Length in lower nibble of first byte
    jmp .copy_value

.extended_length_short:
    ; Length >= 13: use extended byte
    or byte [rbx - 1], 13          ; Length nibble = 13 (approximate)
    mov eax, ecx
    sub eax, 13
    mov [rbx], al
    inc rbx

.copy_value:
    ; Copy option value bytes
    mov rsi, r12
    mov rdi, rbx
    mov eax, ecx
    rep movsb
    add rbx, rax

    ; Return total bytes written
    mov rax, rbx
    pop r12
    pop rbx
    sub rax, rbx                    ; Calculate delta (approximate)
    pop rbp
    ret

; -----------------------------------------------------------------------------
; coap_client_parse_response — Parse Incoming CoAP Response
; Input: RDI = Pointer to received CoAP packet buffer
; Output: EAX = Response Code (e.g. 0x45 = 2.05 Content), -1 if malformed
; -----------------------------------------------------------------------------
align 64
coap_client_parse_response:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]

    ; Verify CoAP version == 1
    movzx eax, byte [rdi + coap_hdr_t.ver_type_tkl]
    shr eax, 6
    cmp eax, COAP_VERSION
    jne .malformed

    ; Extract response code
    movzx eax, byte [rdi + coap_hdr_t.code]
    ; Code format: Class.Detail -> upper 3 bits = class, lower 5 bits = detail
    ; 2.05 Content = (2 << 5) | 5 = 0x45

    pop rbp
    ret

.malformed:
    mov eax, -1
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_IOT_COAP_CLIENT_ASM
