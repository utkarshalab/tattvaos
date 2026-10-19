; ============================================================================
; Move/Resize — Interactive Window Move and Resize
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define MOVE_RESIZE_MOVE      0
%define MOVE_RESIZE_RESIZE    1
%define RESIZE_EDGE_NONE      0
%define RESIZE_EDGE_TOP       (1 << 0)
%define RESIZE_EDGE_BOTTOM    (1 << 1)
%define RESIZE_EDGE_LEFT      (1 << 2)
%define RESIZE_EDGE_RIGHT     (1 << 3)

section .text

; ---------------------------------------------------------------------------
; move_resize_init
;   Initialize move/resize subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global move_resize_init
move_resize_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.move_resize], 0
    mov qword [rbx + Server.arena], r12

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; move_resize_start
;   Start move or resize operation
;   IN:  rdi = server*, rsi = seat*, rdx = toplevel*, rcx = type, r8 = edges, r9 = x, r10 = y
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global move_resize_start
move_resize_start:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp,24
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
    mov [rsp],r9d
    mov [rsp+4],r10d
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    cmp qword [rbx + Server.move_resize],0
    jne .busy

    ; Allocate move/resize state
    mov rdi, [rbx + Server.arena]
    mov rsi, MoveResize_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rsp+8],rax

    ; Initialize move/resize state
    mov r11,[rsp+8]
    mov [r11 + MoveResize.seat],r12
    mov [r11 + MoveResize.toplevel],r13
    mov [r11 + MoveResize.type],r14d
    mov [r11 + MoveResize.edges],r15d
    mov eax,[rsp]
    mov [r11 + MoveResize.start_x],eax
    mov eax,[rsp+4]
    mov [r11 + MoveResize.start_y],eax
    mov eax,[r13 + Toplevel.x]
    mov [r11 + MoveResize.initial_x],eax
    mov eax,[r13 + Toplevel.y]
    mov [r11 + MoveResize.initial_y],eax
    mov eax,[r13 + Toplevel.width]
    mov [r11 + MoveResize.surface_x],eax
    mov eax,[r13 + Toplevel.height]
    mov [r11 + MoveResize.surface_y],eax
    mov dword [r11 + MoveResize.grab_serial],0
    call tv_time_now_ns
    mov r11,[rsp+8]
    mov [r11 + MoveResize.grab_time],rax
    mov [rbx + Server.move_resize],r11

    xor rax, rax
    add rsp,24
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    add rsp,24
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.busy:
    mov rax,-EBUSY
    add rsp,24
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; move_resize_update
;   Update move/resize operation
; ---------------------------------------------------------------------------
global move_resize_update
move_resize_update:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx

    mov r15,[rbx + Server.move_resize]
    test r15,r15
    jz .done
    cmp [r15 + MoveResize.seat],r12
    jne .denied

    ; Update position based on type
    cmp dword [r15 + MoveResize.type],MOVE_RESIZE_MOVE
    je .move
    cmp dword [r15 + MoveResize.type],MOVE_RESIZE_RESIZE
    jne .invalid
    mov r12,[r15 + MoveResize.toplevel]
    mov eax,r13d
    sub eax,[r15 + MoveResize.start_x]
    mov edx,r14d
    sub edx,[r15 + MoveResize.start_y]
    mov r8d,[r15 + MoveResize.initial_x]
    mov r9d,[r15 + MoveResize.initial_y]
    mov r10d,[r15 + MoveResize.surface_x]
    mov r11d,[r15 + MoveResize.surface_y]
    test dword [r15 + MoveResize.edges],RESIZE_EDGE_LEFT
    jz .right
    add r8d,eax
    sub r10d,eax
.right:
    test dword [r15 + MoveResize.edges],RESIZE_EDGE_RIGHT
    jz .top
    add r10d,eax
.top:
    test dword [r15 + MoveResize.edges],RESIZE_EDGE_TOP
    jz .bottom
    add r9d,edx
    sub r11d,edx
.bottom:
    test dword [r15 + MoveResize.edges],RESIZE_EDGE_BOTTOM
    jz .clamp
    add r11d,edx
.clamp:
    cmp r10d,1
    jge .width_ok
    mov r10d,1
.width_ok:
    cmp r11d,1
    jge .height_ok
    mov r11d,1
.height_ok:
    mov [r12 + Toplevel.pending_width],r10d
    mov [r12 + Toplevel.pending_height],r11d
    mov byte [r12 + Toplevel.pending_state],1
    mov rdi,r12
    mov esi,r8d
    mov edx,r9d
    call toplevel_set_position
    mov rdi,r12
    call toplevel_schedule_configure
    jmp .done

.move:
    mov r12,[r15 + MoveResize.toplevel]
    mov esi,r13d
    sub esi,[r15 + MoveResize.start_x]
    add esi,[r15 + MoveResize.initial_x]
    mov edx,r14d
    sub edx,[r15 + MoveResize.start_y]
    add edx,[r15 + MoveResize.initial_y]
    mov rdi,r12
    call toplevel_set_position
    jmp .done

.denied:
    mov rax,-EPERM
    jmp .out
.invalid:
    mov rax,-EINVAL
    jmp .out

.done:
    xor rax, rax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; move_resize_end
;   End move/resize operation
; ---------------------------------------------------------------------------
global move_resize_end
move_resize_end:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Free move/resize state
    mov rdi, [rbx + Server.arena]
    mov rsi, [rbx + Server.move_resize]
    call arena_free

    mov qword [rbx + Server.move_resize], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global move_resize_version
move_resize_version: dq 0x010000
