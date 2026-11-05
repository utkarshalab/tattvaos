; ============================================================================
; Unit Test — Windows (src/shell/window.asm, proto/canvas-shell.cwp)
; ============================================================================
; test_window_suite -> eax = failed cases (each case returns 0 / 1).
; A server on 64x48 and one client with the shell capability (and the layer
; one where layers are made). The cases send cw_toplevel, cw_popup and
; cw_layer requests, inject input for the shortcuts, and read the events and
; the server's own records.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"
%include "inc/color.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/event.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_init
extern client_accept_trusted
extern handle_resolve
extern msgbuf_read
extern msgbuf_write
extern server_init
extern server_poll
extern virtual_input_inject
extern window_activate

%define HEAP_SIZE (2 * 1024 * 1024)

%define OP_CREATE   0
%define OP_DESTROY  1
%define OP_ATTACH   2
%define OP_DAMAGE   3
%define OP_COMMIT   12

; cw_toplevel
%define TL_CREATE       0
%define TL_DESTROY      1
%define TL_SET_TITLE    2
%define TL_SET_APP_ID   3
%define TL_ACK          4
%define TL_SET_MAX      5
%define TL_UNSET_MAX    6
%define TL_SET_FULL     7
%define TL_UNSET_FULL   8
%define TL_SET_MIN      9
%define TL_SET_DECO     10
%define TL_CONFIGURE    0
%define TL_CLOSE        1
%define PU_CREATE       0
%define PU_DONE         0
%define LY_CREATE       0
%define LY_DESTROY      1
%define LY_EXCLUSIVE    2
%define LY_CONFIGURE    0
%define WL_SUBSCRIBE    0
%define WL_ACTIVATE     1
%define WL_CLOSE        2
%define WL_MINIMIZE     3
%define WL_MAXIMIZE     4
%define WL_WINDOW       0
%define WL_REMOVED      1
%define WL_ACTIVATED    2
%define WL_WORKSPACE    3
%define WL_SET_WS       5

section .text

global test_window_suite
test_window_suite:
    push rbx
    xor ebx, ebx
%macro CASE 2
    mov edi, %2
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tw_configure, CAP_SHELL
    CASE tw_place, CAP_SHELL
    CASE tw_names, CAP_SHELL
    CASE tw_list, CAP_SHELL
    CASE tw_needs_cap, 0
    CASE tw_popup, CAP_SHELL
    CASE tw_layers, CAP_SHELL | CAP_LAYER
    CASE tw_alt_f4, CAP_SHELL
    CASE tw_alt_drag, CAP_SHELL
    CASE tw_alt_resize, CAP_SHELL
    CASE tw_popup_follows, CAP_SHELL
    CASE tw_popup_dismiss, CAP_SHELL
    CASE tw_maximize, CAP_SHELL
    CASE tw_fullscreen, CAP_SHELL | CAP_LAYER
    CASE tw_minimize, CAP_SHELL
    CASE tw_state_keys, CAP_SHELL
    CASE tw_exclusive, CAP_SHELL | CAP_LAYER
    CASE tw_window_list, CAP_SHELL | CAP_WINDOWS
    CASE tw_list_needs_cap, CAP_SHELL
    CASE tw_workspaces, CAP_SHELL
    CASE tw_list_workspace, CAP_SHELL | CAP_WINDOWS
    CASE tw_titlebar, CAP_SHELL
    CASE tw_titlebar_drag, CAP_SHELL
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

; send interface, opcode, the first %3 bytes of [req]
%macro SEND 3
    mov dword [rel hdr + MsgHdr.obj], %1
    mov word [rel hdr + MsgHdr.opcode], %2
    mov word [rel hdr + MsgHdr.flags], 0
    mov dword [rel hdr + MsgHdr.len], %3
    call send
%endmacro

; a cw_toplevel request about the surface in %2 with one more dword
%macro TOPLEVEL 3
    mov eax, [rel %2]
    mov [rel req], eax
    mov dword [rel req + 4], %3
    SEND CWP_OBJ_TOPLEVEL, %1, 8
%endmacro

; inject type, code, value
%macro INJECT 3
    lea rdi, [rel server]
    mov esi, %1
    mov edx, %2
    mov ecx, %3
    xor r8d, r8d
    call virtual_input_inject
%endmacro

; the next event of interface %1, event %2 into hdr / ans; .fail if none
%macro FIND 2
    mov edi, %1
    mov esi, %2
    call find_event
    test eax, eax
    jz .fail
%endmacro

; the pointer to x, y
%macro POINTER 2
    lea rdi, [rel server]
    mov esi, INPUT_POSITION
    mov edx, %1
    mov ecx, %2
    xor r8d, r8d
    call virtual_input_inject
%endmacro

; edi = capabilities: a started server and a trusted client asking for them
fresh:
    push rbx
    mov ebx, edi
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    mov edx, 64
    mov ecx, 48
    xor r8d, r8d
    call server_init
    lea rdi, [rel server]
    lea rsi, [rel pair]
    mov edx, ebx
    call client_accept_trusted          ; it gets only what it asks for
    call drain
    pop rbx
    ret

; edi x esi: a buffer, then a surface -> eax = the surface, [buffer] the buffer
new_surface:
    sub rsp, 8
    mov [rel req], edi
    mov [rel req + 4], esi
    mov dword [rel req + 8], DRM_FORMAT_BGRA8888
    mov dword [rel req + 12], 0
    mov qword [rel req + 16], 0
    SEND CWP_OBJ_BUFFER, OP_CREATE, 24
    call poll
    call next_reply
    mov eax, [rel ans]
    mov [rel buffer], eax
    SEND CWP_OBJ_SURFACE, OP_CREATE, 0
    call poll
    call next_reply
    mov eax, [rel ans]
    add rsp, 8
    ret

; edi = surface, esi = buffer, edx, ecx = the x, y attach asks for: shown
show:
    sub rsp, 8
    mov [rel req], edi
    mov [rel req + 4], esi
    mov [rel req + 8], edx
    mov [rel req + 12], ecx
    mov qword [rel req + 16], 0
    SEND CWP_OBJ_SURFACE, OP_ATTACH, 24
    mov dword [rel req + 4], 0
    mov dword [rel req + 8], 0
    mov dword [rel req + 12], 8
    mov dword [rel req + 16], 8
    SEND CWP_OBJ_SURFACE, OP_DAMAGE, 20
    mov dword [rel req + 4], 0
    SEND CWP_OBJ_SURFACE, OP_COMMIT, 8
    call poll
    add rsp, 8
    ret

; edi = surface handle -> rax = Surface*
surface_of:
    sub rsp, 8
    mov esi, edi
    mov rdi, [rel server + Server.surface_table]
    call handle_resolve
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

poll:
    sub rsp, 8
    lea rdi, [rel server]
    call server_poll
    add rsp, 8
    ret

; the next message for the client into hdr / ans -> rax = payload length
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

; the next cw_toplevel event -> rax = payload length, negative if none
next_toplevel:
    sub rsp, 8
.next:
    call next_event
    test rax, rax
    js .done
    cmp dword [rel hdr + MsgHdr.obj], CWP_OBJ_TOPLEVEL
    jne .next
.done:
    add rsp, 8
    ret

; edi = interface, esi = event -> eax = 1 with it in hdr / ans, 0 if none
find_event:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
.next:
    call next_event
    test rax, rax
    js .none
    test word [rel hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jnz .next
    cmp [rel hdr + MsgHdr.obj], ebx
    jne .next
    movzx eax, word [rel hdr + MsgHdr.opcode]
    cmp eax, r12d
    jne .next
    mov eax, 1
    jmp .out
.none:
    xor eax, eax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi = interface -> eax = 1 if any event of it was waiting; reads them all
any_event:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    xor r12d, r12d
.next:
    call next_event
    test rax, rax
    js .out
    cmp [rel hdr + MsgHdr.obj], ebx
    jne .next
    mov r12d, 1
    jmp .next
.out:
    mov eax, r12d
    add rsp, 8
    pop r12
    pop rbx
    ret

; edi x esi, shown as a window -> eax = the surface
new_window:
    push rbx
    call new_surface
    mov ebx, eax
    mov [rel req], eax
    SEND CWP_OBJ_TOPLEVEL, TL_CREATE, 4
    mov edi, ebx
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    mov eax, ebx
    pop rbx
    ret

drain:
    sub rsp, 8
.next:
    call next_event
    test rax, rax
    jns .next
    add rsp, 8
    ret

; ---------------------------------------------------------------------------
; Cases
; ---------------------------------------------------------------------------

; create answers with configure(surface, 1, 0, 0, 0); an ack of a serial never
; sent is refused, one sent is kept
tw_configure:
    sub rsp, 8
    mov edi, 8
    mov esi, 8
    call new_surface
    mov [rel surface_a], eax
    TOPLEVEL TL_CREATE, surface_a, 0
    call poll
    call next_toplevel
    cmp rax, 20
    jne .fail
    cmp word [rel hdr + MsgHdr.opcode], TL_CONFIGURE
    jne .fail
    mov eax, [rel surface_a]
    cmp [rel ans], eax
    jne .fail
    cmp dword [rel ans + 4], 1
    jne .fail
    cmp qword [rel ans + 8], 0
    jne .fail
    cmp dword [rel ans + 16], 0
    jne .fail
    TOPLEVEL TL_ACK, surface_a, 5
    TOPLEVEL TL_ACK, surface_a, 1
    call poll
    mov edi, [rel surface_a]
    call surface_of
    mov rax, [rax + Surface.window]
    test rax, rax
    jz .fail
    cmp dword [rax + Window.acked], 1
    jne .fail
    TOPLEVEL TL_CREATE, surface_a, 0    ; one is enough
    call poll
    call next_toplevel
    test rax, rax
    jns .fail
    PASS

; Placed at the pointer, back inside the output; attach's x, y ignored then
; and after
tw_place:
    sub rsp, 8
    POINTER 40, 30
    mov edi, 16
    mov esi, 12
    call new_surface
    mov [rel surface_a], eax
    TOPLEVEL TL_CREATE, surface_a, 0
    mov edi, [rel surface_a]
    mov esi, [rel buffer]
    mov edx, 3
    mov ecx, 3
    call show
    mov edi, [rel surface_a]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 40
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 30
    jne .fail
    POINTER 60, 46                      ; too near the corner for 32x24
    mov edi, 32
    mov esi, 24
    call new_surface
    mov [rel surface_b], eax
    TOPLEVEL TL_CREATE, surface_b, 0
    mov edi, [rel surface_b]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    mov edi, [rel surface_b]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 32
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 24
    jne .fail
    mov edi, [rel surface_a]            ; a later commit keeps its place
    call surface_of
    mov rax, [rax + Surface.current + SurfaceState.buffer]
    mov edi, [rel surface_a]
    mov esi, eax
    xor edx, edx
    xor ecx, ecx
    call show
    mov edi, [rel surface_a]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 40
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 30
    jne .fail
    PASS

; Title and app id kept; one too long is refused and changes nothing
tw_names:
    sub rsp, 8
    mov edi, 8
    mov esi, 8
    call new_surface
    mov [rel surface_a], eax
    TOPLEVEL TL_CREATE, surface_a, 0
    mov dword [rel req + 4], 5
    mov dword [rel req + 8], 'File'
    mov byte [rel req + 12], 's'
    SEND CWP_OBJ_TOPLEVEL, TL_SET_TITLE, 13
    mov dword [rel req + 4], 3
    mov dword [rel req + 8], 'fm'
    mov byte [rel req + 10], 'x'
    SEND CWP_OBJ_TOPLEVEL, TL_SET_APP_ID, 11
    mov dword [rel req + 4], WINDOW_NAME_MAX + 1
    SEND CWP_OBJ_TOPLEVEL, TL_SET_TITLE, 8 + WINDOW_NAME_MAX + 1
    mov dword [rel req + 4], 40         ; longer than what was sent
    SEND CWP_OBJ_TOPLEVEL, TL_SET_TITLE, 12
    call poll
    mov edi, [rel surface_a]
    call surface_of
    mov rax, [rax + Surface.window]
    test rax, rax
    jz .fail
    cmp dword [rax + Window.title_len], 5
    jne .fail
    cmp dword [rax + Window.title], 'File'
    jne .fail
    cmp word [rax + Window.title + 4], 's'
    jne .fail
    cmp dword [rax + Window.app_id_len], 3
    jne .fail
    cmp dword [rax + Window.app_id], 'fmx'
    jne .fail
    PASS

; Newest first on Server.windows; destroy takes the role off, and so does
; destroying the surface
tw_list:
    sub rsp, 8
    mov edi, 8
    mov esi, 8
    call new_surface
    mov [rel surface_a], eax
    mov edi, 8
    mov esi, 8
    call new_surface
    mov [rel surface_b], eax
    TOPLEVEL TL_CREATE, surface_a, 0
    TOPLEVEL TL_CREATE, surface_b, 0
    call poll
    mov edi, [rel surface_b]
    call surface_of
    mov rcx, [rel server + Server.windows]
    cmp rcx, [rax + Surface.window]
    jne .fail
    mov rcx, [rcx + Window.next]
    test rcx, rcx
    jz .fail
    cmp qword [rcx + Window.next], 0
    jne .fail
    TOPLEVEL TL_DESTROY, surface_b, 0
    call poll
    mov edi, [rel surface_b]
    call surface_of
    cmp qword [rax + Surface.window], 0
    jne .fail
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.windows]
    cmp rcx, [rax + Surface.window]
    jne .fail
    cmp qword [rcx + Window.next], 0
    jne .fail
    mov eax, [rel surface_a]
    mov [rel req], eax
    SEND CWP_OBJ_SURFACE, OP_DESTROY, 4
    call poll
    cmp qword [rel server + Server.windows], 0
    jne .fail
    PASS

; Without the shell capability there are no windows
tw_needs_cap:
    sub rsp, 8
    mov edi, 8
    mov esi, 8
    call new_surface
    mov [rel surface_a], eax
    TOPLEVEL TL_CREATE, surface_a, 0
    call poll
    mov edi, [rel surface_a]
    call surface_of
    cmp qword [rax + Surface.window], 0
    jne .fail
    cmp qword [rel server + Server.windows], 0
    jne .fail
    PASS

; A popup sits at its offset on its parent, above it; when the parent goes
; it is done and loses its role
tw_popup:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    mov edi, 8
    mov esi, 8
    call new_surface
    mov [rel surface_b], eax
    mov [rel req], eax
    mov eax, [rel surface_a]
    mov [rel req + 4], eax
    mov dword [rel req + 8], 4
    mov dword [rel req + 12], 2
    SEND CWP_OBJ_POPUP, PU_CREATE, 16
    mov edi, [rel surface_b]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    mov edi, [rel surface_b]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 14
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 12
    jne .fail
    cmp qword [rax + Surface.z_order_next], 0
    jne .fail                           ; on top
    call drain
    mov eax, [rel surface_a]
    mov [rel req], eax
    SEND CWP_OBJ_SURFACE, OP_DESTROY, 4
    call poll
    FIND CWP_OBJ_POPUP, PU_DONE
    mov eax, [rel surface_b]
    cmp [rel ans], eax
    jne .fail
    mov edi, [rel surface_b]
    call surface_of
    cmp qword [rax + Surface.window], 0
    jne .fail
    PASS

; Layers: a background told the output's size and kept at the bottom, below
; a window shown after it, and never given the keyboard; a top layer against
; its edges and above a window raised after it
tw_layers:
    sub rsp, 8
    mov edi, 64
    mov esi, 48
    call new_surface
    mov [rel surface_a], eax
    mov [rel req], eax
    mov dword [rel req + 4], 0          ; background
    mov dword [rel req + 8], 15         ; every edge
    mov dword [rel req + 12], 0
    SEND CWP_OBJ_LAYER, LY_CREATE, 16
    call poll
    FIND CWP_OBJ_LAYER, LY_CONFIGURE
    cmp dword [rel ans + 8], 64
    jne .fail
    cmp dword [rel ans + 12], 48
    jne .fail
    mov edi, [rel surface_a]
    mov esi, [rel buffer]
    mov edx, 5                          ; ignored
    mov ecx, 5
    call show
    mov edi, [rel surface_a]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 0
    jne .fail
    mov rcx, [rel server + Server.input_seat]
    cmp qword [rcx + InputSeat.keyboard_focus], 0
    jne .fail                           ; a background takes no keyboard

    POINTER 0, 0
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_b], eax
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.outputs]
    cmp [rcx + Output.surfaces], rax
    jne .fail                           ; the background stays the bottom
    POINTER 40, 40                      ; on the background only
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
    mov edi, [rel surface_b]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail                           ; the window keeps it

    mov edi, 60
    mov esi, 8
    call new_surface
    mov [rel surface_a], eax
    mov [rel req], eax
    mov dword [rel req + 4], 2          ; top
    mov dword [rel req + 8], 2 | 4 | 8  ; bottom, left, right
    mov dword [rel req + 12], 2
    SEND CWP_OBJ_LAYER, LY_CREATE, 16
    mov edi, [rel surface_a]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    mov edi, [rel surface_a]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 2
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 38
    jne .fail
    POINTER 4, 4                        ; the window, raised by a click
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
    mov edi, [rel surface_a]
    call surface_of
    cmp qword [rax + Surface.z_order_next], 0
    jne .fail                           ; the top layer is still on top
    PASS

; Alt+F4 asks the focused window to close
tw_alt_f4:
    sub rsp, 8
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    INJECT INPUT_KEY, 56, 1             ; Alt
    INJECT INPUT_KEY, 62, 1             ; F4
    INJECT INPUT_KEY, 62, 0
    INJECT INPUT_KEY, 56, 0
    call poll
    FIND CWP_OBJ_TOPLEVEL, TL_CLOSE
    mov eax, [rel surface_a]
    cmp [rel ans], eax
    jne .fail
    PASS

; Alt+drag moves the window by the pointer's travel; its client sees no
; pointer event of it
tw_alt_drag:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    INJECT INPUT_KEY, 56, 1
    POINTER 12, 12
    call poll
    call drain
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_POSITION, 30, 20
    INJECT INPUT_BUTTON, 0, 0
    call poll
    mov edi, CWP_OBJ_POINTER
    call any_event
    test eax, eax
    jnz .fail
    mov edi, [rel surface_a]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 28
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 18
    jne .fail
    mov rax, [rel server + Server.input_seat]
    cmp qword [rax + InputSeat.moving], 0
    jne .fail
    PASS

; Alt+right-drag asks for the window's size plus the pointer's travel; its
; client sees no button of it
tw_alt_resize:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    INJECT INPUT_KEY, 56, 1
    POINTER 12, 12
    call poll
    call drain
    INJECT INPUT_BUTTON, 1, 1
    INJECT INPUT_POSITION, 30, 22
    INJECT INPUT_BUTTON, 1, 0
    call poll
    FIND CWP_OBJ_TOPLEVEL, TL_CONFIGURE
    mov eax, [rel surface_a]
    cmp [rel ans], eax
    jne .fail
    cmp dword [rel ans + 8], 16 + 18
    jne .fail
    cmp dword [rel ans + 12], 12 + 10
    jne .fail
    mov edi, CWP_OBJ_POINTER            ; no button; the pointer may leave,
    mov esi, 3                          ; the client not having grown yet
    call find_event
    test eax, eax
    jnz .fail
    mov edi, [rel surface_a]            ; it did not move
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 10
    jne .fail
    PASS

; a popup 8x8 at (4, 2) on surface_a -> surface_b
popup_on_a:
    sub rsp, 8
    mov edi, 8
    mov esi, 8
    call new_surface
    mov [rel surface_b], eax
    mov [rel req], eax
    mov eax, [rel surface_a]
    mov [rel req + 4], eax
    mov dword [rel req + 8], 4
    mov dword [rel req + 12], 2
    SEND CWP_OBJ_POPUP, PU_CREATE, 16
    mov edi, [rel surface_b]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    add rsp, 8
    ret

; A popup goes along when its window is moved
tw_popup_follows:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call popup_on_a
    INJECT INPUT_KEY, 56, 1
    POINTER 12, 12
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_POSITION, 30, 20
    INJECT INPUT_BUTTON, 0, 0
    call poll
    mov edi, [rel surface_b]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 28 + 4
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 18 + 2
    jne .fail
    PASS

; A press on the popup keeps it; one anywhere else ends it
tw_popup_dismiss:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call popup_on_a
    call drain
    POINTER 16, 14                      ; on the popup
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
    mov edi, CWP_OBJ_POPUP
    call any_event
    test eax, eax
    jnz .fail
    POINTER 60, 40                      ; on nothing
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
    FIND CWP_OBJ_POPUP, PU_DONE
    mov eax, [rel surface_b]
    cmp [rel ans], eax
    jne .fail
    mov edi, [rel surface_b]
    call surface_of
    cmp qword [rax + Surface.window], 0
    jne .fail
    PASS

; the next configure is width %1, height %2, states %3
%macro CONFIGURED 3
    FIND CWP_OBJ_TOPLEVEL, TL_CONFIGURE
    cmp dword [rel ans + 8], %1
    jne .fail
    cmp dword [rel ans + 12], %2
    jne .fail
    cmp dword [rel ans + 16], %3
    jne .fail
%endmacro

; surface_a is at x, y
%macro AT 2
    mov edi, [rel surface_a]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], %1
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], %2
    jne .fail
%endmacro

; a 16x12 window at (10, 10) -> surface_a, every event so far read
window_at_10:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    add rsp, 8
    ret

; Maximized it fills the output and is told so; unset it goes back to its
; place and is asked for its old size
tw_maximize:
    sub rsp, 8
    call window_at_10
    TOPLEVEL TL_SET_MAX, surface_a, 0
    call poll
    CONFIGURED 64, 48, 1
    AT 0, 0
    TOPLEVEL TL_SET_MAX, surface_a, 0   ; again: nothing new
    call poll
    call next_toplevel
    test rax, rax
    jns .fail
    TOPLEVEL TL_UNSET_MAX, surface_a, 0
    call poll
    CONFIGURED 16, 12, 0
    AT 10, 10
    PASS

; Fullscreen fills the output above a top layer; unset it goes back under
tw_fullscreen:
    sub rsp, 8
    mov edi, 64
    mov esi, 8
    call new_surface
    mov [rel surface_b], eax
    mov [rel req], eax
    mov dword [rel req + 4], 2          ; top
    mov dword [rel req + 8], 1 | 4 | 8  ; top, left, right
    mov dword [rel req + 12], 0
    SEND CWP_OBJ_LAYER, LY_CREATE, 16
    mov edi, [rel surface_b]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    call window_at_10
    TOPLEVEL TL_SET_FULL, surface_a, 0
    call poll
    CONFIGURED 64, 48, 2
    AT 0, 0
    mov edi, [rel surface_a]
    call surface_of
    cmp qword [rax + Surface.z_order_next], 0
    jne .fail                           ; above the panel
    TOPLEVEL TL_UNSET_FULL, surface_a, 0
    call poll
    CONFIGURED 16, 12, 0
    mov edi, [rel surface_b]
    call surface_of
    cmp qword [rax + Surface.z_order_next], 0
    jne .fail                           ; the panel above it again
    PASS

; Minimized it leaves the output and the keyboard; activated it is back,
; on top, with the keyboard
tw_minimize:
    sub rsp, 8
    call window_at_10
    TOPLEVEL TL_SET_MIN, surface_a, 0
    call poll
    mov edi, [rel surface_a]
    call surface_of
    cmp qword [rax + Surface.output], 0
    jne .fail
    mov rcx, [rel server + Server.input_seat]
    cmp qword [rcx + InputSeat.keyboard_focus], 0
    jne .fail
    mov rcx, [rel server + Server.outputs]
    cmp qword [rcx + Output.surfaces], 0
    jne .fail
    mov edi, [rel surface_a]
    call surface_of
    lea rdi, [rel server]
    mov rsi, rax
    call window_activate
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.outputs]
    cmp [rcx + Output.surfaces], rax
    jne .fail
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail
    AT 10, 10
    PASS

; Super+Up maximizes and puts back, Super+Down minimizes; the client sees
; neither arrow
tw_state_keys:
    sub rsp, 8
    call window_at_10
    INJECT INPUT_KEY, 125, 1            ; Super
    INJECT INPUT_KEY, 103, 1            ; Up
    INJECT INPUT_KEY, 103, 0
    call poll
    CONFIGURED 64, 48, 1
    INJECT INPUT_KEY, 103, 1
    INJECT INPUT_KEY, 103, 0
    call poll
    CONFIGURED 16, 12, 0
    call drain
    INJECT INPUT_KEY, 108, 1            ; Down
    INJECT INPUT_KEY, 108, 0
    INJECT INPUT_KEY, 125, 0
    call poll
    mov edi, [rel surface_a]
    call surface_of
    cmp qword [rax + Surface.output], 0
    jne .fail
    PASS

; a cw_window_list request about window 1 with one more dword
%macro LIST 2
    mov dword [rel req], 1
    mov dword [rel req + 4], %2
    SEND CWP_OBJ_WINDOW_LIST, %1, 8
%endmacro

; A panel's exclusive strip is kept from a maximized window; when the
; panel goes the window fills the output again
tw_exclusive:
    sub rsp, 8
    mov edi, 64
    mov esi, 8
    call new_surface
    mov [rel surface_b], eax
    mov [rel req], eax
    mov dword [rel req + 4], 2          ; top
    mov dword [rel req + 8], 1 | 4 | 8  ; top, left, right
    mov dword [rel req + 12], 0
    SEND CWP_OBJ_LAYER, LY_CREATE, 16
    mov eax, [rel surface_b]
    mov [rel req], eax
    mov dword [rel req + 4], 8
    SEND CWP_OBJ_LAYER, LY_EXCLUSIVE, 8
    mov edi, [rel surface_b]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    call window_at_10
    TOPLEVEL TL_SET_MAX, surface_a, 0
    call poll
    CONFIGURED 64, 40, 1
    AT 0, 8
    mov eax, [rel surface_b]
    mov [rel req], eax
    SEND CWP_OBJ_LAYER, LY_DESTROY, 4
    call poll
    CONFIGURED 64, 48, 1
    AT 0, 0
    PASS

; The window list: every window on subscribing, then names, states, the
; keyboard, and control by id
tw_window_list:
    sub rsp, 8
    call window_at_10
    SEND CWP_OBJ_WINDOW_LIST, WL_SUBSCRIBE, 0
    call poll
    FIND CWP_OBJ_WINDOW_LIST, WL_WINDOW
    cmp dword [rel ans], 1
    jne .fail
    cmp dword [rel ans + 4], 0
    jne .fail
    FIND CWP_OBJ_WINDOW_LIST, WL_ACTIVATED
    cmp dword [rel ans], 1
    jne .fail

    mov eax, [rel surface_a]            ; a title it hears of
    mov [rel req], eax
    mov dword [rel req + 4], 2
    mov word [rel req + 8], 'Ed'
    SEND CWP_OBJ_TOPLEVEL, TL_SET_TITLE, 10
    call poll
    FIND CWP_OBJ_WINDOW_LIST, WL_WINDOW
    cmp dword [rel ans + 12], 'Ed'      ; and the NUL after
    jne .fail

    LIST WL_MINIMIZE, 0
    call poll
    FIND CWP_OBJ_WINDOW_LIST, WL_WINDOW
    cmp dword [rel ans + 4], 4
    jne .fail
    mov edi, [rel surface_a]
    call surface_of
    cmp qword [rax + Surface.output], 0
    jne .fail

    LIST WL_ACTIVATE, 0
    call poll
    FIND CWP_OBJ_WINDOW_LIST, WL_WINDOW
    cmp dword [rel ans + 4], 0
    jne .fail
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail

    LIST WL_MAXIMIZE, 1
    call poll
    CONFIGURED 64, 48, 1
    LIST WL_CLOSE, 0
    call poll
    FIND CWP_OBJ_TOPLEVEL, TL_CLOSE
    mov eax, [rel surface_a]
    cmp [rel ans], eax
    jne .fail

    mov eax, [rel surface_a]
    mov [rel req], eax
    SEND CWP_OBJ_SURFACE, OP_DESTROY, 4
    call poll
    FIND CWP_OBJ_WINDOW_LIST, WL_REMOVED
    cmp dword [rel ans], 1
    jne .fail
    PASS

; Without the windows capability there is no list
tw_list_needs_cap:
    sub rsp, 8
    call window_at_10
    SEND CWP_OBJ_WINDOW_LIST, WL_SUBSCRIBE, 0
    call poll
    mov edi, CWP_OBJ_WINDOW_LIST
    call any_event
    test eax, eax
    jnz .fail
    cmp qword [rel server + Server.window_lists], 0
    jne .fail
    PASS

; Super+key %1, pressed and let go, with Super held already
%macro SUPER_KEY 1
    INJECT INPUT_KEY, %1, 1
    INJECT INPUT_KEY, %1, 0
    call poll
%endmacro

; surface in %1 is on the output (%2 = 1) or off it (0)
%macro SHOWN 2
    mov edi, [rel %1]
    call surface_of
    xor ecx, ecx
    cmp qword [rax + Surface.output], 0
    setne cl
    cmp ecx, %2
    jne .fail
%endmacro

; Super+2 shows workspace 1, without A; a window made there stays there;
; Super+1 brings A back with the keyboard; Super+Shift+2 sends A to 1
tw_workspaces:
    sub rsp, 8
    call window_at_10
    INJECT INPUT_KEY, 125, 1            ; Super
    SUPER_KEY 3                         ; 2
    cmp qword [rel server + Server.workspace], 1
    jne .fail
    SHOWN surface_a, 0
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_b], eax
    SUPER_KEY 2                         ; 1
    SHOWN surface_a, 1
    SHOWN surface_b, 0
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail
    INJECT INPUT_KEY, 42, 1             ; Shift
    SUPER_KEY 3
    INJECT INPUT_KEY, 42, 0
    SHOWN surface_a, 0                  ; gone to 1, 0 still shown
    cmp qword [rel server + Server.workspace], 0
    jne .fail
    SUPER_KEY 3
    SHOWN surface_a, 1
    SHOWN surface_b, 1
    INJECT INPUT_KEY, 125, 0
    PASS

; The window list says which workspace is shown and each window's, and
; shows another on request
tw_list_workspace:
    sub rsp, 8
    call window_at_10
    SEND CWP_OBJ_WINDOW_LIST, WL_SUBSCRIBE, 0
    call poll
    FIND CWP_OBJ_WINDOW_LIST, WL_WINDOW
    cmp dword [rel ans + 8], 0          ; its workspace
    jne .fail
    FIND CWP_OBJ_WINDOW_LIST, WL_WORKSPACE
    cmp dword [rel ans], 0
    jne .fail
    cmp dword [rel ans + 4], 4
    jne .fail
    mov dword [rel req], 2
    SEND CWP_OBJ_WINDOW_LIST, WL_SET_WS, 4
    call poll
    FIND CWP_OBJ_WINDOW_LIST, WL_WORKSPACE
    cmp dword [rel ans], 2
    jne .fail
    SHOWN surface_a, 0
    PASS

; a press and release at x, y, then a turn
%macro CLICK_AT 2
    POINTER %1, %2
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
%endmacro

; edi = x, esi = y -> eax = the output's pixel there, as composited
screen_pixel:
    mov rax, [rel server + Server.outputs]
    mov rcx, [rax + Output.stride]
    imul rsi, rcx
    mov rax, [rax + Output.framebuffer]
    add rax, rsi
    mov eax, [rax + rdi * 4]
    ret

; a 64x20 window with a title bar, at the top-left corner -> surface_a
decorated_window:
    sub rsp, 8
    POINTER 0, 0
    mov edi, 64
    mov esi, 20
    call new_surface
    mov [rel surface_a], eax
    TOPLEVEL TL_CREATE, surface_a, 0
    TOPLEVEL TL_SET_DECO, surface_a, 1
    mov edi, [rel surface_a]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    call drain
    add rsp, 8
    ret

; The bar goes above the window, inside the output; its buttons maximize
; and put back (the bar's room kept), close, minimize; the client sees none
; of the clicks
tw_titlebar:
    sub rsp, 8
    call decorated_window
    AT 0, TITLEBAR_H
    mov edi, 2                          ; drawn: the bar, the close button
    mov esi, 2
    call screen_pixel
    cmp eax, 0xFF2C3248
    jne .fail
    mov edi, 64 - 12
    mov esi, 10
    call screen_pixel
    cmp eax, 0xFFC04848
    jne .fail
    CLICK_AT 30, 10                     ; maximize: 24 to 40 across
    CONFIGURED 64, 48 - TITLEBAR_H, 1
    AT 0, TITLEBAR_H
    CLICK_AT 30, 10
    CONFIGURED 64, 20, 0
    CLICK_AT 50, 10                     ; close: 44 to 60
    FIND CWP_OBJ_TOPLEVEL, TL_CLOSE
    mov edi, CWP_OBJ_POINTER
    call any_event
    test eax, eax
    jnz .fail
    CLICK_AT 10, 10                     ; minimize: 4 to 20
    mov edi, [rel surface_a]
    call surface_of
    cmp qword [rax + Surface.output], 0
    jne .fail
    PASS

; Dragging the bar moves the window
tw_titlebar_drag:
    sub rsp, 8
    call decorated_window
    POINTER 62, 5                       ; on the bar, past the buttons
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_POSITION, 62, 15
    INJECT INPUT_BUTTON, 0, 0
    call poll
    AT 0, TITLEBAR_H + 10
    mov edi, CWP_OBJ_POINTER
    call any_event
    test eax, eax
    jnz .fail
    PASS

section .bss
alignb 16
server:         resb Server_size
arena:          resb Arena_size
pair:           resb ChannelPair_size
hdr:            resb MsgHdr_size
surface_a:      resd 1
surface_b:      resd 1
buffer:         resd 1
alignb 16
req:            resb 128
ans:            resb 256
alignb 16
heap:           resb HEAP_SIZE
