; ============================================================================
; Virtual Output — In-Memory Output Backed by Tile-Diff + Encoders
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc VirtualOutput {
    .output:        resq 1
    .fb:            resq 1
    .tilediff:      resq 1
    .seq:           resq 1
}
%define VirtualOutput_size    32

; ---------------------------------------------------------------------------
; virtual_output_create
;   IN: rdi=server*, rsi=width, rdx=height
; ---------------------------------------------------------------------------
global virtual_output_create
virtual_output_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    test r12, r12
    jz .invalid
    test r13, r13
    jz .invalid
    mov rdi, [rbx + Server.arena]
    mov rsi, VirtualOutput_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax
    ; framebuffer pixbuf
    mov rdi, [rbx + Server.arena]
    mov rsi, r12
    mov rdx, r13
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .oom
    mov [r14 + VirtualOutput.fb], rax
    ; output object
    mov rdi, rbx
    mov rsi, rax
    call output_create
    test rax, rax
    jz .oom
    mov [r14 + VirtualOutput.output], rax
    ; tile diff
    mov rdi, [rbx + Server.arena]
    mov rsi, r14
    add rsi, VirtualOutput.tilediff
    sub rsi, VirtualOutput.tilediff
    ; allocate TileDiff struct
    mov rdi, [rbx + Server.arena]
    mov rsi, 48
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r14 + VirtualOutput.tilediff], rax
    mov rdi, [rbx + Server.arena]
    mov rsi, rax
    mov rdx, r12
    mov rcx, r13
    call tile_diff_init
    test rax, rax
    jnz .fail
    mov qword [r14 + VirtualOutput.seq], 0
    mov rax, r14
    ret
.invalid:
    RETURN_ERROR EINVAL
.oom:
    RETURN_ERROR ENOMEM
.fail:
    RETURN_ERROR EIO

; ---------------------------------------------------------------------------
; virtual_output_damage
;   Run tile diff over current framebuffer; returns dirty count
; ---------------------------------------------------------------------------
global virtual_output_damage
virtual_output_damage:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + VirtualOutput.fb]
    mov rdi, [rbx + VirtualOutput.tilediff]
    mov rsi, [r12 + PixBuf.data]
    mov rdx, [r12 + PixBuf.stride]
    mov ecx, [r12 + PixBuf.width]
    mov r8d, [r12 + PixBuf.height]
    call tile_diff_update
    ret

section .data
global virtual_output_version
virtual_output_version: dq 0x010000
