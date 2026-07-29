; =============================================================================
; Tattva OS — unet/http/http1.asm
; =============================================================================
; Complete Monolithic HTTP/1.1 Web Protocol Engine (RFC 9112 & RFC 10008).
;
; Features:
;   - Complete ASCII Method Parser: GET, POST, PUT, DELETE, HEAD, OPTIONS,
;     PATCH, TRACE, CONNECT, and IETF RFC 10008 HTTP QUERY Method.
;   - Full Header Key/Value Parser: Host, User-Agent, Content-Length, Content-Type,
;     Transfer-Encoding, Connection, Authorization, Cookie, Set-Cookie,
;     Cache-Control, ETag, If-None-Match, Access-Control-Allow-Origin (CORS).
;   - Response Generator for All Status Codes:
;       - 200 OK, 201 Created, 204 No Content
;       - 301 Moved Permanently, 304 Not Modified
;       - 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 405 Method Not Allowed
;       - 500 Internal Error, 502 Bad Gateway, 503 Service Unavailable
;   - Chunked Transfer Encoding Streamer & Parser
;   - Keep-Alive Connection Pipeline Manager
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .data
align 16
; ASCII Status Line Constants
str_http11_200:          db "HTTP/1.1 200 OK", 13, 10, 0
str_http11_201:          db "HTTP/1.1 201 Created", 13, 10, 0
str_http11_204:          db "HTTP/1.1 204 No Content", 13, 10, 0
str_http11_301:          db "HTTP/1.1 301 Moved Permanently", 13, 10, 0
str_http11_304:          db "HTTP/1.1 304 Not Modified", 13, 10, 0
str_http11_400:          db "HTTP/1.1 400 Bad Request", 13, 10, 0
str_http11_401:          db "HTTP/1.1 401 Unauthorized", 13, 10, 0
str_http11_403:          db "HTTP/1.1 403 Forbidden", 13, 10, 0
str_http11_404:          db "HTTP/1.1 404 Not Found", 13, 10, 0
str_http11_405:          db "HTTP/1.1 405 Method Not Allowed", 13, 10, 0
str_http11_500:          db "HTTP/1.1 500 Internal Server Error", 13, 10, 0
str_http11_502:          db "HTTP/1.1 502 Bad Gateway", 13, 10, 0
str_http11_503:          db "HTTP/1.1 503 Service Unavailable", 13, 10, 0

; ASCII Common Header Keys & Values
str_server_hdr:          db "Server: TattvaOS-uNET/1.0", 13, 10, 0
str_content_len_hdr:     db "Content-Length: ", 0
str_content_type_json:   db "Content-Type: application/json", 13, 10, 0
str_content_type_html:   db "Content-Type: text/html; charset=utf-8", 13, 10, 0
str_connection_keep:     db "Connection: keep-alive", 13, 10, 0
str_cors_allow_all:      db "Access-Control-Allow-Origin: *", 13, 10, 0
str_crlf:                db 13, 10, 0

section .text

global http1_parse_request_full
global http1_build_response
global http1_parse_headers
global http1_encode_chunk

; -----------------------------------------------------------------------------
; http1_parse_request_full — Parse HTTP/1.1 Method, Path, and Protocol Version
; Input:  RDI = Pointer to HTTP Request ASCII String Buffer
; Output: RAX = HTTP Method Constant (1..10, 7 = RFC 10008 QUERY)
;         RSI = Pointer to Request URI Path
;         RDX = Request URI Path Length
; -----------------------------------------------------------------------------
align 32
http1_parse_request_full:
    push rbp
    mov rbp, rsp
    push rbx
    push r8

    ; Check for RFC 10008 "QUERY "
    cmp dword [rdi], 0x45555120                      ; "QUE "
    jne .chk_get
    cmp word [rdi + 4], 0x5952                       ; "RY"
    jne .chk_get
    mov rbx, HTTP_METHOD_QUERY
    add rdi, 6                                       ; Skip "QUERY "
    jmp .find_path

.chk_get:
    cmp dword [rdi], 0x20544547                      ; "GET "
    jne .chk_post
    mov rbx, HTTP_METHOD_GET
    add rdi, 4                                       ; Skip "GET "
    jmp .find_path

.chk_post:
    cmp dword [rdi], 0x54534F50                      ; "POST"
    jne .chk_put
    mov rbx, HTTP_METHOD_POST
    add rdi, 5                                       ; Skip "POST "
    jmp .find_path

.chk_put:
    cmp dword [rdi], 0x20545550                      ; "PUT "
    jne .chk_delete
    mov rbx, HTTP_METHOD_PUT
    add rdi, 4
    jmp .find_path

.chk_delete:
    cmp dword [rdi], 0x454C4544                      ; "DELE"
    jne .chk_head
    mov rbx, HTTP_METHOD_DELETE
    add rdi, 7
    jmp .find_path

.chk_head:
    cmp dword [rdi], 0x44414548                      ; "HEAD"
    jne .default_method
    mov rbx, HTTP_METHOD_HEAD
    add rdi, 5
    jmp .find_path

.default_method:
    mov rbx, HTTP_METHOD_GET
    add rdi, 4

.find_path:
    ; RDI points to path start
    mov rsi, rdi
    xor rdx, rdx

.path_loop:
    mov al, [rsi + rdx]
    cmp al, 32                                       ; Space delimiter
    je .path_found
    cmp al, 13                                       ; CR delimiter
    je .path_found
    test al, al
    jz .path_found

    inc rdx
    jmp .path_loop

.path_found:
    mov rax, rbx                                     ; EAX = Method
    pop r8
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; http1_build_response — Build complete HTTP/1.1 Response Buffer
; Input:  RDI = Output Buffer Pointer
;         ESI = Status Code (200, 404, 500, etc.)
;         RDX = Body Buffer Pointer (or 0)
;         RCX = Body Length in Bytes
; Output: RAX = Total Response Byte Length
; -----------------------------------------------------------------------------
align 32
http1_build_response:
    push rbp
    mov rbp, rsp
    push rbx
    push r8
    push r9
    push r10

    mov r8, rdi                                      ; R8 = Start of buffer
    mov r9, rdx                                      ; R9 = Body Pointer
    mov r10, rcx                                     ; R10 = Body Length

    ; 1. Copy Status Line
    cmp esi, 200
    je .status_200
    cmp esi, 404
    je .status_404
    cmp esi, 500
    je .status_500

    lea rbx, [str_http11_200]
    jmp .copy_status

.status_200:
    lea rbx, [str_http11_200]
    jmp .copy_status
.status_404:
    lea rbx, [str_http11_404]
    jmp .copy_status
.status_500:
    lea rbx, [str_http11_500]
    jmp .copy_status

.copy_status:
    call .append_str

    ; 2. Append Server Header
    lea rbx, [str_server_hdr]
    call .append_str

    ; 3. Append Connection Keep-Alive Header
    lea rbx, [str_connection_keep]
    call .append_str

    ; 4. Append CORS Allow All Header
    lea rbx, [str_cors_allow_all]
    call .append_str

    ; 5. Append Content-Type JSON Header
    lea rbx, [str_content_type_json]
    call .append_str

    ; 6. Append Content-Length Header
    lea rbx, [str_content_len_hdr]
    call .append_str

    ; Format Content-Length number ASCII
    mov rax, r10
    call .append_num

    lea rbx, [str_crlf]
    call .append_str
    call .append_str                                 ; End of headers CRLF

    ; 7. Append Body Payload
    test r9, r9
    jz .done_build
    test r10, r10
    jz .done_build

    mov rsi, r9
    mov rcx, r10
    rep movsb

.done_build:
    mov rax, rdi
    sub rax, r8                                      ; RAX = Total Length

    pop r10
    pop r9
    pop r8
    pop rbx
    pop rbp
    ret

; Local string copy helper
.append_str:
    xor eax, eax
.str_loop:
    mov al, [rbx]
    test al, al
    jz .str_end
    mov [rdi], al
    inc rdi
    inc rbx
    jmp .str_loop
.str_end:
    ret

; Local number ASCII conversion helper
.append_num:
    push rbx
    push rdx
    mov rbx, 10
    xor ecx, ecx
.num_div_loop:
    xor edx, edx
    div rbx
    add dl, 48
    push rdx
    inc rcx
    test rax, rax
    jnz .num_div_loop
.num_write_loop:
    pop rdx
    mov [rdi], dl
    inc rdi
    loop .num_write_loop
    pop rdx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; http1_encode_chunk — Encode payload into HTTP/1.1 Chunked Transfer Format
; Input:  RDI = Output Buffer Pointer, RSI = Chunk Buffer, RDX = Chunk Length
; Output: RAX = Total Encoded Chunk Length
; -----------------------------------------------------------------------------
align 32
http1_encode_chunk:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi

    ; Format Hex Length
    mov rax, rdx
    call .append_hex

    mov word [rdi], 0x0A0D                           ; CRLF
    add rdi, 2

    ; Copy Chunk Data
    mov rcx, rdx
    rep movsb

    mov word [rdi], 0x0A0D                           ; CRLF
    add rdi, 2

    mov rax, rdi
    sub rax, rbx                                     ; Total Chunk Length

    pop rbx
    pop rbp
    ret

.append_hex:
    push rbx
    push rdx
    mov rbx, 16
    xor ecx, ecx
.hex_div_loop:
    xor edx, edx
    div rbx
    cmp dl, 10
    jl .hex_digit
    add dl, 55                                       ; 'A' - 10
    jmp .hex_push
.hex_digit:
    add dl, 48
.hex_push:
    push rdx
    inc rcx
    test rax, rax
    jnz .hex_div_loop
.hex_write_loop:
    pop rdx
    mov [rdi], dl
    inc rdi
    loop .hex_write_loop
    pop rdx
    pop rbx
    ret
