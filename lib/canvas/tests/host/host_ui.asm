; ============================================================================
; Host UI Tool — host_ui.asm
; Usage: host_ui <script> <out.raw>
; Draws server UI pieces into a buffer and writes it as BGRA rows:
;   script: u32 width, height, background, 0; u64 command count; commands,
;   each a u64 opcode and f64 arguments:
;     1 icon colour x y size weight name_length <name, padded to 8>
;         canvas_icon_draw onto the buffer
;     2 decor titlebar_height border_width titlebar_colour border_colour
;         button_bg button_fg n type x n
;         decoration_draw_frame for a toplevel the size of the buffer
;         (no title) with n buttons of the given types
; Exit status: 0 ok, 1 usage, 2 read error, 3 a call failed, 4 write
;   error, 6 unknown opcode. Used by tests/host/ui_icons_check.py.
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/pixbuf.inc"

%define HOST_SYS_WRITE  1
%define HOST_SYS_OPEN   2
%define HOST_SYS_FSTAT  5
%define HOST_SYS_MMAP   9
%define HOST_BUF_SIZE   (64 * 1024 * 1024)
%define MAX_BUTTONS     8
%define BUTTON_NODE     48              ; DecorationButton + the next pointer at 40

extern canvas_icon_draw
extern decoration_draw_frame
extern ut_mem_alloc
extern ut_task_exit

section .text

global _start
_start:
    mov r12, [rsp + 16]
    mov r13, [rsp + 24]
    mov rax, [rsp]
    and rsp, -16
    cmp rax, 3
    jne .usage
    mov rdi, r12
    xor esi, esi
    mov eax, HOST_SYS_OPEN
    syscall
    test rax, rax
    js .read_fail
    mov r14, rax
    sub rsp, 144
    mov rdi, r14
    mov rsi, rsp
    mov eax, HOST_SYS_FSTAT
    syscall
    mov r15, [rsp + 48]
    add rsp, 144
    cmp r15, 24
    jb .read_fail
    xor edi, edi
    mov rsi, r15
    mov edx, 1
    mov r10d, 2
    mov r8, r14
    xor r9d, r9d
    mov eax, HOST_SYS_MMAP
    syscall
    test rax, rax
    js .read_fail
    mov rbx, rax                        ; script
    ; the buffer as a PixBuf, filled with the background
    mov rdi, HOST_BUF_SIZE
    xor esi, esi
    call ut_mem_alloc
    test rax, rax
    js .call_fail
    mov ecx, [rbx]
    mov [rel pix + PixBuf_width], rcx
    mov edx, [rbx + 4]
    mov [rel pix + PixBuf_height], rdx
    shl rcx, 2
    mov [rel pix + PixBuf_stride], rcx
    mov [rel pix + PixBuf_data], rax
    imul rcx, rdx
    cmp rcx, HOST_BUF_SIZE
    ja .call_fail
    mov [rel pix + PixBuf_size], rcx
    mov qword [rel pix + PixBuf_refcount], 1
    mov rdi, rax
    shr rcx, 2
    mov eax, [rbx + 8]
    rep stosd
    mov r12, [rbx + 16]                 ; commands
    lea r14, [rbx + 24]
.command:
    test r12, r12
    jz .done
    mov rax, [r14]
    add r14, 8
    cmp rax, 1
    je .icon
    cmp rax, 2
    je .decor
    mov edi, 6
    jmp ut_task_exit
.icon:
    cvttsd2si rcx, qword [r14]          ; colour
    movsd xmm0, [r14 + 8]
    movsd xmm1, [r14 + 16]
    movsd xmm2, [r14 + 24]
    movsd xmm3, [r14 + 32]
    cvttsd2si rdx, qword [r14 + 40]     ; name length
    lea rsi, [r14 + 48]
    lea rax, [rdx + 7]
    and rax, -8
    lea r14, [rsi + rax]
    lea rdi, [rel pix]
    call canvas_icon_draw
    test rax, rax
    jnz .call_fail
    dec r12
    jmp .command
.decor:
    ; the toplevel, the decoration, the buttons, the draw state
    mov eax, [rbx]
    mov [rel toplevel + Toplevel.width], eax
    mov eax, [rbx + 4]
    mov [rel toplevel + Toplevel.height], eax
    mov qword [rel toplevel + Toplevel.title], 0
    lea rax, [rel toplevel]
    mov [rel decoration + Decoration.toplevel], rax
    cvttsd2si eax, qword [r14]
    mov [rel decoration + Decoration.titlebar_height], eax
    cvttsd2si eax, qword [r14 + 8]
    mov [rel decoration + Decoration.border_width], eax
    mov rax, [rel pix + PixBuf_data]
    mov [rel draw_state + DecorationDrawState.framebuffer], rax
    mov rax, [rel pix + PixBuf_stride]
    mov [rel draw_state + DecorationDrawState.stride], rax
    mov eax, [rbx]
    mov [rel draw_state + DecorationDrawState.width], eax
    mov eax, [rbx + 4]
    mov [rel draw_state + DecorationDrawState.height], eax
    cvttsd2si rax, qword [r14 + 16]
    mov [rel draw_state + DecorationDrawState.titlebar_color], eax
    cvttsd2si rax, qword [r14 + 24]
    mov [rel draw_state + DecorationDrawState.border_color], eax
    cvttsd2si rax, qword [r14 + 32]
    mov [rel draw_state + DecorationDrawState.button_bg_color], eax
    cvttsd2si rax, qword [r14 + 40]
    mov [rel draw_state + DecorationDrawState.button_fg_color], eax
    mov dword [rel draw_state + DecorationDrawState.inactive_alpha], 0
    cvttsd2si rcx, qword [r14 + 48]     ; n
    cmp rcx, MAX_BUTTONS
    ja .call_fail
    mov [rel decoration + Decoration.button_count], ecx
    lea rdx, [rel buttons]
    mov [rel decoration + Decoration.buttons], rdx
    xor r8d, r8d
.button:
    cmp r8, rcx
    jae .buttons_done
    imul r9, r8, BUTTON_NODE
    lea r9, [rdx + r9]
    cvttsd2si rax, qword [r14 + 56 + r8 * 8]
    mov [r9 + DecorationButton.type], eax
    mov dword [r9 + DecorationButton.state], 0
    lea rax, [r9 + BUTTON_NODE]
    lea r10, [r8 + 1]
    cmp r10, rcx
    jb .button_next
    xor eax, eax
.button_next:
    mov [r9 + 40], rax
    inc r8
    jmp .button
.buttons_done:
    lea r14, [r14 + 56 + rcx * 8]
    lea rdi, [rel draw_state]
    lea rsi, [rel decoration]
    mov rdx, [rel pix + PixBuf_data]
    call decoration_draw_frame
    test rax, rax
    jnz .call_fail
    dec r12
    jmp .command
.done:
    mov rdi, r13
    mov esi, 0x241
    mov edx, 0644o
    mov eax, HOST_SYS_OPEN
    syscall
    test rax, rax
    js .write_fail
    mov r14, rax
    mov rsi, [rel pix + PixBuf_data]
    mov rdx, [rel pix + PixBuf_size]
.write:
    test rdx, rdx
    jz .ok
    mov rdi, r14
    push rsi
    push rdx
    mov eax, HOST_SYS_WRITE
    syscall
    pop rdx
    pop rsi
    test rax, rax
    jle .write_fail
    add rsi, rax
    sub rdx, rax
    jmp .write
.ok:
    xor edi, edi
    jmp ut_task_exit
.usage:
    mov edi, 1
    jmp ut_task_exit
.read_fail:
    mov edi, 2
    jmp ut_task_exit
.call_fail:
    mov edi, 3
    jmp ut_task_exit
.write_fail:
    mov edi, 4
    jmp ut_task_exit

section .bss
alignb 16
pix:            resb PixBuf_SIZE
toplevel:       resb 256
decoration:     resb Decoration_SIZE
draw_state:     resb DecorationDrawState_SIZE
alignb 16
buttons:        resb MAX_BUTTONS * BUTTON_NODE
