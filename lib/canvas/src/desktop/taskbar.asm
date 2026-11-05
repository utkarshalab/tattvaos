; ============================================================================
; Taskbar — a Block for Every Window, Along the Bottom
; ============================================================================
; A trusted client inside canvasd, through the client library, as the
; greeter is. It is a top layer along the bottom edge that keeps its height
; from maximized windows, and it watches the window list: a block for each
; window of the workspace shown, in the order they came, coloured from its
; app id, grey while minimized, with a stripe over the one that has the
; keyboard; at the right end a square for each workspace, the one shown
; bright. Text waits for fonts. A click on a block activates that window, on
; the active window's block minimizes it; a click on a square shows that
; workspace.
;
; taskbar_start makes everything with library calls that turn server_poll,
; so it runs outside a turn; canvasd's loop calls taskbar_step after each
; server_poll.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/backend.inc"
%include "inc/canvas_client.inc"
%include "inc/taskbar.inc"

extern arena_alloc
extern canvas_buffer_create
extern canvas_buffer_mmap
extern canvas_connect_pair
extern canvas_event_poll
extern canvas_layer_create
extern canvas_layer_set_exclusive
extern canvas_surface_attach
extern canvas_surface_commit
extern canvas_surface_create
extern canvas_surface_damage
extern canvas_window_activate
extern canvas_window_list_set_workspace
extern canvas_window_list_subscribe
extern canvas_window_minimize
extern client_accept_trusted
extern server_poll

%define EV_DATA     (Taskbar.event + ClientEvent.data)
%define STATE_MINIMIZED 4

; How much of the right end the workspace squares take
%define SWITCHER_W  (TASKBAR_WS_COUNT * (TASKBAR_WS_W + TASKBAR_GAP))

section .text

; ---------------------------------------------------------------------------
; taskbar_start
;   Connect a taskbar and show it
;   IN:  rdi = server*, rsi = arena*
;   OUT: rax = taskbar*, -ENODEV with no output, -EINVAL if the output is
;        not taller than the bar, -ENOMEM, other negative errors
; ---------------------------------------------------------------------------
global taskbar_start
taskbar_start:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov r12, rdi
    mov r13, rsi
    mov rax, [r12 + Server.outputs]
    test rax, rax
    jz .no_output
    cmp dword [rax + Output.height], TASKBAR_H
    jbe .too_small

    mov rdi, r13
    mov esi, Taskbar_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, Taskbar_size
    rep stosb
    mov [rbx + Taskbar.server], r12
    mov rax, [r12 + Server.outputs]
    mov ecx, [rax + Output.width]
    mov [rbx + Taskbar.width], ecx
    shl ecx, 2
    mov [rbx + Taskbar.stride], ecx
    mov dword [rbx + Taskbar.pointer_x], -1

    mov rdi, r12
    lea rsi, [rbx + Taskbar.pair]
    mov edx, CLIENT_CAP_LAYER | CLIENT_CAP_WINDOWS
    call client_accept_trusted
    test rax, rax
    js .out
    lea rdi, [rbx + Taskbar.pair]
    lea rsi, [rel server_poll]
    mov rdx, r12
    call canvas_connect_pair
    test rax, rax
    jz .oom
    mov [rbx + Taskbar.conn], rax

    mov rdi, rax
    mov esi, [rbx + Taskbar.width]
    mov edx, TASKBAR_H
    mov ecx, DRM_FORMAT_BGR8888
    call canvas_buffer_create
    test rax, rax
    js .out
    mov [rbx + Taskbar.buffer], eax
    mov rdi, [rbx + Taskbar.conn]
    mov esi, eax
    call canvas_buffer_mmap
    mov [rbx + Taskbar.pixels], rax
    mov rdi, [rbx + Taskbar.conn]
    call canvas_surface_create
    test rax, rax
    js .out
    mov [rbx + Taskbar.surface], eax
    mov rdi, [rbx + Taskbar.conn]
    mov esi, eax
    mov edx, CANVAS_LAYER_TOP
    mov ecx, CANVAS_ANCHOR_BOTTOM | CANVAS_ANCHOR_LEFT | CANVAS_ANCHOR_RIGHT
    xor r8d, r8d
    call canvas_layer_create
    test rax, rax
    js .out
    mov rdi, [rbx + Taskbar.conn]
    mov esi, [rbx + Taskbar.surface]
    mov edx, TASKBAR_H
    call canvas_layer_set_exclusive
    mov rdi, [rbx + Taskbar.conn]
    call canvas_window_list_subscribe

    mov rdi, rbx
    call draw
    mov rdi, [rbx + Taskbar.conn]
    mov esi, [rbx + Taskbar.surface]
    mov edx, [rbx + Taskbar.buffer]
    xor ecx, ecx
    xor r8d, r8d
    call canvas_surface_attach
    mov rdi, rbx
    call show
    mov [r12 + Server.taskbar], rbx
    mov rax, rbx
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.no_output:
    mov rax, -(ENODEV)
    jmp .out
.too_small:
    mov rax, -(EINVAL)
    jmp .out
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; taskbar_step
;   Everything that came in, then a new frame if anything changed
;   IN:  rdi = taskbar*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global taskbar_step
taskbar_step:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
.next:
    mov rdi, [rbx + Taskbar.conn]
    lea rsi, [rbx + Taskbar.event]
    call canvas_event_poll
    test eax, eax
    jz .read_all
    mov eax, [rbx + Taskbar.event + ClientEvent.type]
    cmp eax, CANVAS_EV_WINDOW
    je .window
    cmp eax, CANVAS_EV_WINDOW_REMOVED
    je .removed
    cmp eax, CANVAS_EV_WINDOW_ACTIVATED
    je .activated
    cmp eax, CANVAS_EV_WORKSPACE
    je .workspace
    cmp eax, CANVAS_EV_POINTER_ENTER
    je .pointer
    cmp eax, CANVAS_EV_MOTION
    je .pointer
    cmp eax, CANVAS_EV_POINTER_LEAVE
    je .left
    cmp eax, CANVAS_EV_BUTTON
    je .button
    jmp .next

    ; window(id, states, title, app_id): new at the end, or changed
.window:
    mov edi, [rbx + EV_DATA]
    mov rsi, rbx
    call find_entry
    test rax, rax
    jnz .update
    mov ecx, [rbx + Taskbar.count]
    cmp ecx, TASKBAR_MAX
    jae .next                           ; full: not shown
    inc dword [rbx + Taskbar.count]
    shl ecx, 4
    lea rax, [rbx + Taskbar.entries + rcx]
    mov ecx, [rbx + EV_DATA]
    mov [rax + TaskbarEntry.id], ecx
.update:
    mov r12, rax
    mov ecx, [rbx + EV_DATA + 4]
    mov [r12 + TaskbarEntry.states], ecx
    mov ecx, [rbx + EV_DATA + 8]
    mov [r12 + TaskbarEntry.workspace], ecx
    lea rdi, [rbx + EV_DATA + 76]       ; its app id
    call app_color
    mov [r12 + TaskbarEntry.color], eax
    jmp .changed

    ; removed(id): the later ones move up
.removed:
    mov edi, [rbx + EV_DATA]
    mov rsi, rbx
    call find_entry
    test rax, rax
    jz .next
    lea rdi, [rax]
    lea rsi, [rax + TaskbarEntry_size]
    lea rcx, [rbx + Taskbar.entries]
    mov edx, [rbx + Taskbar.count]
    shl edx, 4
    add rcx, rdx                        ; the end
    sub rcx, rsi
    rep movsb
    dec dword [rbx + Taskbar.count]
    jmp .changed

.activated:
    mov eax, [rbx + EV_DATA]
    mov [rbx + Taskbar.active], eax
    jmp .changed

    ; workspace(current, count)
.workspace:
    mov eax, [rbx + EV_DATA]
    mov [rbx + Taskbar.workspace], eax
    jmp .changed

    ; enter or motion (time, surface, x, y): where a click would land
.pointer:
    mov eax, [rbx + EV_DATA + 12]
    mov [rbx + Taskbar.pointer_x], eax
    jmp .next
.left:
    mov dword [rbx + Taskbar.pointer_x], -1
    jmp .next

    ; button(time, surface, button, state): a left press on a block
.button:
    cmp dword [rbx + EV_DATA + 12], 0
    jne .next
    cmp dword [rbx + EV_DATA + 16], 1
    jne .next
    mov rdi, rbx
    call square_at_pointer
    test eax, eax
    js .block
    mov rdi, [rbx + Taskbar.conn]
    mov esi, eax
    call canvas_window_list_set_workspace
    jmp .next
.block:
    mov rdi, rbx
    call entry_at_pointer
    test rax, rax
    jz .next
    mov esi, [rax + TaskbarEntry.id]
    mov rdi, [rbx + Taskbar.conn]
    cmp esi, [rbx + Taskbar.active]
    jne .activate
    test dword [rax + TaskbarEntry.states], STATE_MINIMIZED
    jnz .activate
    call canvas_window_minimize         ; the active one: out of the way
    jmp .next
.activate:
    call canvas_window_activate
    jmp .next

.changed:
    mov dword [rbx + Taskbar.dirty], 1
    jmp .next
.read_all:
    cmp dword [rbx + Taskbar.dirty], 0
    je .done
    mov dword [rbx + Taskbar.dirty], 0
    mov rdi, rbx
    call draw
    mov rdi, rbx
    call show
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; The bar, the blocks of the workspace shown, the workspace squares.
; rdi = taskbar
draw:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    xor esi, esi
    xor edx, edx
    mov ecx, [rbx + Taskbar.width]
    mov r8d, TASKBAR_H
    mov r9d, TASKBAR_BG
    call fill

    ; The squares, the shown one bright
    xor r12d, r12d
.square:
    cmp r12d, TASKBAR_WS_COUNT
    jae .blocks
    mov esi, [rbx + Taskbar.width]
    sub esi, SWITCHER_W
    imul eax, r12d, TASKBAR_WS_W + TASKBAR_GAP
    add esi, eax
    mov r9d, TASKBAR_DIM
    cmp r12d, [rbx + Taskbar.workspace]
    jne .square_color
    mov r9d, TASKBAR_INK
.square_color:
    mov rdi, rbx
    mov edx, TASKBAR_PAD
    mov ecx, TASKBAR_WS_W
    mov r8d, TASKBAR_H - 2 * TASKBAR_PAD
    call fill
    inc r12d
    jmp .square

.blocks:
    xor r12d, r12d                      ; the entry
    xor r14d, r14d                      ; the slot on the bar
.block:
    cmp r12d, [rbx + Taskbar.count]
    jae .out
    mov eax, r12d
    shl eax, 4
    mov eax, [rbx + Taskbar.entries + rax + TaskbarEntry.workspace]
    cmp eax, [rbx + Taskbar.workspace]
    jne .next                           ; another workspace's
    imul r13d, r14d, TASKBAR_ENTRY_W + TASKBAR_GAP
    add r13d, TASKBAR_PAD               ; its x
    inc r14d
    mov eax, r13d
    add eax, TASKBAR_ENTRY_W
    mov ecx, [rbx + Taskbar.width]
    sub ecx, SWITCHER_W
    cmp eax, ecx
    ja .out                             ; no room for more
    mov eax, r12d
    shl eax, 4
    lea rax, [rbx + Taskbar.entries + rax]
    mov r9d, [rax + TaskbarEntry.color]
    test dword [rax + TaskbarEntry.states], STATE_MINIMIZED
    jz .colored
    mov r9d, TASKBAR_DIM
.colored:
    mov rdi, rbx
    mov esi, r13d
    mov edx, TASKBAR_PAD
    mov ecx, TASKBAR_ENTRY_W
    mov r8d, TASKBAR_H - 2 * TASKBAR_PAD
    call fill
    mov eax, r12d
    shl eax, 4
    mov eax, [rbx + Taskbar.entries + rax + TaskbarEntry.id]
    cmp eax, [rbx + Taskbar.active]
    jne .next
    mov rdi, rbx                        ; the one with the keyboard
    mov esi, r13d
    mov edx, TASKBAR_PAD
    mov ecx, TASKBAR_ENTRY_W
    mov r8d, TASKBAR_STRIPE
    mov r9d, TASKBAR_INK
    call fill
.next:
    inc r12d
    jmp .block
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; The whole bar damaged and committed.
; rdi = taskbar
show:
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + Taskbar.conn]
    mov esi, [rbx + Taskbar.surface]
    xor edx, edx
    xor ecx, ecx
    mov r8d, [rbx + Taskbar.width]
    mov r9d, TASKBAR_H
    call canvas_surface_damage
    mov rdi, [rbx + Taskbar.conn]
    mov esi, [rbx + Taskbar.surface]
    xor edx, edx
    call canvas_surface_commit
    pop rbx
    ret

; edi = id, rsi = taskbar -> rax = its TaskbarEntry, 0 if none
find_entry:
    lea rax, [rsi + Taskbar.entries]
    mov ecx, [rsi + Taskbar.count]
.next:
    test ecx, ecx
    jz .none
    cmp [rax + TaskbarEntry.id], edi
    je .done
    add rax, TaskbarEntry_size
    dec ecx
    jmp .next
.none:
    xor eax, eax
.done:
    ret

; rdi = taskbar -> rax = the TaskbarEntry whose block is under the pointer,
; 0 if none: the slot, then that slot's entry among the workspace shown's
entry_at_pointer:
    mov eax, [rdi + Taskbar.pointer_x]
    sub eax, TASKBAR_PAD
    js .none
    xor edx, edx
    mov ecx, TASKBAR_ENTRY_W + TASKBAR_GAP
    div ecx
    cmp edx, TASKBAR_ENTRY_W
    jae .none                           ; in a gap
    mov r8d, eax                        ; the slot
    lea rax, [rdi + Taskbar.entries]
    mov ecx, [rdi + Taskbar.count]
    mov edx, [rdi + Taskbar.workspace]
.find:
    test ecx, ecx
    jz .none
    cmp [rax + TaskbarEntry.workspace], edx
    jne .skip
    test r8d, r8d
    jz .found
    dec r8d
.skip:
    add rax, TaskbarEntry_size
    dec ecx
    jmp .find
.found:
    ret
.none:
    xor eax, eax
    ret

; rdi = taskbar -> eax = the workspace square under the pointer, -1 if none
square_at_pointer:
    mov eax, [rdi + Taskbar.pointer_x]
    test eax, eax
    js .none
    sub eax, [rdi + Taskbar.width]
    add eax, SWITCHER_W
    js .none
    xor edx, edx
    mov ecx, TASKBAR_WS_W + TASKBAR_GAP
    div ecx
    cmp edx, TASKBAR_WS_W
    jae .none
    cmp eax, TASKBAR_WS_COUNT
    jae .none
    ret
.none:
    mov eax, -1
    ret

; A colour for an app id, the same every time: FNV-1a over its bytes picks
; one of the palette's.
; rdi = NUL-terminated app id (at most 64 bytes) -> eax = colour
app_color:
    mov eax, 2166136261
    mov ecx, 64
.byte:
    movzx edx, byte [rdi]
    test edx, edx
    jz .pick
    xor eax, edx
    imul eax, eax, 16777619
    inc rdi
    dec ecx
    jnz .byte
.pick:
    and eax, 7
    lea rdx, [rel palette]
    mov eax, [rdx + rax * 4]
    ret

; rdi = taskbar, esi = x, edx = y, ecx = width, r8d = height, r9d = colour
fill:
    mov eax, r9d
    mov r9d, ecx
    mov r10, [rdi + Taskbar.pixels]
    mov r11d, [rdi + Taskbar.stride]
    mov edx, edx
    imul rdx, r11
    add r10, rdx
    mov esi, esi
    lea r10, [r10 + rsi * 4]
.row:
    mov rdi, r10
    mov ecx, r9d
    rep stosd
    add r10, r11
    dec r8d
    jnz .row
    ret

section .rodata
palette:        dd 0xFF4C78A8, 0xFFF58518, 0xFF54A24B, 0xFFE45756
                dd 0xFF72B7B2, 0xFFB279A2, 0xFFFF9DA6, 0xFF9D755D

section .data
global taskbar_version
taskbar_version: dq 0x010000
