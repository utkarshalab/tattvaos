; ============================================================================
; Client Buffer Helpers — cw_buffer requests
; ============================================================================
; The server makes a buffer and answers with its handle and where its pixels
; are; the connection keeps both in its buffer table (ClientBuffer records at
; CLIENT_BUFFER_TABLE), so canvas_buffer_mmap and canvas_buffer_stride need
; no request.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/canvas_client.inc"

extern canvas_call
extern canvas_send

section .text

; ---------------------------------------------------------------------------
; canvas_buffer_create
;   IN:  rdi = conn, esi = width, edx = height, ecx = format (DRM_FORMAT_*)
;   OUT: rax = the buffer's handle, negative error (-ENOSPC: the table is
;        full)
; ---------------------------------------------------------------------------
global canvas_buffer_create
canvas_buffer_create:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 32                         ; create's payload
    mov rbx, rdi
    mov rax, -(ENOSPC)
    cmp qword [rbx + ClientConn.buffer_count], CLIENT_BUFFER_MAX
    jae .out
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov dword [rsp + 12], 0
    mov qword [rsp + 16], 0
    mov esi, CWP_OBJ_BUFFER
    mov edx, BUFFER_CREATE
    mov rcx, rsp
    mov r8d, 24
    call canvas_call
    test rax, rax
    js .out

    ; (buffer, pixels) into the table
    mov rax, [rbx + ClientConn.buffer_count]
    imul eax, eax, ClientBuffer_size
    lea r12, [rbx + CLIENT_BUFFER_TABLE + rax]
    mov eax, [rbx + CLIENT_WIRE + ClientWire.reply]
    mov [r12 + ClientBuffer.id], eax
    mov rax, [rbx + CLIENT_WIRE + ClientWire.reply + 8]
    mov [r12 + ClientBuffer.pixels], rax
    mov eax, [rsp]
    mov [r12 + ClientBuffer.width], eax
    mov ecx, [rsp + 4]
    mov [r12 + ClientBuffer.height], ecx
    mov ecx, [rsp + 8]
    mov [r12 + ClientBuffer.format], ecx
    shl eax, 2                          ; the server's stride: 4 bytes a pixel,
    cmp ecx, DRM_FORMAT_RGB565          ; 2 for RGB565, rows to 4 bytes
    jne .stride
    shr eax, 1
    add eax, 3
    and eax, ~3
.stride:
    mov [r12 + ClientBuffer.stride], eax
    inc qword [rbx + ClientConn.buffer_count]
    mov eax, [r12 + ClientBuffer.id]
.out:
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; canvas_buffer_destroy
;   IN:  rdi = conn, esi = buffer
;   OUT: rax = 0, -ENOENT if it is not this connection's
; ---------------------------------------------------------------------------
global canvas_buffer_destroy
canvas_buffer_destroy:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 16
    mov rbx, rdi
    mov [rsp], esi
    call find_buffer
    test rax, rax
    jz .missing
    mov r12, rax
    mov rdi, rbx
    mov esi, CWP_OBJ_BUFFER
    mov edx, BUFFER_DESTROY
    mov rcx, rsp
    mov r8d, 4
    call canvas_send
    ; the last record takes its place
    dec qword [rbx + ClientConn.buffer_count]
    mov rax, [rbx + ClientConn.buffer_count]
    imul eax, eax, ClientBuffer_size
    lea rsi, [rbx + CLIENT_BUFFER_TABLE + rax]
    mov rdi, r12
    mov ecx, ClientBuffer_size
    rep movsb
    xor eax, eax
    jmp .out
.missing:
    mov rax, -(ENOENT)
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; canvas_buffer_mmap
;   IN:  rdi = conn, esi = buffer
;   OUT: rax = its pixels, 0 if it is not this connection's
; ---------------------------------------------------------------------------
global canvas_buffer_mmap
canvas_buffer_mmap:
    call find_buffer
    test rax, rax
    jz .out
    mov rax, [rax + ClientBuffer.pixels]
.out:
    ret

; ---------------------------------------------------------------------------
; canvas_buffer_stride
;   IN:  rdi = conn, esi = buffer
;   OUT: rax = bytes from one row to the next, 0 if it is not this
;        connection's
; ---------------------------------------------------------------------------
global canvas_buffer_stride
canvas_buffer_stride:
    call find_buffer
    test rax, rax
    jz .out
    mov eax, [rax + ClientBuffer.stride]
.out:
    ret

; rdi = conn, esi = buffer -> rax = its ClientBuffer, 0 if none
find_buffer:
    lea rax, [rdi + CLIENT_BUFFER_TABLE]
    mov rcx, [rdi + ClientConn.buffer_count]
.next:
    test rcx, rcx
    jz .none
    cmp [rax + ClientBuffer.id], esi
    je .done
    add rax, ClientBuffer_size
    dec rcx
    jmp .next
.none:
    xor eax, eax
.done:
    ret

section .data
global canvas_buffer_helpers_version
canvas_buffer_helpers_version: dq 0x020000
