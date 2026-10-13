; ============================================================================
; Pixel Buffer — Raw Pixel Data with Metadata
; 32-bit BGRA premultiplied alpha (primary format)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define PixBuf_width     0
%define PixBuf_height    8
%define PixBuf_stride    16
%define PixBuf_format    24
%define PixBuf_data      32
%define PixBuf_size      40
%define PixBuf_refcount  48
%define PixBuf_arena     56
%define PixBuf_size_total 64

section .text


; ---------------------------------------------------------------------------
; pixbuf_create (proper)
; ---------------------------------------------------------------------------
global pixbuf_create
pixbuf_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; arena
    mov r12, rsi        ; width
    mov r13, rdx        ; height
    mov r14, rcx        ; format
    mov r15, rbx        ; save arena

    ; Validate
    test r12, r12
    jz .invalid
    test r13, r13
    jz .invalid
    cmp r12, 32768
    ja .invalid
    cmp r13, 32768
    ja .invalid

    ; Stride
    mov rax, r12
    shl rax, 2
    add rax, 3
    and rax, ~3
    mov r12, rax        ; stride in r12

    ; Size
    imul rax, r13
    mov r13, rax        ; size in r13

    ; Alloc PixBuf struct
    mov rdi, r15
    mov rsi, 64
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax        ; PixBuf*

    ; Alloc pixel data
    mov rdi, r15
    mov rsi, r13
    call arena_alloc
    test rax, rax
    jz .oom

    ; Fill
    mov qword [rbx + PixBuf_width], rsi
    mov qword [rbx + PixBuf_height], rdx
    mov qword [rbx + PixBuf_stride], r12
    mov qword [rbx + PixBuf_format], r14
    mov qword [rbx + PixBuf_data], rax
    mov qword [rbx + PixBuf_size], r13
    mov qword [rbx + PixBuf_refcount], 1
    mov qword [rbx + PixBuf_arena], r15
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; pixbuf_destroy
;   Decrement refcount, free if zero
;   IN:  rdi = PixBuf*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global pixbuf_destroy
pixbuf_destroy:
    PROLOGUE
    ASSERT_PTR rdi
    lock dec qword [rdi + PixBuf_refcount]
    jnz .done
    ; Refcount hit zero - free data via arena
    ; Note: In practice, arena_free_all would be called on arena destroy
    ; For now just zero the struct
    mov qword [rdi + PixBuf_data], 0
    mov qword [rdi + PixBuf_size], 0
.done:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; pixbuf_ref
;   Increment refcount
;   IN:  rdi = PixBuf*
;   OUT: rax = PixBuf*
; ---------------------------------------------------------------------------
global pixbuf_ref
pixbuf_ref:
    PROLOGUE
    ASSERT_PTR rdi
    lock inc qword [rdi + PixBuf_refcount]
    mov rax, rdi
    leave
    ret

; ---------------------------------------------------------------------------
; pixbuf_get_pixel
;   Get pixel at (x,y)
;   IN:  rdi = PixBuf*, rsi = x, rdx = y
;   OUT: rax = pixel (u32 BGRA)
; ---------------------------------------------------------------------------
global pixbuf_get_pixel
pixbuf_get_pixel:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + PixBuf_width]
    cmp rsi, rax
    jae .oob
    mov rax, [rdi + PixBuf_height]
    cmp rdx, rax
    jae .oob

    mov rax, [rdi + PixBuf_stride]
    imul rax, rdx
    add rax, rsi
    shl rax, 2
    add rax, [rdi + PixBuf_data]
    mov eax, [rax]
    leave
    ret
.oob:
    xor eax, eax
    leave
    ret

; ---------------------------------------------------------------------------
; pixbuf_set_pixel
;   Set pixel at (x,y)
;   IN:  rdi = PixBuf*, rsi = x, rdx = y, rcx = pixel (u32)
;   OUT: rax = 0 OK, EINVAL if OOB
; ---------------------------------------------------------------------------
global pixbuf_set_pixel
pixbuf_set_pixel:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + PixBuf_width]
    cmp rsi, rax
    jae .oob
    mov rax, [rdi + PixBuf_height]
    cmp rdx, rax
    jae .oob

    mov rax, [rdi + PixBuf_stride]
    imul rax, rdx
    add rax, rsi
    shl rax, 2
    add rax, [rdi + PixBuf_data]
    mov [rax], ecx
    xor rax, rax
    leave
    ret
.oob:
    mov rax, -(EINVAL)
    leave
    ret

section .data

global pixbuf_version
pixbuf_version: dq 0x010000
