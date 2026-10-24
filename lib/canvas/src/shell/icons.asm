; ============================================================================
; Icons — the built-in UI icon pack, drawn through lib/ugfx
; ============================================================================
; assets/icons/ui.uic (28 Lucide icons, see assets/icons/README.md) is part of
; the Canvas image, so server-drawn UI (window decorations, the shell) has
; icons without loading anything.
;
;   canvas_icon_draw(pixbuf, name, length, colour, x, y, size, weight)
;
; Each call opens the pack (it is checked as ugfx_uic_open checks any
; pack), puts a ugfx context on the PixBuf and draws the icon fitted into
; the square (x, y, size, size): colour is straight BGRA, weight scales the
; stroke width (<= 0: 1). Its working memory is a private scratch arena,
; rewound after every call, so drawing allocates nothing that lasts. Not
; reentrant. It aligns its own stack, so callers need not.
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "ugfx.inc"

extern arena_init
extern arena_mark
extern arena_rewind
extern ugfx_uic_open
extern ugfx_uic_find
extern ugfx_uic_draw
extern ugfx_ctx_init

%define ICON_SCRATCH    (512 * 1024)
%define ICON_ARENA      64              ; bytes reserved for the Arena struct

; frame
%define I_UIC       0                   ; UgfxUic
%define I_CTX       UgfxUic_SIZE        ; UgfxContext
%define I_MARK      (I_CTX + UgfxContext_SIZE)
%define I_COLOUR    (I_MARK + 8)        ; u32
%define I_ARGS      (I_MARK + 16)       ; f64 x, y, size, weight
%define I_SIZE      ((I_ARGS + 32 + 15) & ~15)

section .rodata
align 16
canvas_ui_icons:
    incbin "assets/icons/ui.uic"
canvas_ui_icons_end:

section .text

; ---------------------------------------------------------------------------
; canvas_icon_draw
;   IN:  rdi = PixBuf*, rsi = icon name, edx = name length,
;        ecx = colour (straight BGRA), xmm0 = x, xmm1 = y, xmm2 = size,
;        xmm3 = stroke weight
;   OUT: rax = 0, -ENOENT (no such icon), -EINVAL, -ENOMEM
; ---------------------------------------------------------------------------
global canvas_icon_draw
canvas_icon_draw:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    and rsp, -16                        ; whatever the caller's alignment
    sub rsp, I_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov [rsp + I_COLOUR], ecx
    movsd [rsp + I_ARGS], xmm0
    movsd [rsp + I_ARGS + 8], xmm1
    movsd [rsp + I_ARGS + 16], xmm2
    movsd [rsp + I_ARGS + 24], xmm3
    mov rax, -(EINVAL)
    test rdi, rdi
    jz .out
    test rsi, rsi
    jz .out
    ; the scratch arena, set up on first use
    cmp byte [rel icon_ready], 0
    jne .ready
    lea rdi, [rel icon_arena]
    lea rsi, [rel icon_scratch]
    mov edx, ICON_SCRATCH
    call arena_init
    test rax, rax
    jnz .out
    mov byte [rel icon_ready], 1
.ready:
    lea rdi, [rel icon_arena]
    call arena_mark
    mov [rsp + I_MARK], rax
    lea rdi, [rsp + I_UIC]
    lea rsi, [rel icon_arena]
    lea rdx, [rel canvas_ui_icons]
    mov ecx, canvas_ui_icons_end - canvas_ui_icons
    call ugfx_uic_open
    test rax, rax
    jnz .rewind
    ; the icon, by name; the pixel size picks among design sizes
    lea rdi, [rsp + I_UIC]
    mov rsi, r12
    mov edx, r13d
    cvttsd2si ecx, qword [rsp + I_ARGS + 16]
    call ugfx_uic_find
    test rax, rax
    js .missing
    mov r14, rax
    lea rdi, [rsp + I_CTX]
    lea rsi, [rel icon_arena]
    mov rdx, rbx
    call ugfx_ctx_init
    test rax, rax
    jnz .rewind
    lea rdi, [rsp + I_UIC]
    mov esi, r14d
    lea rdx, [rsp + I_CTX]
    lea rcx, [rsp + I_COLOUR]
    mov r8d, 1
    movsd xmm0, [rsp + I_ARGS]
    movsd xmm1, [rsp + I_ARGS + 8]
    movsd xmm2, [rsp + I_ARGS + 16]
    movsd xmm3, [rsp + I_ARGS + 24]
    call ugfx_uic_draw
    jmp .rewind
.missing:
    mov rax, -(ENOENT)
.rewind:
    mov r15, rax
    lea rdi, [rel icon_arena]
    mov rsi, [rsp + I_MARK]
    call arena_rewind
    mov rax, r15
.out:
    lea rsp, [rbp - 40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

section .bss
alignb 16
icon_arena:         resb ICON_ARENA
icon_ready:         resb 1
alignb 4096
icon_scratch:       resb ICON_SCRATCH

section .data
global icons_version
icons_version: dq 0x010000
