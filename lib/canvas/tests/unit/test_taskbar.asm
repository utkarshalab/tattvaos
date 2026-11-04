; ============================================================================
; Unit Test — the Built-in Taskbar (src/desktop/taskbar.asm)
; ============================================================================
; test_taskbar_suite -> eax = failed cases (each case returns 0 / 1).
; A server on 400x80 with the taskbar, and an ordinary client with the shell
; capability making windows. A turn is server_poll then taskbar_step, as in
; canvasd's loop; clicks go in through virtual_input_inject.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"
%include "inc/color.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/channel.inc"
%include "inc/event.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/taskbar.inc"

extern arena_init
extern client_accept
extern handle_resolve
extern msgbuf_read
extern msgbuf_write
extern server_init
extern server_poll
extern taskbar_start
extern taskbar_step
extern virtual_input_inject

%define HEAP_SIZE   (4 * 1024 * 1024)
%define WIDTH       400
%define HEIGHT      80
%define BAR_Y       (HEIGHT - TASKBAR_H)
%define BLOCK_X(n)  (TASKBAR_PAD + (n) * (TASKBAR_ENTRY_W + TASKBAR_GAP))

section .text

global test_taskbar_suite
test_taskbar_suite:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tb_shown
    CASE tb_windows
    CASE tb_click
    CASE tb_removed
    CASE tb_exclusive
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

%macro SEND 3
    mov dword [rel hdr + MsgHdr.obj], %1
    mov word [rel hdr + MsgHdr.opcode], %2
    mov word [rel hdr + MsgHdr.flags], 0
    mov dword [rel hdr + MsgHdr.len], %3
    call send
%endmacro

; a click at x, y on the output, then the turns for it to be acted on
%macro CLICK 2
    mov edi, %1
    mov esi, %2
    call click
%endmacro

; the taskbar's pixel at x, y is colour
%macro PIXEL 3
    mov edi, %1
    mov esi, %2
    call bar_pixel
    cmp eax, %3
    jne .fail
%endmacro

fresh:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    mov edx, WIDTH
    mov ecx, HEIGHT
    xor r8d, r8d
    call server_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call taskbar_start
    mov [rel bar], rax
    lea rdi, [rel server]
    lea rsi, [rel pair]
    mov edx, CAP_SHELL
    call client_accept
    call poll
    call drain
    add rsp, 8
    ret

poll:
    sub rsp, 8
    lea rdi, [rel server]
    call server_poll
    mov rdi, [rel server + Server.taskbar]
    test rdi, rdi
    jz .out
    call taskbar_step
.out:
    add rsp, 8
    ret

send:
    sub rsp, 8
    mov rdi, [rel pair + ChannelPair.client_to_server]
    lea rsi, [rel hdr]
    lea rdx, [rel req]
    call msgbuf_write
    add rsp, 8
    ret

next_event:
    sub rsp, 8
    mov rdi, [rel pair + ChannelPair.server_to_client]
    lea rsi, [rel hdr]
    lea rdx, [rel ans]
    mov ecx, 256
    call msgbuf_read
    add rsp, 8
    ret

next_reply:
    sub rsp, 8
.next:
    call next_event
    test rax, rax
    js .done
    test word [rel hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jz .next
.done:
    add rsp, 8
    ret

drain:
    sub rsp, 8
.next:
    call next_event
    test rax, rax
    jns .next
    add rsp, 8
    ret

; A shown 16x12 window -> eax = its surface handle
new_window:
    push rbx
    mov dword [rel req], 16
    mov dword [rel req + 4], 12
    mov dword [rel req + 8], DRM_FORMAT_BGRA8888
    mov dword [rel req + 12], 0
    mov qword [rel req + 16], 0
    SEND CWP_OBJ_BUFFER, BUFFER_CREATE, 24
    call poll
    call next_reply
    mov eax, [rel ans]
    mov [rel buffer], eax
    SEND CWP_OBJ_SURFACE, SURFACE_CREATE, 0
    call poll
    call next_reply
    mov ebx, [rel ans]
    mov [rel req], ebx
    SEND CWP_OBJ_TOPLEVEL, TOPLEVEL_CREATE, 4
    mov [rel req], ebx
    mov eax, [rel buffer]
    mov [rel req + 4], eax
    mov qword [rel req + 8], 0
    mov qword [rel req + 16], 0
    SEND CWP_OBJ_SURFACE, SURFACE_ATTACH, 24
    mov dword [rel req + 4], 0
    mov dword [rel req + 8], 0
    mov dword [rel req + 12], 16
    mov dword [rel req + 16], 12
    SEND CWP_OBJ_SURFACE, SURFACE_DAMAGE, 20
    mov dword [rel req + 4], 0
    SEND CWP_OBJ_SURFACE, SURFACE_COMMIT, 8
    call poll
    call poll                           ; the taskbar hears of it
    call drain
    mov eax, ebx
    pop rbx
    ret

; edi = surface handle -> rax = Surface*
surface_of:
    sub rsp, 8
    mov esi, edi
    mov rdi, [rel server + Server.surface_table]
    call handle_resolve
    add rsp, 8
    ret

; edi = x, esi = y on the output: press and release there, then turns for
; the taskbar to read it and the server to act on what it asks
click:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    lea rdi, [rel server]
    mov esi, INPUT_POSITION
    mov edx, ebx
    mov ecx, r12d
    xor r8d, r8d
    call virtual_input_inject
    lea rdi, [rel server]
    mov esi, INPUT_BUTTON
    xor edx, edx
    mov ecx, 1
    xor r8d, r8d
    call virtual_input_inject
    lea rdi, [rel server]
    mov esi, INPUT_BUTTON
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call virtual_input_inject
    call poll
    call poll
    call poll
    call drain
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = x, esi = y on the bar -> eax = its pixel
bar_pixel:
    mov rax, [rel bar]
    imul esi, [rax + Taskbar.stride]
    mov rax, [rax + Taskbar.pixels]
    add rax, rsi
    mov eax, [rax + rdi * 4]
    ret

; ---------------------------------------------------------------------------
; Cases
; ---------------------------------------------------------------------------

; Along the bottom, empty
tb_shown:
    sub rsp, 8
    mov rax, [rel bar]
    test rax, rax
    jle .fail
    cmp dword [rax + Taskbar.count], 0
    jne .fail
    mov edi, [rax + Taskbar.surface]
    call surface_of
    test rax, rax
    jz .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 0
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], BAR_Y
    jne .fail
    PIXEL 0, 0, TASKBAR_BG
    PIXEL WIDTH - 1, TASKBAR_H - 1, TASKBAR_BG
    PASS

; A block for each window in the order they came, the stripe over the one
; with the keyboard
tb_windows:
    sub rsp, 8
    call new_window
    mov [rel surface_a], eax
    call new_window
    mov [rel surface_b], eax
    mov rax, [rel bar]
    cmp dword [rax + Taskbar.count], 2
    jne .fail
    cmp dword [rax + Taskbar.entries + 0 * TaskbarEntry_size + TaskbarEntry.id], 1
    jne .fail
    cmp dword [rax + Taskbar.entries + 1 * TaskbarEntry_size + TaskbarEntry.id], 2
    jne .fail
    cmp dword [rax + Taskbar.active], 2
    jne .fail
    mov ecx, [rax + Taskbar.entries + TaskbarEntry.color]
    mov [rel color], ecx
    PIXEL BLOCK_X(1) + 5, TASKBAR_PAD, TASKBAR_INK
    PIXEL BLOCK_X(0) + 5, TASKBAR_PAD, [rel color]
    PIXEL BLOCK_X(0) + 5, TASKBAR_PAD + 10, [rel color]
    PIXEL BLOCK_X(2) + 5, TASKBAR_PAD + 10, TASKBAR_BG
    PASS

; A click on a block activates its window; on the active one's, minimizes
; it; again, brings it back
tb_click:
    sub rsp, 8
    call new_window
    mov [rel surface_a], eax
    call new_window
    mov [rel surface_b], eax
    CLICK BLOCK_X(0) + 10, BAR_Y + 16
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail
    CLICK BLOCK_X(0) + 10, BAR_Y + 16
    mov edi, [rel surface_a]
    call surface_of
    cmp qword [rax + Surface.output], 0
    jne .fail                           ; minimized
    PIXEL BLOCK_X(0) + 5, TASKBAR_PAD + 10, TASKBAR_DIM
    CLICK BLOCK_X(0) + 10, BAR_Y + 16
    mov edi, [rel surface_a]
    call surface_of
    cmp qword [rax + Surface.output], 0
    je .fail                            ; back
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail
    PASS

; A window that goes takes its block with it
tb_removed:
    sub rsp, 8
    call new_window
    mov [rel surface_a], eax
    call new_window
    mov [rel surface_b], eax
    mov eax, [rel surface_a]
    mov [rel req], eax
    SEND CWP_OBJ_SURFACE, SURFACE_DESTROY, 4
    call poll
    call poll
    mov rax, [rel bar]
    cmp dword [rax + Taskbar.count], 1
    jne .fail
    cmp dword [rax + Taskbar.entries + TaskbarEntry.id], 2
    jne .fail
    PIXEL BLOCK_X(1) + 5, TASKBAR_PAD + 10, TASKBAR_BG
    PASS

; A maximized window stops above the bar
tb_exclusive:
    sub rsp, 8
    call new_window
    mov [rel surface_a], eax
    mov [rel req], eax
    SEND CWP_OBJ_TOPLEVEL, TOPLEVEL_SET_MAXIMIZED, 4
    call poll
.next:
    call next_event
    test rax, rax
    js .fail
    cmp dword [rel hdr + MsgHdr.obj], CWP_OBJ_TOPLEVEL
    jne .next
    cmp word [rel hdr + MsgHdr.opcode], TOPLEVEL_EVENT_CONFIGURE
    jne .next
    cmp dword [rel ans + 8], WIDTH
    jne .fail
    cmp dword [rel ans + 12], BAR_Y
    jne .fail
    PASS

section .bss
alignb 16
server:         resb Server_size
arena:          resb Arena_size
pair:           resb ChannelPair_size
hdr:            resb MsgHdr_size
bar:            resq 1
surface_a:      resd 1
surface_b:      resd 1
buffer:         resd 1
color:          resd 1
alignb 16
req:            resb 128
ans:            resb 256
alignb 16
heap:           resb HEAP_SIZE
