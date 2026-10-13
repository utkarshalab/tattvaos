; ============================================================================
; Buffer Management — Creation, Ownership Transfer, Format Negotiation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/color.inc"

; struct offsets (hoisted above use)
%define Buffer_handle        0
%define Buffer.handle 0
%define Buffer_generation    4
%define Buffer.generation 4
%define Buffer_width         8
%define Buffer.width 8
%define Buffer_height        12
%define Buffer.height 12
%define Buffer_stride        16
%define Buffer.stride 16
%define Buffer_format        20
%define Buffer.format 20
%define Buffer_modifier      24
%define Buffer.modifier 24
%define Buffer_base          32
%define Buffer.base 32
%define Buffer_dma_addr      40
%define Buffer.dma_addr 40
%define Buffer_size          48
%define Buffer.size 48
%define Buffer_acquire_fence 56
%define Buffer.acquire_fence 56
%define Buffer_release_fence 60
%define Buffer.release_fence 60
%define Buffer_timeline      64
%define Buffer.timeline 64
%define Buffer_acquire_point 68
%define Buffer.acquire_point 68
%define Buffer_release_point 76
%define Buffer.release_point 76
%define Buffer_state         84
%define Buffer.state 84
%define Buffer_refcount      88
%define Buffer.refcount 88
%define Buffer_client_id     92
%define Buffer.client_id 92
%define Buffer_size          96
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
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.buffer_table], 0
    mov qword [rbx + Server.buffer_pool], 0
    mov qword [rbx + Server.arena], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; buffer_create
;   Create buffer object
;   IN:  rdi = server*, rsi = client*, rdx = params*, rcx = client_handle
;   OUT: rax = buffer_handle, negative error
; ---------------------------------------------------------------------------
global buffer_create
buffer_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; server
    mov r12, rsi        ; client
    mov r13, rdx        ; params
    mov r14, rcx        ; client_handle
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Validate format
    mov eax, [r13 + 8]      ; format
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

    ; Calculate stride
    mov eax, [r13 + 0]      ; width
    shl eax, 2              ; * 4 bytes
    add eax, 3
    and eax, ~3
    mov r15d, eax           ; stride

    ; Calculate size
    imul rax, rdx

    ; Allocate DMA-able memory for buffer
    mov rdi, [rbx + Server.arena]
    mov rsi, rax
    mov rdx, MEM_DMA
    call tv_mem_alloc
    test rax, rax
    js .oom
    mov r12, rax            ; vaddr
    mov r13, rdx            ; paddr

    ; Allocate buffer object
    push r12
    push r13
    mov rdi, [rbx + Server.arena]
    mov rsi, 96             ; Buffer struct size
    call arena_alloc
    pop r13
    pop r12
    test rax, rax
    jz .oom
    mov rbx, rax            ; buffer*

    ; Fill buffer struct
    mov qword [rbx + Buffer.handle], 0
    mov qword [rbx + Buffer.generation], 0
    mov dword [rbx + Buffer.width], [r13 + 0]
    mov dword [rbx + Buffer.height], [r13 + 4]
    mov dword [rbx + Buffer.stride], r15d
    mov dword [rbx + Buffer.format], [r13 + 8]
    mov qword [rbx + Buffer.modifier], [r13 + 16]
    mov qword [rbx + Buffer.base], r12
    mov qword [rbx + Buffer.dma_addr], r13
    mov qword [rbx + Buffer.size], rax
    mov dword [rbx + Buffer.acquire_fence], 0
    mov dword [rbx + Buffer.release_fence], 0
    mov dword [rbx + Buffer.timeline], 0
    mov qword [rbx + Buffer.acquire_point], 0
    mov qword [rbx + Buffer.release_point], 0
    mov byte [rbx + Buffer.state], 1  ; ALLOCATED
    mov dword [rbx + Buffer.refcount], 1
    mov qword [rbx + Buffer.client_id], [r12 + Client.id]

    ; Create handle in server's buffer table
    mov rdi, [rdi + Server.buffer_table]
    mov rsi, rbx
    call handle_create
    test rax, rax
    jz .oom
    mov [rbx + Buffer.handle], eax

    ; Return handle to client
    mov rax, [rbx + Buffer.handle]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.bad_format:
    mov rax, -(EBUF_FORMAT)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad_dim:
    mov rax, -(EBUF_SIZE)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

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
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global buffer_destroy
buffer_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Resolve handle
    mov rdi, [rbx + Server.buffer_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov rbx, rax

    ; Decrement refcount
    lock dec dword [rbx + Buffer.refcount]
    jnz .done

    ; Free DMA memory
    mov rdi, [rbx + Buffer.dma_addr]
    call tv_dma_free

    ; Destroy handle
    mov rdi, [rdi + Server.buffer_table]
    mov rsi, r12
    call handle_destroy

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.not_found:
    mov rax, -(EBUF_BUSY)
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
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
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
    cmp byte [rbx + Buffer.state], 1  ; ALLOCATED
    jne .bad_state

    ; Set on surface pending state
    mov rax, [r12 + Surface.pending]
    mov qword [rax + SurfaceState.buffer], r13
    mov dword [rax + SurfaceState.buf_x], r14d
    mov dword [rax + SurfaceState.buf_y], r8d
    mov byte [rax + SurfaceState.pending], 1

    ; Update buffer state
    mov byte [rbx + Buffer.state], 2  ; ATTACHED

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.bad_buffer:
    mov rax, -(EBUF_FORMAT)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.bad_state:
    mov rax, -(EBUF_BUSY)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data



global buffer_version
buffer_version: dq 0x010000
