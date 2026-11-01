; ============================================================================
; Buffer Management — Creation, Ownership Transfer, Format Negotiation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/color.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"
%include "inc/handle.inc"

%define BUFFER_HANDLES    4096

%define Buffer_FREE       0
%define Buffer_ALLOCATED  1
%define Buffer_ATTACHED   2
%define Buffer_SCANOUT    3

section .text

; ---------------------------------------------------------------------------
; buffer_init
;   Initialize buffer subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global buffer_init
buffer_init:
    PROLOGUE_SAVE rbx
    sub rsp, 8
    mov rbx, rdi
    ASSERT_PTR rbx
    ASSERT_PTR rsi

    mov qword [rbx + Server.buffer_pool], 0
    mov [rbx + Server.arena], rsi
    mov rdi, rsi
    mov esi, BUFFER_HANDLES
    call handle_table_create
    mov [rbx + Server.buffer_table], rax
    test rax, rax
    mov rax, -(ENOMEM)
    mov ecx, 0
    cmovnz rax, rcx
    add rsp, 8
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; buffer_create
;   Create buffer object: its pixels are a memory region of their own, its
;   header lives with the client
;   IN:  rdi = server*, rsi = client*, rdx = params*, rcx = client_handle
;        (params: u32 width, height, format, pad; u64 modifier)
;   OUT: rax = buffer_handle, negative error
; ---------------------------------------------------------------------------
global buffer_create
buffer_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov rbx, rdi        ; server
    mov r12, rsi        ; client
    mov r13, rdx        ; params
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Validate format
    mov edi, [r13 + 8]
    call buffer_validate_format
    test rax, rax
    jz .bad_format

    ; Validate dimensions
    mov eax, [r13 + 0]      ; width
    mov edx, [r13 + 4]      ; height
    test eax, eax
    jz .bad_dim
    test edx, edx
    jz .bad_dim
    cmp eax, 32768
    ja .bad_dim
    cmp edx, 32768
    ja .bad_dim

    ; Stride and size
    cmp dword [r13 + 8], DRM_FORMAT_RGB565
    je .two_bytes
    shl eax, 2
    jmp .sized
.two_bytes:
    add eax, eax
.sized:
    add eax, 3
    and eax, ~3
    mov r15d, eax           ; stride
    imul rax, rdx
    mov r14, rax            ; size

    ; The header first: nothing to undo if the client's arena is out of room
    mov rdi, [r12 + Client.arena]
    mov esi, Buffer_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rdx, rax
    xor eax, eax
    mov ecx, Buffer_size
    rep stosb
    mov [rsp], rdx          ; buffer*

    mov rdi, r14
    mov esi, MEM_DMA
    call ut_mem_alloc
    test rax, rax
    js .out
    mov rcx, [rsp]
    mov [rcx + Buffer.base], rax
    mov [rcx + Buffer.dma_addr], rdx
    mov [rcx + Buffer.region], r8
    mov [rcx + Buffer.size], r14
    mov [rcx + Buffer.stride], r15
    mov eax, [r13 + 0]
    mov [rcx + Buffer.width], rax
    mov eax, [r13 + 4]
    mov [rcx + Buffer.height], rax
    mov eax, [r13 + 8]
    mov [rcx + Buffer.format], rax
    mov rax, [r13 + 16]
    mov [rcx + Buffer.modifier], rax
    mov qword [rcx + Buffer.state], Buffer_ALLOCATED
    mov qword [rcx + Buffer.refcount], 1
    mov [rcx + Buffer.client], r12
    mov rax, [r12 + Client.id]
    mov [rcx + Buffer.client_id], rax

    ; Create handle in server's buffer table
    mov rdi, [rbx + Server.buffer_table]
    mov rsi, rcx
    call handle_create
    mov rcx, [rsp]
    test rax, rax
    jz .no_handle
    mov [rcx + Buffer.handle], rax
    mov rdx, [r12 + Client.buffers]
    mov [rcx + Buffer.client_next], rdx
    mov [r12 + Client.buffers], rcx
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.no_handle:
    mov rdi, [rcx + Buffer.region]
    call ut_mem_free
.oom:
    mov rax, -(ENOMEM)
    jmp .out
.bad_format:
    mov rax, -(EBUF_FORMAT)
    jmp .out
.bad_dim:
    mov rax, -(EBUF_SIZE)
    jmp .out

; ---------------------------------------------------------------------------
; buffer_validate_format
;   Check if format is supported
;   IN:  rdi = format
;   OUT: rax = 1 if supported, 0 if not
; ---------------------------------------------------------------------------
buffer_validate_format:
    PROLOGUE
    cmp rdi, DRM_FORMAT_BGRA8888
    je .ok
    cmp rdi, DRM_FORMAT_BGR8888
    je .ok
    cmp rdi, DRM_FORMAT_RGB565
    je .ok
    cmp rdi, DRM_FORMAT_XRGB2101010
    je .ok
    xor rax, rax
    leave
    ret
.ok:
    mov rax, 1
    leave
    ret

; ---------------------------------------------------------------------------
; buffer_destroy
;   Destroy buffer (server-side)
;   IN:  rdi = server*, rsi = buffer_handle
;   OUT: rax = 0 OK, -EBUF_BUSY if there is no such buffer
; ---------------------------------------------------------------------------
global buffer_destroy
buffer_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Resolve handle
    mov rdi, [rbx + Server.buffer_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov r13, rax

    ; Decrement refcount
    lock dec qword [r13 + Buffer.refcount]
    jnz .done

    ; Off the client's list
    mov rcx, [r13 + Buffer.client]
    lea rcx, [rcx + Client.buffers]
.find:
    mov rax, [rcx]
    test rax, rax
    jz .unlinked
    cmp rax, r13
    je .unlink
    lea rcx, [rax + Buffer.client_next]
    jmp .find
.unlink:
    mov rax, [r13 + Buffer.client_next]
    mov [rcx], rax
.unlinked:

    ; Free the pixels
    mov rdi, [r13 + Buffer.region]
    call ut_mem_free

    ; Destroy handle
    mov rdi, [rbx + Server.buffer_table]
    mov rsi, r12
    call handle_destroy

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.not_found:
    mov rax, -(EBUF_BUSY)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; buffer_destroy_client
;   Destroy every buffer of a client (it is going away, references or not)
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global buffer_destroy_client
buffer_destroy_client:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
.next:
    mov rax, [r12 + Client.buffers]
    test rax, rax
    jz .done
    mov qword [rax + Buffer.refcount], 1
    mov rdi, rbx
    mov rsi, [rax + Buffer.handle]
    call buffer_destroy
    jmp .next
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; buffer_attach
;   Attach buffer to surface
;   IN:  rdi = server*, rsi = surface*, rdx = buffer_handle, rcx = x, r8 = y
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global buffer_attach
buffer_attach:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Resolve buffer
    mov rdi, [rbx + Server.buffer_table]
    mov rsi, r13
    call handle_resolve
    test rax, rax
    jz .bad_buffer
    mov rbx, rax

    ; Check buffer state
    cmp qword [rbx + Buffer.state], Buffer_ALLOCATED
    jne .bad_state

    ; Set on surface pending state
    lea rax, [r12 + Surface.pending]
    mov qword [rax + SurfaceState.buffer], r13
    mov dword [rax + SurfaceState.buf_x], r14d
    mov dword [rax + SurfaceState.buf_y], r15d
    mov dword [rax + SurfaceState.pending], 1

    ; Update buffer state
    mov qword [rbx + Buffer.state], Buffer_ATTACHED

    xor rax, rax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.bad_buffer:
    mov rax, -(EBUF_FORMAT)
    jmp .out
.bad_state:
    mov rax, -(EBUF_BUSY)
    jmp .out

section .data

global buffer_version
buffer_version: dq 0x010100
