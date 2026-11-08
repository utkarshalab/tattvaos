; ============================================================================
; Taskbar — a Block for Every Window, Along the Bottom
; ============================================================================
; A trusted client inside canvasd, through the client library, as the
; greeter is. It is a top layer along the bottom edge that keeps its height
; from maximized windows, and it watches the window list: a block for each
; window of the workspace shown, in the order they came, coloured from its
; app id, grey while minimized, with its title in the embedded font and a
; stripe over the one that has the keyboard; at the right end a square for each workspace, the one shown
; bright. Text waits for fonts. A click on a block activates that window, on
; the active window's block minimizes it; a click on a square shows that
; workspace.
;
; There is one for each output, on Server.taskbar through Taskbar.next, each
; listing every window. taskbar_start makes one with library calls that turn
; server_poll, so it runs outside a turn (taskbar_start_all one for each
; output); canvasd's loop calls taskbar_step_all after each server_poll,
; which also starts one on an output added since, once it is tall enough,
; and stops the one of an output taken away or made a mirror; a mirror has
; none. A stopped taskbar's record waits on Server.spare_taskbars for the
; next one started, so outputs coming and going do not use up the arena.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/backend.inc"
%include "inc/canvas_client.inc"
%include "inc/taskbar.inc"
%include "inc/ui_text.inc"

extern arena_alloc
extern canvas_buffer_create
extern canvas_buffer_mmap
extern canvas_connect_pair
extern canvas_event_poll
extern canvas_layer_create
extern canvas_layer_set_exclusive
extern canvas_layer_set_output
extern canvas_surface_attach
extern canvas_surface_commit
extern canvas_surface_create
extern canvas_surface_damage
extern canvas_window_activate
extern canvas_window_list_set_workspace
extern canvas_window_list_subscribe
extern canvas_window_minimize
extern canvas_disconnect
extern client_accept_trusted
extern client_disconnect
extern server_poll
extern ui_text_draw

%define EV_DATA     (Taskbar.event + ClientEvent.data)
%define STATE_MINIMIZED 4

; How much of the right end the workspace squares take
%define SWITCHER_W  (TASKBAR_WS_COUNT * (TASKBAR_WS_W + TASKBAR_GAP))

section .text

; ---------------------------------------------------------------------------
; taskbar_start_all
;   A taskbar on every output; one that is too small goes without
;   IN:  rdi = server*, rsi = arena*
;   OUT: rax = how many started, negative error
; ---------------------------------------------------------------------------
global taskbar_start_all
taskbar_start_all:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx                        ; the output's number
    xor r14d, r14d                      ; how many
.next:
    mov rdi, r12
    mov rsi, r13
    mov edx, ebx
    call taskbar_start
    cmp rax, -(ENODEV)
    je .done                            ; past the last output
    cmp rax, -(EINVAL)
    je .skip
    test rax, rax
    js .out
    inc r14d
.skip:
    inc ebx
    jmp .next
.done:
    mov eax, r14d
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; taskbar_step_all
;   A taskbar whose output was taken away stops, the others take their
;   output's place in the list as their number; taskbar_step for each; then
;   a taskbar for each output without one (added since), from the server's
;   arena. Outside a turn, as taskbar_start must be
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global taskbar_step_all
taskbar_step_all:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov r12, rdi
    lea r13, [r12 + Server.taskbar]     ; the link to the one looked at
.check:
    mov rbx, [r13]
    test rbx, rbx
    jz .checked
    mov rax, [r12 + Server.outputs]
    xor ecx, ecx
.place:
    test rax, rax
    jz .gone
    cmp rax, [rbx + Taskbar.output_ptr]
    jne .further
    cmp qword [rax + Output.mirror_of], 0
    jne .gone                           ; a mirror now
    jmp .here
.further:
    inc ecx
    mov rax, [rax + Output.next]
    jmp .place
.here:
    mov [rbx + Taskbar.output], ecx
    lea r13, [rbx + Taskbar.next]
    jmp .check
.gone:
    mov rax, [rbx + Taskbar.next]       ; off the list, its client gone
    mov [r13], rax
    mov rdi, r12
    mov rsi, [rbx + Taskbar.client_id]
    call client_disconnect
    mov rdi, [rbx + Taskbar.conn]
    call canvas_disconnect
    mov rax, [r12 + Server.spare_taskbars]  ; its record kept for the next
    mov [rbx + Taskbar.next], rax
    mov [r12 + Server.spare_taskbars], rbx
    jmp .check
.checked:
    mov rbx, [r12 + Server.taskbar]
.step:
    test rbx, rbx
    jz .stepped
    mov rdi, rbx
    call taskbar_step
    mov rbx, [rbx + Taskbar.next]
    jmp .step
.stepped:
    mov r13, [r12 + Server.outputs]
    xor ebx, ebx                        ; its number
.output:
    test r13, r13
    jz .done
    mov rax, [r12 + Server.taskbar]
.has:
    test rax, rax
    jz .start
    cmp [rax + Taskbar.output], ebx
    je .next
    mov rax, [rax + Taskbar.next]
    jmp .has
.start:
    cmp qword [r13 + Output.mirror_of], 0
    jne .next                           ; a mirror shows another's
    cmp dword [r13 + Output.height], TASKBAR_H
    jbe .next                           ; too small for one
    mov rdi, r12
    mov rsi, [r12 + Server.arena]
    mov edx, ebx
    call taskbar_start
.next:
    inc ebx
    mov r13, [r13 + Output.next]
    jmp .output
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; taskbar_start
;   Connect a taskbar on an output and show it
;   IN:  rdi = server*, rsi = arena*, edx = the output's number, 0 the first
;   OUT: rax = taskbar*, -ENODEV with no such output, -EINVAL if the output
;        is not taller than the bar, -ENOMEM, other negative errors
; ---------------------------------------------------------------------------
global taskbar_start
taskbar_start:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov rax, [r12 + Server.outputs]
    mov ecx, edx
.find:
    test rax, rax
    jz .no_output
    test ecx, ecx
    jz .found
    dec ecx
    mov rax, [rax + Output.next]
    jmp .find
.found:
    cmp dword [rax + Output.height], TASKBAR_H
    jbe .too_small
    push rax
    push rax                            ; 16-byte aligned

    mov rax, [r12 + Server.spare_taskbars]  ; a stopped one's record, else
    test rax, rax                           ; a new one
    jz .new
    mov rcx, [rax + Taskbar.next]
    mov [r12 + Server.spare_taskbars], rcx
    jmp .have
.new:
    mov rdi, r13
    mov esi, Taskbar_size
    call arena_alloc
.have:
    pop rcx
    pop rcx                             ; the output
    test rax, rax
    jz .oom
    mov rbx, rax
    mov rdi, rax
    xor eax, eax
    mov r8, rcx
    mov ecx, Taskbar_size
    rep stosb
    mov [rbx + Taskbar.server], r12
    mov [rbx + Taskbar.output], r14d
    mov [rbx + Taskbar.output_ptr], r8
    mov rax, r8
    mov ecx, [rax + Output.width]
    mov [rbx + Taskbar.width], ecx
    shl ecx, 2
    mov [rbx + Taskbar.stride], ecx
    mov dword [rbx + Taskbar.pointer_x], -1

    mov rdi, r12
    lea rsi, [rbx + Taskbar.pair]
    mov edx, CLIENT_CAP_LAYER | CLIENT_CAP_WINDOWS | CLIENT_CAP_POINTER
    call client_accept_trusted
    test rax, rax
    js .out
    mov [rbx + Taskbar.client_id], rax
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
    test r14d, r14d
    jz .first                           ; new surfaces start on the first
    mov rdi, [rbx + Taskbar.conn]
    mov esi, [rbx + Taskbar.surface]
    mov edx, r14d
    call canvas_layer_set_output
.first:
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
    mov rax, [r12 + Server.taskbar]
    mov [rbx + Taskbar.next], rax
    mov [r12 + Server.taskbar], rbx
    mov rax, rbx
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14
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
    imul ecx, ecx, TaskbarEntry_size
    lea rax, [rbx + Taskbar.entries + rcx]
    mov ecx, [rbx + EV_DATA]
    mov [rax + TaskbarEntry.id], ecx
.update:
    mov r12, rax
    mov ecx, [rbx + EV_DATA + 4]
    mov [r12 + TaskbarEntry.states], ecx
    mov ecx, [rbx + EV_DATA + 8]
    mov [r12 + TaskbarEntry.workspace], ecx
    lea rdi, [r12 + TaskbarEntry.title] ; its title
    lea rsi, [rbx + EV_DATA + 12]
    mov ecx, 64
    rep movsb
    mov byte [r12 + TaskbarEntry.title + 63], 0
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
    imul edx, edx, TaskbarEntry_size
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

; The bar, the blocks of the workspace shown, the workspace squares. In
; high contrast (A11Y-07) the bar is black, a block white with a black
; title, the active one yellow, a minimized one a white outline with a white
; title; the shown square yellow, the others outlines.
; rdi = taskbar
draw:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov rax, [rbx + Taskbar.server]
    mov rax, [rax + Server.high_contrast]
    mov [rel hc], eax
    xor esi, esi
    xor edx, edx
    mov ecx, [rbx + Taskbar.width]
    mov r8d, TASKBAR_H
    mov r9d, TASKBAR_BG
    test eax, eax
    jz .bar
    mov r9d, HC_BLACK
.bar:
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
    cmp dword [rel hc], 0
    jne .hc_square
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
    jmp .square_next
.hc_square:
    mov r9d, HC_YELLOW
    cmp r12d, [rbx + Taskbar.workspace]
    je .square_color
    mov rdi, rbx
    mov edx, TASKBAR_PAD
    mov ecx, TASKBAR_WS_W
    mov r8d, TASKBAR_H - 2 * TASKBAR_PAD
    call outline
.square_next:
    inc r12d
    jmp .square

.blocks:
    xor r12d, r12d                      ; the entry
    xor r14d, r14d                      ; the slot on the bar
.block:
    cmp r12d, [rbx + Taskbar.count]
    jae .out
    mov eax, r12d
    imul eax, eax, TaskbarEntry_size
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
    imul eax, eax, TaskbarEntry_size
    lea rax, [rbx + Taskbar.entries + rax]
    cmp dword [rel hc], 0
    jne .hc_block
    mov dword [rel text_colour], TASKBAR_TEXT
    mov r9d, [rax + TaskbarEntry.color]
    test dword [rax + TaskbarEntry.states], STATE_MINIMIZED
    jz .colored
    mov r9d, TASKBAR_DIM
    jmp .colored
.hc_block:
    test dword [rax + TaskbarEntry.states], STATE_MINIMIZED
    jnz .hc_minimized
    mov dword [rel text_colour], HC_TEXT_DARK
    mov r9d, HC_WHITE
    mov ecx, [rax + TaskbarEntry.id]
    cmp ecx, [rbx + Taskbar.active]
    jne .colored
    mov r9d, HC_YELLOW
    jmp .colored
.hc_minimized:
    mov dword [rel text_colour], HC_TEXT_LIGHT
    mov rdi, rbx
    mov esi, r13d
    mov edx, TASKBAR_PAD
    mov ecx, TASKBAR_ENTRY_W
    mov r8d, TASKBAR_H - 2 * TASKBAR_PAD
    call outline
    jmp .titled
.colored:
    mov rdi, rbx
    mov esi, r13d
    mov edx, TASKBAR_PAD
    mov ecx, TASKBAR_ENTRY_W
    mov r8d, TASKBAR_H - 2 * TASKBAR_PAD
    call fill
.titled:
    mov rdi, rbx
    mov esi, r13d
    mov edx, r12d
    call draw_title
    cmp dword [rel hc], 0
    jne .next                           ; the active one is yellow: no stripe
    mov eax, r12d
    imul eax, eax, TaskbarEntry_size
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

; An entry's title inside its block.
; rdi = taskbar, esi = the block's x, edx = the entry
draw_title:
    push rbx
    sub rsp, UiText_size
    mov rbx, rdi
    imul edx, edx, TaskbarEntry_size
    lea rax, [rbx + Taskbar.entries + rdx + TaskbarEntry.title]
    mov [rsp + UiText.text], rax
    xor ecx, ecx                        ; its length
.length:
    cmp byte [rax + rcx], 0
    je .counted
    inc ecx
    cmp ecx, 63
    jb .length
.counted:
    mov [rsp + UiText.length], ecx
    mov rax, [rbx + Taskbar.pixels]
    mov [rsp + UiText.pixels], rax
    mov eax, [rbx + Taskbar.stride]
    mov [rsp + UiText.stride], rax
    add esi, TASKBAR_TEXT_PAD
    mov [rsp + UiText.x], esi
    mov [rsp + UiText.clip_x], esi
    mov dword [rsp + UiText.y], TASKBAR_PAD
    mov dword [rsp + UiText.clip_y], TASKBAR_PAD
    mov dword [rsp + UiText.width], TASKBAR_ENTRY_W - 2 * TASKBAR_TEXT_PAD
    mov dword [rsp + UiText.clip_w], TASKBAR_ENTRY_W - 2 * TASKBAR_TEXT_PAD
    mov dword [rsp + UiText.height], TASKBAR_H - 2 * TASKBAR_PAD
    mov dword [rsp + UiText.clip_h], TASKBAR_H - 2 * TASKBAR_PAD
    mov dword [rsp + UiText.size], TASKBAR_TEXT_SIZE
    mov eax, [rel text_colour]
    mov [rsp + UiText.colour], eax
    mov rdi, rsp
    call ui_text_draw                   ; no font: a plain block
    add rsp, UiText_size
    pop rbx
    ret

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

; A white edge round black, two pixels wide (high contrast).
; rdi = taskbar, esi = x, edx = y, ecx = width, r8d = height
outline:
    push rbx
    push r12
    push r13
    push r14
    push r15                            ; 16-byte aligned
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    mov r9d, HC_WHITE
    call fill
    mov rdi, rbx
    lea esi, [r12 + HC_EDGE]
    lea edx, [r13 + HC_EDGE]
    lea ecx, [r14 - 2 * HC_EDGE]
    lea r8d, [r15 - 2 * HC_EDGE]
    mov r9d, HC_BLACK
    call fill
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
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

section .bss
hc:             resd 1                  ; 1: drawing in high contrast
text_colour:    resd 1                  ; a block's title, as drawn now

section .rodata
palette:        dd 0xFF4C78A8, 0xFFF58518, 0xFF54A24B, 0xFFE45756
                dd 0xFF72B7B2, 0xFFB279A2, 0xFFFF9DA6, 0xFF9D755D

section .data
global taskbar_version
taskbar_version: dq 0x010000
