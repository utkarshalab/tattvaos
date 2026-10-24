; ============================================================================
; Pixel Buffer — Raw Pixel Data with Metadata
; 32-bit BGRA premultiplied alpha (primary format)
; ============================================================================

%include "ugfx.inc"

extern arena_alloc

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
    sub rsp, 16
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
    mov [rsp], rax      ; stride

    ; Size
    imul rax, r13
    mov [rsp + 8], rax  ; size

    ; Alloc PixBuf struct
    mov rdi, r15
    mov rsi, 64
    call arena_alloc
    test rax, rax
    jz .oom
    mov rdx, rax
    mov rbx, rax        ; PixBuf*

    ; Alloc pixel data
    mov rdi, r15
    mov rsi, [rsp + 8]
    call arena_alloc
    test rax, rax
    jz .oom
    mov rdx, rax        ; pixel storage

    ; Fill
    mov qword [rbx + PixBuf_width], r12
    mov qword [rbx + PixBuf_height], r13
    mov rax, [rsp]
    mov qword [rbx + PixBuf_stride], rax
    mov qword [rbx + PixBuf_format], r14
    mov qword [rbx + PixBuf_data], rdx
    mov rax, [rsp + 8]
    mov qword [rbx + PixBuf_size], rax
    mov qword [rbx + PixBuf_refcount], 1
    mov qword [rbx + PixBuf_arena], r15
    mov rax, rbx
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.invalid:
    mov rax, -(EINVAL)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; pixbuf_premultiply
;   Convert straight-alpha BGRA to premultiplied BGRA in place (decision 0002),
;   rounding each channel to nearest: c' = round(c * a / 255).
;   IN:  rdi = PixBuf*
;   OUT: rax = 0 OK, -EINVAL
; ---------------------------------------------------------------------------
global pixbuf_premultiply
pixbuf_premultiply:
    PROLOGUE_SAVE rbx, r12, r13
    test rdi, rdi
    jz .pm_bad
    mov r12, [rdi + PixBuf_data]
    test r12, r12
    jz .pm_bad
    mov r13, [rdi + PixBuf_height]
    mov rbx, [rdi + PixBuf_stride]
    mov r11, [rdi + PixBuf_width]
.pm_row:
    test r13, r13
    jz .pm_done
    xor r10d, r10d
.pm_pixel:
    cmp r10, r11
    jae .pm_next_row
    movzx r9d, byte [r12 + r10 * 4 + 3]
    cmp r9d, 255
    je .pm_skip                       ; opaque pixels are unchanged
    lea r8, [r12 + r10 * 4]
    xor ecx, ecx
.pm_channel:
    movzx eax, byte [r8 + rcx]
    imul eax, r9d
    add eax, 128
    mov edx, eax
    shr edx, 8
    add eax, edx
    shr eax, 8
    mov [r8 + rcx], al
    inc ecx
    cmp ecx, 3
    jb .pm_channel
.pm_skip:
    inc r10
    jmp .pm_pixel
.pm_next_row:
    add r12, rbx
    dec r13
    jmp .pm_row
.pm_done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13
.pm_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13

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
    ; Arena storage is reclaimed with its owner; invalidate this object now.
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
    lea rcx, [rsi * 4]
    add rax, rcx
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
    lea r8, [rsi * 4]
    add rax, r8
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
