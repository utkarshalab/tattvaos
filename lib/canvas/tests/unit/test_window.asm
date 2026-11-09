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
%include "inc/cwp_ops.inc"
%include "inc/channel.inc"
%include "inc/event.inc"
%include "inc/backend.inc"
%include "inc/render.inc"
%include "inc/struct_offsets.inc"
%include "ugfx.inc"

extern arena_init
extern client_accept_trusted
extern handle_resolve
extern msgbuf_read
extern msgbuf_write
extern server_init
extern server_poll
extern virtual_input_inject
extern window_activate
extern switcher_selected
extern server_add_output
extern window_move
extern server_mirror_output
extern scale_nearest_rect
extern scale_bilinear_rect
extern displays_start
extern scale_fractional_compute
extern output_set_scale
extern magnify_focus
extern window_move_to_workspace
extern server_set_pointer
extern server_set_button_map
extern server_set_pen_curve
extern compositor_output_at
extern scale_fractional_calculate_dest
extern scale_fractional_render
extern displays_step
extern displays_event
extern client_accept
extern client_disconnect
extern clipboard_set
extern input_set_sticky
extern server_set_magnifier
extern server_remove_output
extern compositor_output_at
extern compositor_damage_all

%define HEAP_SIZE (2 * 1024 * 1024)

%define OP_CREATE   0
%define OP_DESTROY  1
%define OP_ATTACH   2
%define OP_DAMAGE   3
%define OP_COMMIT   12

; cw_toplevel
%define TL_CREATE       0
%define RG_CREATE       0
%define RG_ADD          2
%define SF_SET_OPAQUE   5
%define NO_INPUT        (1 << 31)       ; fresh: a client asking for no input
%define FN_CREATE       0
%define FN_SIGNAL       2
%define FN_STATUS       5
%define TL_NEW          0               ; cw_timeline
%define TL_DESTROY      1
%define TL_SIGNAL       2
%define TL_POINT        4
%define BUF_TIMELINE    4               ; cw_buffer.set_timeline
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
    CASE tw_titlebar_focus, CAP_SHELL
    CASE tw_alt_tab, CAP_SHELL
    CASE tw_occlusion, CAP_SHELL
    CASE tw_fences, CAP_SHELL
    CASE tw_timelines, CAP_SHELL
    CASE tw_two_outputs, CAP_SHELL
    CASE tw_locked, CAP_SHELL
    CASE tw_alt_tab_output, CAP_SHELL
    CASE tw_no_input, CAP_SHELL | NO_INPUT
    CASE tw_mirror, CAP_SHELL
    CASE tw_scale_rect, CAP_SHELL
    CASE tw_scale_bilinear, CAP_SHELL
    CASE tw_displays, CAP_SHELL
    CASE tw_scale_fractional, CAP_SHELL
    CASE tw_cursor, CAP_SHELL
    CASE tw_cursor_shapes, CAP_SHELL
    CASE tw_clipboard, CAP_SHELL | CAP_CLIPBOARD
    CASE tw_dnd, CAP_SHELL | CAP_CLIPBOARD | CAP_DATA
    CASE tw_sticky, CAP_SHELL
    CASE tw_outputs, CAP_SHELL | CAP_OUTPUT
    CASE tw_buffer_scale, CAP_SHELL
    CASE tw_contrast, CAP_SHELL
    CASE tw_touch, CAP_SHELL
    CASE tw_pen, CAP_SHELL
    CASE tw_seat, CAP_SHELL | CAP_SEAT
    CASE tw_clamshell, CAP_SHELL
    CASE tw_logical, CAP_SHELL | CAP_OUTPUT
    CASE tw_pixels, CAP_SHELL
    CASE tw_pixel_parts, CAP_SHELL
    CASE tw_snap, CAP_SHELL
    CASE tw_wake, CAP_SHELL
    CASE tw_foreign_objects, CAP_SHELL | CAP_SURFACE | CAP_BUFFER
    CASE tw_size_limits, CAP_SHELL
    CASE tw_transient, CAP_SHELL
    CASE tw_modal, CAP_SHELL
    CASE tw_attention, CAP_SHELL
    CASE tw_focus_steal, CAP_SHELL
    CASE tw_scroll, CAP_SHELL | CAP_SESSION
    CASE tw_buttons, CAP_SHELL
    CASE tw_relative, CAP_SHELL
    CASE tw_magnify_focus, CAP_SHELL
    CASE tw_pad, CAP_SHELL
    CASE tw_pen_curve, CAP_SHELL
    CASE tw_gestures, CAP_SHELL
    CASE tw_workspace_swipe, CAP_SHELL
    CASE tw_magnifier, CAP_SHELL
    CASE tw_overlay_refused, CAP_SHELL | CAP_LAYER
    CASE tw_overlay, CAP_SHELL | CAP_LAYER | CAP_OVERLAY
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

; edi = capabilities: a started server and a trusted client asking for them,
; and for pointer, keyboard and touch input unless NO_INPUT is among them
fresh:
    push rbx
    mov ebx, edi
    btr ebx, 31
    jc .asked
    or ebx, CAP_POINTER | CAP_KEYBOARD | CAP_TOUCH | CAP_TABLET
.asked:
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
    mov [rel client_a], rax
    lea rax, [rel pair]                 ; the one the helpers talk through
    mov [rel cur_pair], rax
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
    mov rdi, [rel cur_pair]             ; the client talking
    mov rdi, [rdi + ChannelPair.client_to_server]
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
    mov rdi, [rel cur_pair]
    mov rdi, [rdi + ChannelPair.server_to_client]
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
    cmp [rel server + Server.stack], rax
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
    cmp qword [rel server + Server.stack], 0
    jne .fail
    mov edi, [rel surface_a]
    call surface_of
    lea rdi, [rel server]
    mov rsi, rax
    call window_activate
    mov edi, [rel surface_a]
    call surface_of
    cmp [rel server + Server.stack], rax
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
    mov edi, 2                          ; drawn: the bar, bright with the
    mov esi, 2                          ; keyboard; the close button
    call screen_pixel
    cmp eax, 0xFF3E4C78
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

; The bar goes dim when another window takes the keyboard, bright again
; when it comes back
tw_titlebar_focus:
    sub rsp, 8
    call decorated_window
    POINTER 40, 40                      ; another window, clear of the bar
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_b], eax
    mov edi, 2
    mov esi, 2
    call screen_pixel
    cmp eax, 0xFF2C3248
    jne .fail
    CLICK_AT 30, 30                     ; on A's own pixels
    mov edi, 2
    mov esi, 2
    call screen_pixel
    cmp eax, 0xFF3E4C78
    jne .fail
    PASS

; the keyboard is on the surface in variable %1
%macro FOCUSED 1
    mov edi, [rel %1]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail
%endmacro

; Alt+Tab: the one before the current, then the one before that; letting
; go of Alt activates it; the order is the latest to have the keyboard
; first; Esc gives up. The switch is drawn over everything.
tw_alt_tab:
    sub rsp, 8
    POINTER 0, 0
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    POINTER 20, 0
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_b], eax
    POINTER 40, 0
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_c], eax            ; C, B, A from the latest
    INJECT INPUT_KEY, 56, 1             ; Alt
    INJECT INPUT_KEY, 15, 1             ; Tab
    INJECT INPUT_KEY, 15, 0
    call poll
    call switcher_selected
    mov [rel picked], rax
    mov edi, [rel surface_b]
    call surface_of
    cmp [rel picked], rax
    jne .fail
    mov edi, 32                         ; the selected tile, over the windows
    mov esi, 24
    call screen_pixel
    cmp eax, 0xFF3E4C78
    jne .fail
    INJECT INPUT_KEY, 15, 1
    INJECT INPUT_KEY, 15, 0
    INJECT INPUT_KEY, 56, 0             ; Alt let go: A
    call poll
    FOCUSED surface_a
    call switcher_selected
    test rax, rax
    jnz .fail                           ; the switch is over
    INJECT INPUT_KEY, 56, 1             ; A, C, B now: one Tab is C
    INJECT INPUT_KEY, 15, 1
    INJECT INPUT_KEY, 15, 0
    INJECT INPUT_KEY, 56, 0
    call poll
    FOCUSED surface_c
    INJECT INPUT_KEY, 56, 1             ; Esc: nothing changes
    INJECT INPUT_KEY, 15, 1
    INJECT INPUT_KEY, 15, 0
    INJECT INPUT_KEY, 1, 1
    INJECT INPUT_KEY, 1, 0
    INJECT INPUT_KEY, 56, 0
    call poll
    FOCUSED surface_c
    PASS

; -> rax = surfaces the compositor has drawn so far
drawn:
    mov rax, [rel server + Server.compositor]
    mov rax, [rax + Compositor.drawn]
    ret

; edi = surface handle, esi = region handle (0: none): its opaque region,
; then a commit
set_opaque:
    sub rsp, 8
    mov [rel req], edi
    mov [rel req + 4], esi
    SEND CWP_OBJ_SURFACE, SF_SET_OPAQUE, 8
    mov dword [rel req + 4], 0
    SEND CWP_OBJ_SURFACE, OP_COMMIT, 8
    call poll
    add rsp, 8
    ret

; A redraw under a window opaque over all of it draws only that window;
; without its opaque region, what is under it is drawn too
tw_occlusion:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    mov eax, [rel buffer]
    mov [rel buffer_a], eax
    POINTER 0, 0                        ; B over all of A
    mov edi, 32
    mov esi, 24
    call new_window
    mov [rel surface_b], eax
    SEND CWP_OBJ_REGION, RG_CREATE, 0
    call poll
    call next_reply
    mov eax, [rel ans]
    mov [rel req], eax
    mov dword [rel req + 4], 0
    mov dword [rel req + 8], 0
    mov dword [rel req + 12], 32
    mov dword [rel req + 16], 24
    mov [rel region_h], eax
    SEND CWP_OBJ_REGION, RG_ADD, 20
    mov edi, [rel surface_b]
    mov esi, [rel region_h]
    call set_opaque
    call drain

    call drawn
    mov [rel picked], rax
    mov edi, [rel surface_a]            ; A damaged under B
    mov esi, [rel buffer_a]
    xor edx, edx
    xor ecx, ecx
    call show
    call drawn
    sub rax, [rel picked]
    cmp rax, 1
    jne .fail                           ; B only

    mov edi, [rel surface_b]
    xor esi, esi                        ; no opaque region any more
    call set_opaque
    call drawn
    mov [rel picked], rax
    mov edi, [rel surface_a]
    mov esi, [rel buffer_a]
    xor edx, edx
    xor ecx, ecx
    call show
    call drawn
    sub rax, [rel picked]
    cmp rax, 2
    jne .fail                           ; A, and B over it
    PASS

; -> eax = a new fence's handle
new_fence:
    sub rsp, 8
    mov dword [rel req], 0
    SEND CWP_OBJ_FENCE, FN_CREATE, 4
    call poll
    call next_reply
    mov eax, [rel ans]
    add rsp, 8
    ret

; edi = surface, esi = buffer, edx = acquire fence, ecx = release fence:
; attached at 0, 0, damaged, committed, a turn
attach_fenced:
    sub rsp, 8
    mov [rel req], edi
    mov [rel req + 4], esi
    mov qword [rel req + 8], 0
    mov [rel req + 16], edx
    mov [rel req + 20], ecx
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

; surface_a shows buffer variable %1 (0: none)
%macro SHOWS 1
    mov edi, [rel surface_a]
    call surface_of
    mov ecx, [rel %1]
    cmp [rax + Surface.current + SurfaceState.buffer], rcx
    jne .fail
%endmacro

; edi = timeline, rsi = point: it reaches the point, a turn
timeline_to:
    sub rsp, 8
    mov [rel req], edi
    mov dword [rel req + 4], 0
    mov [rel req + 8], rsi
    SEND CWP_OBJ_TIMELINE, TL_SIGNAL, 16
    call poll
    add rsp, 8
    ret

; -> rax = the timeline's point
timeline_point:
    sub rsp, 8
    call drain
    mov eax, [rel timeline]
    mov [rel req], eax
    SEND CWP_OBJ_TIMELINE, TL_POINT, 4
    call poll
    call next_reply
    mov rax, [rel ans]
    add rsp, 8
    ret

; edi = buffer, esi = timeline, rdx = acquire point, rcx = release point
set_timeline:
    sub rsp, 8
    mov [rel req], edi
    mov [rel req + 4], esi
    mov [rel req + 8], rdx
    mov [rel req + 16], rcx
    SEND CWP_OBJ_BUFFER, BUF_TIMELINE, 24
    call poll
    add rsp, 8
    ret

; A buffer with a timeline is shown once the timeline reaches its acquire
; point; the timeline never goes back; it reaches the release point when
; another buffer replaces it; a timeline not the client's is refused; one
; destroyed lets what waited on it go on
tw_timelines:
    sub rsp, 8
    mov dword [rel zero], 0
    SEND CWP_OBJ_TIMELINE, TL_NEW, 0
    call poll
    call next_reply
    mov eax, [rel ans]
    test eax, eax
    jz .fail
    mov [rel timeline], eax
    mov edi, 8
    mov esi, 8
    call new_surface
    mov [rel surface_a], eax
    mov eax, [rel buffer]
    mov [rel buffer_a], eax
    mov edi, [rel buffer_a]
    mov esi, [rel timeline]
    mov edx, 5
    mov ecx, 7
    call set_timeline
    mov edi, [rel surface_a]
    mov esi, [rel buffer_a]
    xor edx, edx
    xor ecx, ecx
    call attach_fenced
    SHOWS zero                          ; at 0: not shown
    mov edi, [rel timeline]
    mov esi, 3
    call timeline_to
    SHOWS zero                          ; at 3: still not
    FIND CWP_OBJ_TIMELINE, TIMELINE_EV_TIMELINE_SIGNALED
    cmp qword [rel ans + 8], 3          ; said so, with the point
    jne .fail
    mov edi, [rel timeline]
    mov esi, 5
    call timeline_to
    SHOWS buffer_a                      ; at 5: shown
    FIND CWP_OBJ_TIMELINE, TIMELINE_EV_TIMELINE_SIGNALED
    cmp qword [rel ans + 8], 5
    jne .fail
    mov edi, [rel timeline]             ; never back, and nothing said
    mov esi, 4
    call timeline_to
    mov edi, CWP_OBJ_TIMELINE
    mov esi, TIMELINE_EV_TIMELINE_SIGNALED
    call find_event
    test eax, eax
    jnz .fail
    call timeline_point
    cmp rax, 5
    jne .fail

    mov edi, 8                          ; another buffer: the first let go
    mov esi, 8
    call new_surface
    mov eax, [rel buffer]
    mov [rel buffer_b], eax
    mov edi, [rel surface_a]
    mov esi, [rel buffer_b]
    xor edx, edx
    xor ecx, ecx
    call attach_fenced
    SHOWS buffer_b
    FIND CWP_OBJ_TIMELINE, TIMELINE_EV_TIMELINE_SIGNALED
    cmp qword [rel ans + 8], 7
    jne .fail
    call timeline_point
    cmp rax, 7                          ; its release point
    jne .fail

    mov edi, [rel buffer_a]             ; no timeline of its: refused
    mov esi, 999
    mov edx, 100
    xor ecx, ecx
    call set_timeline
    mov rdi, [rel server + Server.buffer_table]
    mov esi, [rel buffer_a]
    call handle_resolve
    mov ecx, [rel timeline]
    cmp [rax + Buffer.timeline], rcx
    jne .fail
    cmp qword [rax + Buffer.acquire_point], 5
    jne .fail

    mov edi, [rel buffer_a]             ; waits for 100: destroyed, it goes on
    mov esi, [rel timeline]
    mov edx, 100
    xor ecx, ecx
    call set_timeline
    mov edi, [rel surface_a]
    mov esi, [rel buffer_a]
    xor edx, edx
    xor ecx, ecx
    call attach_fenced
    SHOWS buffer_b
    mov eax, [rel timeline]
    mov [rel req], eax
    SEND CWP_OBJ_TIMELINE, TL_DESTROY, 4
    call poll
    SHOWS buffer_a
    PASS

; A buffer is shown only once its acquire fence is signaled; its release
; fence is signaled when another replaces it; a fence not the client's is
; refused
tw_fences:
    sub rsp, 8
    mov dword [rel zero], 0
    call new_fence
    mov [rel fence_a], eax
    call new_fence
    mov [rel fence_r], eax
    mov edi, 8
    mov esi, 8
    call new_surface
    mov [rel surface_a], eax
    mov eax, [rel buffer]
    mov [rel buffer_a], eax
    mov edi, [rel surface_a]
    mov esi, [rel buffer_a]
    mov edx, [rel fence_a]
    mov ecx, [rel fence_r]
    call attach_fenced
    SHOWS zero                          ; its pixels not done: not shown
    call poll
    SHOWS zero
    mov eax, [rel fence_a]
    mov [rel req], eax
    SEND CWP_OBJ_FENCE, FN_SIGNAL, 4
    call poll
    SHOWS buffer_a                      ; signaled: shown
    FIND CWP_OBJ_FENCE, FENCE_EV_FENCE_SIGNALED
    mov eax, [rel fence_a]
    cmp [rel ans], eax
    jne .fail                           ; and said so

    mov edi, 8                          ; another buffer: the first let go
    mov esi, 8
    call new_surface                    ; (a surface too; only its buffer used)
    mov eax, [rel buffer]
    mov [rel buffer_b], eax
    mov edi, [rel surface_a]
    mov esi, [rel buffer_b]
    xor edx, edx
    xor ecx, ecx
    call attach_fenced
    SHOWS buffer_b
    FIND CWP_OBJ_FENCE, FENCE_EV_FENCE_SIGNALED
    mov eax, [rel fence_r]
    cmp [rel ans], eax
    jne .fail                           ; the release fence: said so
    call drain
    mov eax, [rel fence_r]
    mov [rel req], eax
    SEND CWP_OBJ_FENCE, FN_STATUS, 4
    call poll
    call next_reply
    cmp dword [rel ans], 1
    jne .fail                           ; the release fence signaled

    mov edi, [rel surface_a]            ; a fence that is no fence of its
    mov esi, [rel buffer_a]
    mov edx, 999
    xor ecx, ecx
    call attach_fenced
    SHOWS buffer_b                      ; refused: nothing changed
    PASS

; edi = x, esi = y in the second output -> eax = its pixel there
second_pixel:
    mov rax, [rel output_b]
    mov rcx, [rax + Output.stride]
    imul rsi, rcx
    mov rax, [rax + Output.framebuffer]
    add rax, rsi
    mov eax, [rax + rdi * 4]
    ret

; A second output to the right: the pointer goes onto it, a window placed
; there is on it and gets the pointer there, Alt+drag takes the window back
; to the first, and a title bar placed there is drawn in its pixels
tw_two_outputs:
    sub rsp, 8
    lea rdi, [rel server]
    mov esi, 64
    mov edx, 48
    call server_add_output
    test rax, rax
    jz .fail
    mov [rel output_b], rax
    cmp dword [rax + Output.x], 64
    jne .fail
    POINTER 500, 10                     ; past both: the layout's right edge
    call poll
    mov rax, [rel server + Server.input_seat]
    cmp dword [rax + InputSeat.x], 127
    jne .fail

    POINTER 80, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel output_b]
    cmp [rax + Surface.output], rcx
    jne .fail
    AT 80, 10
    call drain
    POINTER 85, 15                      ; the pointer finds it there
    call poll
    FIND CWP_OBJ_POINTER, 0
    mov eax, [rel surface_a]
    cmp [rel ans + 8], eax
    jne .fail

    INJECT INPUT_KEY, 56, 1             ; Alt+drag A onto the first output
    POINTER 85, 15
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_POSITION, 15, 15
    INJECT INPUT_BUTTON, 0, 0
    INJECT INPUT_KEY, 56, 0
    call poll
    AT 10, 10
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.outputs]
    cmp [rax + Surface.output], rcx
    jne .fail
    POINTER 70, 0                       ; a decorated one: its bar in the
    mov edi, 32                         ; second output's own pixels
    mov esi, 12
    call new_surface
    mov [rel surface_b], eax
    TOPLEVEL TL_CREATE, surface_b, 0
    TOPLEVEL TL_SET_DECO, surface_b, 1
    mov edi, [rel surface_b]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    mov edi, 70 - 64 + 2
    mov esi, 2
    call second_pixel
    cmp eax, 0xFF3E4C78
    jne .fail
    mov edi, 70 - 64 + 2                ; and not in the first's
    mov esi, 2
    call screen_pixel
    cmp eax, 0xFF3E4C78
    je .fail

    mov edi, [rel surface_b]            ; over the edge at 64: drawn on both
    call surface_of
    lea rdi, [rel server]
    mov rsi, rax
    mov edx, 50
    mov ecx, TITLEBAR_H
    call window_move
    call poll
    mov edi, 56                         ; its bar's left part, on the first
    mov esi, 2
    call screen_pixel
    cmp eax, 0xFF3E4C78
    jne .fail
    mov edi, 74 - 64                    ; its right part, on the second
    mov esi, 2
    call second_pixel
    cmp eax, 0xFF3E4C78
    jne .fail
    mov edi, 94 - 64                    ; where it was, there: redrawn
    mov esi, 2
    call second_pixel
    cmp eax, 0xFF3E4C78
    je .fail
    PASS

; surface_a asks to be an overlay layer, a turn -> rax = its Window, 0: none
overlay_a:
    sub rsp, 8
    mov edi, 16
    mov esi, 16
    call new_surface
    mov [rel surface_a], eax
    mov [rel req], eax
    mov dword [rel req + 4], 3          ; overlay
    mov dword [rel req + 8], 15         ; every edge
    mov dword [rel req + 12], 0
    SEND CWP_OBJ_LAYER, LY_CREATE, 16
    call poll
    mov edi, [rel surface_a]
    call surface_of
    mov rax, [rax + Surface.window]
    add rsp, 8
    ret

; An overlay layer without CAP_OVERLAY is refused: the surface has no role
tw_overlay_refused:
    sub rsp, 8
    call overlay_a
    test rax, rax
    jnz .fail
    PASS

; With CAP_OVERLAY it is one, over everything
tw_overlay:
    sub rsp, 8
    call overlay_a
    test rax, rax
    jz .fail
    cmp dword [rax + Window.level], LEVEL_OVERLAY
    jne .fail
    PASS

; Alt+Tab with the pointer on the second output: the box is drawn there,
; centred, and not on the first; Esc takes it away
tw_alt_tab_output:
    sub rsp, 8
    lea rdi, [rel server]
    mov esi, 64
    mov edx, 48
    call server_add_output
    test rax, rax
    jz .fail
    mov [rel output_b], rax
    POINTER 0, 0
    mov edi, 16
    mov esi, 12
    call new_window
    POINTER 20, 0
    mov edi, 16
    mov esi, 12
    call new_window
    POINTER 40, 0
    mov edi, 16
    mov esi, 12
    call new_window
    POINTER 90, 10                      ; onto the second
    call poll
    INJECT INPUT_KEY, 56, 1             ; Alt
    INJECT INPUT_KEY, 15, 1             ; Tab
    INJECT INPUT_KEY, 15, 0
    call poll
    mov edi, 32                         ; the selected tile, at its centre
    mov esi, 24
    call second_pixel
    cmp eax, 0xFF3E4C78
    jne .fail
    mov edi, 32                         ; nothing at the first's
    mov esi, 24
    call screen_pixel
    cmp eax, 0xFF3E4C78
    je .fail
    INJECT INPUT_KEY, 1, 1              ; Esc: given up, gone
    INJECT INPUT_KEY, 1, 0
    INJECT INPUT_KEY, 56, 0
    call poll
    mov edi, 32
    mov esi, 24
    call second_pixel
    cmp eax, 0xFF3E4C78
    je .fail
    PASS

; A client that did not ask for input: its window does not take the
; keyboard, and the pointer over it sends it nothing
tw_no_input:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    mov rax, [rel server + Server.input_seat]
    cmp qword [rax + InputSeat.keyboard_focus], 0
    jne .fail
    call drain
    POINTER 15, 15
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
    mov rax, [rel server + Server.input_seat]
    cmp qword [rax + InputSeat.keyboard_focus], 0
    jne .fail                           ; not by a click either
    mov edi, CWP_OBJ_POINTER
    mov esi, POINTER_EV_ENTER
    call find_event
    test eax, eax
    jnz .fail
    PASS

; A second output, wider, mirroring the first: where the first is, the same pixels
; (a title bar in both), no part of the layout (the pointer kept on the
; first, a point found on the first); itself or a mirror it cannot show;
; mirroring no more, it is to the right again, its own part
tw_mirror:
    sub rsp, 8
    lea rdi, [rel server]
    mov esi, 96                         ; wider than the first
    mov edx, 48
    call server_add_output
    test rax, rax
    jz .fail
    mov [rel output_b], rax
    call decorated_window               ; a bar along the first's top
    POINTER 100, 10                     ; on the second
    call poll
    lea rdi, [rel server]
    mov rsi, [rel output_b]
    mov rdx, [rel server + Server.outputs]
    call server_mirror_output
    test rax, rax
    jnz .fail
    call poll
    mov rax, [rel output_b]
    cmp dword [rax + Output.x], 0
    jne .fail
    mov edi, 4                          ; the bar in both
    mov esi, 2
    call screen_pixel
    mov [rel region_h], eax
    cmp eax, 0xFF3E4C78
    jne .fail
    mov edi, 4
    mov esi, 2
    call second_pixel
    cmp eax, [rel region_h]
    jne .fail
    mov edi, 90                         ; scaled: the bar's right end, from
    mov esi, 2                          ; 60 of the first's 64
    call second_pixel
    cmp eax, [rel region_h]
    jne .fail
    mov rax, [rel server + Server.input_seat]
    cmp dword [rax + InputSeat.x], 64
    jge .fail                           ; kept on the first
    lea rdi, [rel server]
    mov esi, 10
    mov edx, 10
    call compositor_output_at
    cmp rax, [rel server + Server.outputs]
    jne .fail
    lea rdi, [rel server]               ; past the first, under the mirror
    mov esi, 80
    mov edx, 10
    call compositor_output_at
    cmp rax, [rel server + Server.outputs]
    jne .fail
    lea rdi, [rel server]               ; not itself, not a mirror
    mov rsi, [rel output_b]
    mov rdx, rsi
    call server_mirror_output
    cmp rax, -(EINVAL)
    jne .fail
    lea rdi, [rel server]
    mov rsi, [rel server + Server.outputs]
    mov rdx, [rel output_b]
    call server_mirror_output
    cmp rax, -(EINVAL)
    jne .fail

    lea rdi, [rel server]               ; its own part again
    mov rsi, [rel output_b]
    xor edx, edx
    call server_mirror_output
    test rax, rax
    jnz .fail
    call poll
    mov rax, [rel output_b]
    cmp dword [rax + Output.x], 64
    jne .fail
    mov edi, 4
    mov esi, 2
    call second_pixel
    cmp eax, 0xFF3E4C78
    je .fail
    PASS

; scale_nearest_rect: a 2x2 image over 4x4, all of it, then one rectangle
; only
%macro SCALED 3                         ; x, y, the pixel expected there
    mov eax, [rel scale_dst + ((%2) * 4 + (%1)) * 4]
    cmp eax, %3
    jne .fail
%endmacro
tw_scale_rect:
    sub rsp, 8
    lea rax, [rel scale_dst]
    mov [rel scale_job + UgfxScale_dst], rax
    mov qword [rel scale_job + UgfxScale_dst_stride], 16
    mov dword [rel scale_job + UgfxScale_dst_w], 4
    mov dword [rel scale_job + UgfxScale_dst_h], 4
    lea rax, [rel scale_src]
    mov [rel scale_job + UgfxScale_src], rax
    mov qword [rel scale_job + UgfxScale_src_stride], 8
    mov dword [rel scale_job + UgfxScale_src_w], 2
    mov dword [rel scale_job + UgfxScale_src_h], 2
    mov dword [rel scale_job + UgfxScale_x], 0
    mov dword [rel scale_job + UgfxScale_y], 0
    mov dword [rel scale_job + UgfxScale_w], 4
    mov dword [rel scale_job + UgfxScale_h], 4
    lea rdi, [rel scale_job]
    call scale_nearest_rect
    SCALED 0, 0, 1
    SCALED 1, 0, 1
    SCALED 2, 0, 2
    SCALED 3, 1, 2
    SCALED 0, 2, 3
    SCALED 3, 3, 4
    lea rdi, [rel scale_dst]            ; again, a rectangle only
    xor eax, eax
    mov ecx, 16
    rep stosd
    mov dword [rel scale_job + UgfxScale_x], 2
    mov dword [rel scale_job + UgfxScale_y], 1
    mov dword [rel scale_job + UgfxScale_w], 2
    mov dword [rel scale_job + UgfxScale_h], 2
    lea rdi, [rel scale_job]
    call scale_nearest_rect
    SCALED 2, 1, 2
    SCALED 3, 2, 4
    SCALED 0, 0, 0                      ; outside it: untouched
    SCALED 1, 1, 0
    SCALED 2, 3, 0
    PASS

; scale_bilinear_rect: black and white, 2x1 over 4x1, centres matched:
; black, a quarter white, three quarters, white; the same size, a copy;
; 2x2 with only the bottom left white, over 4x4: (1, 1) blends both rows
tw_scale_bilinear:
    sub rsp, 8
    lea rax, [rel scale_dst]
    mov [rel scale_job + UgfxScale_dst], rax
    mov qword [rel scale_job + UgfxScale_dst_stride], 16
    mov dword [rel scale_job + UgfxScale_dst_w], 4
    mov dword [rel scale_job + UgfxScale_dst_h], 1
    lea rax, [rel blend_src]
    mov [rel scale_job + UgfxScale_src], rax
    mov qword [rel scale_job + UgfxScale_src_stride], 8
    mov dword [rel scale_job + UgfxScale_src_w], 2
    mov dword [rel scale_job + UgfxScale_src_h], 1
    mov dword [rel scale_job + UgfxScale_x], 0
    mov dword [rel scale_job + UgfxScale_y], 0
    mov dword [rel scale_job + UgfxScale_w], 4
    mov dword [rel scale_job + UgfxScale_h], 1
    lea rdi, [rel scale_job]
    call scale_bilinear_rect
    SCALED 0, 0, 0xFF000000
    SCALED 1, 0, 0xFF3F3F3F
    SCALED 2, 0, 0xFFBFBFBF
    SCALED 3, 0, 0xFFFFFFFF
    mov dword [rel scale_job + UgfxScale_dst_w], 2  ; the same size
    mov dword [rel scale_job + UgfxScale_w], 2
    lea rdi, [rel scale_dst]
    xor eax, eax
    mov ecx, 16
    rep stosd
    lea rdi, [rel scale_job]
    call scale_bilinear_rect
    SCALED 0, 0, 0xFF000000
    SCALED 1, 0, 0xFFFFFFFF
    SCALED 2, 0, 0                      ; past it: untouched
    mov dword [rel scale_job + UgfxScale_dst_w], 4
    mov dword [rel scale_job + UgfxScale_dst_h], 4
    mov dword [rel scale_job + UgfxScale_w], 4
    mov dword [rel scale_job + UgfxScale_h], 4
    lea rax, [rel corner_src]
    mov [rel scale_job + UgfxScale_src], rax
    mov dword [rel scale_job + UgfxScale_src_h], 2
    lea rdi, [rel scale_job]
    call scale_bilinear_rect
    SCALED 1, 1, 0xFF2F2F2F             ; a quarter of three quarters white
    SCALED 0, 3, 0xFFFFFFFF
    SCALED 3, 0, 0xFF000000
    PASS

; The fractional scale helpers: 3/2 as 16.16, 64x48 times it, and a 2x2
; buffer stretched over the 64x48 output, nearest at 2.0 (each quarter one
; pixel) and bilinear at 1.5 (its corners held)
%macro OUT_PIXEL 3                      ; x, y, the pixel there
    mov rax, [rel server + Server.outputs]
    mov rcx, [rax + Output.framebuffer]
    mov eax, [rcx + ((%2) * 64 + (%1)) * 4]
    cmp eax, %3
    jne .fail
%endmacro
tw_scale_fractional:
    sub rsp, 8
    mov rdi, [rel server + Server.outputs]
    mov esi, 3
    mov edx, 2
    call scale_fractional_compute
    test rax, rax
    jnz .fail
    mov rax, [rel server + Server.outputs]
    cmp qword [rax + Output.scale], 0x18000
    jne .fail
    cmp dword [rax + Output.width], 43  ; applied: 64 / 1.5, rounded
    jne .fail
    lea rdi, [rel server]               ; 1 again, for the stretch: its
    mov rsi, [rel server + Server.outputs]  ; frame the pixels
    mov edx, 120
    call output_set_scale
    test rax, rax
    jnz .fail
    mov rax, [rel server + Server.outputs]
    cmp dword [rax + Output.width], 64
    jne .fail
    cmp qword [rax + Output.pixel_fb], 0
    jne .fail
    mov edi, 64
    mov esi, 48
    mov edx, 0x18000
    lea rcx, [rel scaled_size]
    call scale_fractional_calculate_dest
    cmp dword [rel scaled_size], 96
    jne .fail
    cmp dword [rel scaled_size + 4], 72
    jne .fail

    mov edi, 2                          ; a 2x2 buffer of four colours
    mov esi, 2
    call new_surface
    mov [rel surface_a], eax
    mov rdi, [rel server + Server.buffer_table]
    mov esi, [rel buffer]
    call handle_resolve
    mov rcx, [rax + Buffer.base]
    mov rdx, [rax + Buffer.stride]
    mov dword [rcx], 0xFF000011
    mov dword [rcx + 4], 0xFF000022
    mov dword [rcx + rdx], 0xFF000033
    mov dword [rcx + rdx + 4], 0xFF000044
    mov edi, [rel surface_a]            ; its buffer as the current one
    call surface_of
    mov ecx, [rel buffer]
    mov [rax + Surface.current + SurfaceState.buffer], rcx
    mov [rel picked], rax
    mov rax, [rel server + Server.outputs]
    mov [rel fr_ctx + FrameCtx.output], rax
    mov qword [rax + Output.scale], 0x20000
    lea rdi, [rel fr_ctx]
    mov rsi, [rel picked]
    xor edx, edx
    call scale_fractional_render
    OUT_PIXEL 0, 0, 0xFF000011
    OUT_PIXEL 40, 0, 0xFF000022
    OUT_PIXEL 0, 30, 0xFF000033
    OUT_PIXEL 63, 47, 0xFF000044
    mov rax, [rel server + Server.outputs]
    mov qword [rax + Output.scale], 0x18000
    lea rdi, [rel fr_ctx]
    mov rsi, [rel picked]
    xor edx, edx                        ; nearest asked, bilinear given
    call scale_fractional_render
    OUT_PIXEL 0, 0, 0xFF000011
    OUT_PIXEL 63, 47, 0xFF000044
    OUT_PIXEL 32, 0, 0xFF000019         ; between the top two, 132/256 on
    PASS

; The software cursor, on: its tip and fill at the pointer; moved, it is
; gone from where it was and drawn where it is; a modifier leaves it, a
; letter typed hides it, a move shows it again; over the edge of a second
; output, part on each
%macro SEES 3                           ; x, y on the first output, pixel
    mov edi, %1
    mov esi, %2
    call screen_pixel
    cmp eax, %3
    jne .fail
%endmacro
tw_cursor:
    sub rsp, 8
    mov rax, [rel server + Server.compositor]
    mov qword [rax + Compositor.cursor_on], 1
    POINTER 20, 20
    call poll
    SEES 20, 20, 0xFF000000             ; the tip
    SEES 21, 22, 0xFFFFFFFF             ; the fill
    POINTER 40, 30
    call poll
    SEES 21, 22, 0xFF202030             ; the background again
    SEES 41, 32, 0xFFFFFFFF
    INJECT INPUT_KEY, 42, 1             ; Shift, a modifier: still there
    INJECT INPUT_KEY, 42, 0
    call poll
    SEES 41, 32, 0xFFFFFFFF
    INJECT INPUT_KEY, 30, 1             ; a letter, typed: gone
    INJECT INPUT_KEY, 30, 0
    call poll
    SEES 41, 32, 0xFF202030
    POINTER 41, 31                      ; moved: back
    call poll
    SEES 42, 33, 0xFFFFFFFF
    lea rdi, [rel server]               ; over the edge at 64
    mov esi, 64
    mov edx, 48
    call server_add_output
    test rax, rax
    jz .fail
    mov [rel output_b], rax
    POINTER 60, 10
    call poll
    SEES 60, 20, 0xFF000000             ; its tenth row: the outline here,
    mov edi, 65 - 64                    ; the fill on the second
    mov esi, 20
    call second_pixel
    cmp eax, 0xFFFFFFFF
    jne .fail
    PASS

; surface_a's pointer shape to %1, a turn
%macro SHAPE 1
    mov eax, [rel surface_a]
    mov [rel req], eax
    mov dword [rel req + 4], %1
    SEND CWP_OBJ_POINTER, POINTER_SET_SHAPE, 8
    call poll
%endmacro

; A window asks for the text shape: over it, an I-beam, its tip at the
; pointer; at an output scale of 2 the arrow is twice the size; a shape that
; is none is refused
tw_cursor_shapes:
    sub rsp, 8
    mov rax, [rel server + Server.compositor]
    mov qword [rax + Compositor.cursor_on], 1
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    SHAPE 1
    POINTER 16, 18
    call poll
    SEES 16, 18, 0xFFFFFFFF             ; the tip: the I-beam's stem
    SEES 13, 11, 0xFF000000             ; its top left: the outline
    SEES 14, 12, 0xFFFFFFFF             ; its serif
    SHAPE 0                             ; the arrow, at 2x
    mov rax, [rel server + Server.outputs]
    mov qword [rax + Output.scale], 0x20000
    POINTER 16, 17
    call poll
    SEES 17, 19, 0xFF000000             ; the outline's second row
    SHAPE 9                             ; no such shape: refused
    mov edi, [rel surface_a]
    call surface_of
    cmp qword [rax + Surface.cursor_shape], 0
    jne .fail
    PASS

; The helpers talk as client A (pair) or B (pair_b)
%macro AS 1
    lea rax, [rel %1]
    mov [rel cur_pair], rax
%endmacro

; B pastes selection %1 (the clipboard if none given) as text/plain, a turn
%macro PASTE 0-1 0
    mov dword [rel req], %1
    lea rdi, [rel req + 4]
    lea rsi, [rel clip_type]
    mov ecx, CLIP_TYPE_LEN
    rep movsb
    SEND CWP_OBJ_CLIPBOARD, CLIPBOARD_RECEIVE, 4 + CLIP_TYPE_LEN
    call poll
%endmacro

; data(serial in clip_serial, %1 done, %2 = a 4-byte string, its length %3)
%macro ANSWER 3
    mov eax, [rel clip_serial]
    mov [rel req], eax
    mov dword [rel req + 4], %1
    mov dword [rel req + 8], %3
    mov dword [rel req + 12], %2
    SEND CWP_OBJ_CLIPBOARD, CLIPBOARD_DATA, 12 + %3
    call poll
%endmacro

; A copies, B (standard, in the background) cannot paste; B's window takes
; the keyboard and B hears what is offered; B pastes, A is asked and answers
; in two pieces, passed on; A goes during another paste: cancelled, nothing
; offered; the server's own text is pasted at once
tw_clipboard:
    sub rsp, 8
    POINTER 2, 2                        ; A: a window with the keyboard
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    mov dword [rel req], 0              ; A offers text/plain
    mov dword [rel req + 4], 1
    lea rdi, [rel req + 8]
    xor eax, eax
    mov ecx, CLIP_TYPES * CLIP_TYPE_LEN
    rep stosb
    lea rdi, [rel req + 8]
    lea rsi, [rel clip_type]
    mov ecx, CLIP_TYPE_LEN
    rep movsb
    SEND CWP_OBJ_CLIPBOARD, CLIPBOARD_OFFER, 8 + CLIP_TYPES * CLIP_TYPE_LEN
    call poll
    call drain

    lea rdi, [rel server]               ; B, a standard client
    lea rsi, [rel pair_b]
    mov edx, CAP_SHELL | CAP_POINTER | CAP_KEYBOARD | CAP_CLIPBOARD
    call client_accept
    test rax, rax
    js .fail
    AS pair_b
    call drain
    PASTE                               ; without the keyboard: refused
    AS pair
    mov edi, CWP_OBJ_CLIPBOARD
    mov esi, CLIPBOARD_EV_SEND
    call find_event
    test eax, eax
    jnz .fail                           ; A was asked nothing

    AS pair_b                           ; B's window: the keyboard, the offer
    POINTER 40, 2
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_b], eax
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_OFFERED
    cmp dword [rel ans + 4], 1
    jne .fail
    cmp dword [rel ans + 8], 'text'
    jne .fail
    PASTE                               ; B pastes: A is asked
    call next_reply
    mov eax, [rel ans]
    test eax, eax
    jz .fail
    mov [rel clip_serial], eax
    AS pair
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_SEND
    mov eax, [rel clip_serial]
    cmp [rel ans], eax
    jne .fail
    ANSWER 0, 'hell', 4                 ; in two pieces
    ANSWER 1, 'o wo', 4
    AS pair_b
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_DATA
    mov eax, [rel clip_serial]
    cmp [rel ans], eax
    jne .fail
    cmp dword [rel ans + 4], 0
    jne .fail
    cmp dword [rel ans + 12], 'hell'
    jne .fail
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_DATA
    cmp dword [rel ans + 4], 1          ; done
    jne .fail
    cmp dword [rel ans + 8], 4
    jne .fail
    cmp dword [rel ans + 12], 'o wo'
    jne .fail

    PASTE                               ; again; A goes before answering
    call next_reply
    mov eax, [rel ans]
    mov [rel clip_serial], eax
    lea rdi, [rel server]
    mov rsi, [rel client_a]
    call client_disconnect
    call poll
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_OFFERED
    cmp dword [rel ans + 4], 0          ; nothing offered now
    jne .fail
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_CANCELLED
    mov eax, [rel clip_serial]
    cmp [rel ans], eax
    jne .fail

    lea rdi, [rel server]               ; the server's own text
    xor esi, esi
    lea rdx, [rel clip_type]
    mov ecx, 10
    lea r8, [rel clip_remote]
    mov r9d, 6
    call clipboard_set
    test rax, rax
    jnz .fail
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_OFFERED
    cmp dword [rel ans + 4], 1
    jne .fail
    PASTE
    call next_reply
    mov eax, [rel ans]
    mov [rel clip_serial], eax
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_DATA
    mov eax, [rel clip_serial]
    cmp [rel ans], eax
    jne .fail
    cmp dword [rel ans + 4], 1
    jne .fail
    cmp dword [rel ans + 8], 6
    jne .fail
    cmp dword [rel ans + 12], 'remo'
    jne .fail
    PASS

; A starts a drag from surface_a offering text/plain, a turn
%macro DRAG 0
    mov eax, [rel surface_a]
    mov [rel req], eax
    mov dword [rel req + 4], 1
    lea rdi, [rel req + 8]
    xor eax, eax
    mov ecx, CLIP_TYPES * CLIP_TYPE_LEN
    rep stosb
    lea rdi, [rel req + 8]
    lea rsi, [rel clip_type]
    mov ecx, CLIP_TYPE_LEN
    rep movsb
    SEND CWP_OBJ_DND, DND_START, 8 + CLIP_TYPES * CLIP_TYPE_LEN
    call poll
%endmacro

; a cw_dnd request %1 with one value %2, a turn
%macro DND 2
    mov dword [rel req], %2
    SEND CWP_OBJ_DND, %1, 4
    call poll
%endmacro

; Drag and drop between two clients: no button held, no drag; held on A's
; window, A drags, an icon of its own at the pointer; over B's, B hears the
; types, enter (copy offered) and motion in its own pixels; B accepts copy;
; let go, B gets drop (copy) and A finished(1, copy); B, though A has the
; keyboard, pastes the drag's data; over B again, not accepted: B left, A
; finished(0); let go over nothing, finished(0)
tw_dnd:
    sub rsp, 8
    POINTER 2, 2                        ; A's window
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    lea rdi, [rel server]               ; B and its window
    lea rsi, [rel pair_b]
    mov edx, CAP_SHELL | CAP_POINTER | CAP_KEYBOARD | CAP_CLIPBOARD | CAP_DATA
    call client_accept
    test rax, rax
    js .fail
    AS pair_b
    call drain
    POINTER 40, 2
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_b], eax
    call drain
    AS pair
    call drain

    DRAG                                ; no button held: no drag
    POINTER 45, 5
    call poll
    AS pair_b
    mov edi, CWP_OBJ_DND
    mov esi, DND_EV_ENTER
    call find_event
    test eax, eax
    jnz .fail

    POINTER 5, 5                        ; held on A's window: a drag
    call poll
    INJECT INPUT_BUTTON, 0, 1
    call poll
    AS pair
    DRAG
    POINTER 45, 6                       ; over B's
    call poll
    AS pair_b
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_OFFERED
    cmp dword [rel ans], CLIP_DRAG
    jne .fail
    cmp dword [rel ans + 4], 1
    jne .fail
    FIND CWP_OBJ_DND, DND_EV_ENTER
    mov eax, [rel surface_b]
    cmp [rel ans], eax
    jne .fail
    cmp dword [rel ans + 4], 45 - 40
    jne .fail
    cmp dword [rel ans + 8], 6 - 2
    jne .fail
    cmp dword [rel ans + 12], DND_COPY  ; copy offered
    jne .fail
    DND DND_ACCEPT, DND_COPY            ; B takes it
    POINTER 46, 7
    call poll
    FIND CWP_OBJ_DND, DND_EV_MOTION
    cmp dword [rel ans + 4], 46 - 40
    jne .fail
    INJECT INPUT_BUTTON, 0, 0           ; let go: dropped on B's
    call poll
    FIND CWP_OBJ_DND, DND_EV_DROP
    mov eax, [rel surface_b]
    cmp [rel ans], eax
    jne .fail
    cmp dword [rel ans + 12], DND_COPY
    jne .fail
    AS pair
    FIND CWP_OBJ_DND, DND_EV_FINISHED
    cmp dword [rel ans], 1
    jne .fail
    cmp dword [rel ans + 4], DND_COPY
    jne .fail
    call drain

    AS pair_b                           ; B pastes it, as the drop target
    PASTE CLIP_DRAG
    call next_reply
    mov eax, [rel ans]
    test eax, eax
    jz .fail
    mov [rel clip_serial], eax
    AS pair
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_SEND
    mov eax, [rel clip_serial]
    cmp [rel ans], eax
    jne .fail
    ANSWER 1, 'drag', 4
    AS pair_b
    FIND CWP_OBJ_CLIPBOARD, CLIPBOARD_EV_DATA
    cmp dword [rel ans + 12], 'drag'
    jne .fail

    AS pair                             ; over B's, not accepted
    call drain
    POINTER 5, 5
    call poll
    INJECT INPUT_BUTTON, 0, 1
    call poll
    DRAG
    mov edi, 4                          ; with an icon: a red 4x4 of A's
    mov esi, 4
    call new_surface
    mov [rel surface_c], eax
    mov rdi, [rel server + Server.buffer_table]
    mov esi, [rel buffer]
    call handle_resolve
    mov rdi, [rax + Buffer.base]
    mov ecx, 16
    mov eax, 0xFFFF0000
    rep stosd
    mov edi, [rel surface_c]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    mov eax, [rel surface_c]
    DND DND_SET_ICON, eax
    POINTER 44, 5
    call poll
    SEES 44 + DND_ICON_OFFSET, 5 + DND_ICON_OFFSET, 0xFFFF0000
    INJECT INPUT_BUTTON, 0, 0
    call poll
    FIND CWP_OBJ_DND, DND_EV_FINISHED
    cmp dword [rel ans], 0
    jne .fail
    AS pair_b
    FIND CWP_OBJ_DND, DND_EV_LEAVE
    mov eax, [rel surface_b]
    cmp [rel ans], eax
    jne .fail

    AS pair                             ; let go over nothing
    call drain
    POINTER 5, 5
    call poll
    INJECT INPUT_BUTTON, 0, 1
    call poll
    DRAG
    POINTER 30, 40
    call poll
    INJECT INPUT_BUTTON, 0, 0
    call poll
    FIND CWP_OBJ_DND, DND_EV_FINISHED
    cmp dword [rel ans], 0
    jne .fail
    PASS

; a key %1 pressed and let go, a turn
%macro TAP 1
    INJECT INPUT_KEY, %1, 1
    INJECT INPUT_KEY, %1, 0
    call poll
%endmacro
; key %1 tapped types character %2
%macro TYPES 2
    TAP %1
    FIND CWP_OBJ_KEYBOARD, KEYBOARD_EV_TEXT
    cmp dword [rel ans + 12], %2
    jne .fail
%endmacro

; Sticky keys: Shift tapped latches it for one key (A, then b); twice locks
; it (C, D) and a third time it is off (e); five Shift taps turn sticky keys
; off (a tap then latches nothing: f) and on again (G)
tw_sticky:
    sub rsp, 8
    mov edi, 16                         ; a window with the keyboard
    mov esi, 12
    call new_window
    lea rdi, [rel server]
    mov esi, 1
    call input_set_sticky
    test rax, rax
    jnz .fail
    call drain
    TAP 42                              ; Shift, alone: latched
    TYPES 30, 'A'
    TYPES 48, 'b'
    TAP 42                              ; twice: locked
    TAP 42
    TYPES 46, 'C'
    TYPES 32, 'D'
    TAP 42                              ; again: off
    TYPES 18, 'e'
    TAP 42                              ; five in a row: sticky keys off
    TAP 42
    TAP 42
    TAP 42
    TAP 42
    TAP 42
    TYPES 33, 'f'
    TAP 42                              ; and five more: on
    TAP 42
    TAP 42
    TAP 42
    TAP 42
    TAP 42
    TYPES 34, 'G'
    PASS

; the next output event says id %1 (a variable), x %2, scale %3
%macro OUTPUT_IS 3
    FIND CWP_OBJ_OUTPUT, OUTPUT_EV_OUTPUT
    mov eax, [rel %1]
    cmp [rel ans], eax
    jne .fail
    cmp dword [rel ans + 4], %2
    jne .fail
    cmp dword [rel ans + 20], %3
    jne .fail
%endmacro
; the next removed event says id %1
%macro REMOVED_IS 1
    FIND CWP_OBJ_OUTPUT, OUTPUT_EV_REMOVED
    mov eax, [rel %1]
    cmp [rel ans], eax
    jne .fail
%endmacro

; cw_output: list gives the first output (0, 0, 64x48, scale 120), then
; done; then a client hears of one added (at 64, its own id), of its scale
; at 3/2 (180), of it made a mirror (removed) and back (again), and of it
; taken away (removed)
tw_outputs:
    sub rsp, 8
    SEND CWP_OBJ_OUTPUT, OUTPUT_LIST, 0
    call poll
    FIND CWP_OBJ_OUTPUT, OUTPUT_EV_OUTPUT
    mov eax, [rel ans]
    test eax, eax
    jz .fail
    mov [rel output_id_a], eax
    cmp dword [rel ans + 4], 0
    jne .fail
    cmp dword [rel ans + 12], 64
    jne .fail
    cmp dword [rel ans + 16], 48
    jne .fail
    cmp dword [rel ans + 20], 120
    jne .fail
    FIND CWP_OBJ_OUTPUT, OUTPUT_EV_DONE

    lea rdi, [rel server]               ; one added
    mov esi, 64
    mov edx, 48
    call server_add_output
    test rax, rax
    jz .fail
    mov [rel output_b], rax
    FIND CWP_OBJ_OUTPUT, OUTPUT_EV_OUTPUT
    mov eax, [rel ans]
    cmp eax, [rel output_id_a]
    je .fail                            ; an id of its own
    mov [rel output_id_b], eax
    cmp dword [rel ans + 4], 64
    jne .fail
    mov rdi, [rel output_b]             ; its scale
    mov esi, 3
    mov edx, 2
    call scale_fractional_compute
    OUTPUT_IS output_id_b, 64, 180
    lea rdi, [rel server]               ; a mirror: removed
    mov rsi, [rel output_b]
    mov rdx, [rel server + Server.outputs]
    call server_mirror_output
    REMOVED_IS output_id_b
    lea rdi, [rel server]               ; back
    mov rsi, [rel output_b]
    xor edx, edx
    call server_mirror_output
    OUTPUT_IS output_id_b, 64, 180
    lea rdi, [rel server]               ; taken away
    mov rsi, [rel output_b]
    call server_remove_output
    REMOVED_IS output_id_b
    PASS

; A 16x12 buffer at buffer scale 240 (twice the size each way) is an 8x6
; window: drawn 8x6 where it was placed, the pointer past its 8 columns not
; on it
tw_buffer_scale:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_surface
    mov [rel surface_a], eax
    mov rdi, [rel server + Server.buffer_table]  ; all of it green
    mov esi, [rel buffer]
    call handle_resolve
    mov rdi, [rax + Buffer.base]
    mov ecx, [rax + Buffer.stride]
    imul ecx, ecx, 12
    shr ecx, 2
    mov eax, 0xFF00FF00
    rep stosd
    mov eax, [rel surface_a]
    mov [rel req], eax
    mov dword [rel req + 4], 240
    SEND CWP_OBJ_SURFACE, SURFACE_SET_BUFFER_SCALE, 8
    TOPLEVEL TL_CREATE, surface_a, 0
    mov edi, [rel surface_a]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    SEES 10, 10, 0xFF00FF00             ; its corners
    SEES 17, 15, 0xFF00FF00
    SEES 18, 10, 0xFF202030             ; past them: the background
    SEES 10, 16, 0xFF202030
    POINTER 19, 11                      ; past its 8 columns: not on it
    call poll
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.pointer_focus], rax
    je .fail
    POINTER 15, 11                      ; on it
    call poll
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.pointer_focus], rax
    jne .fail
    PASS

; Super+Shift+H: the focused window's bar white and the background black;
; again, both as they were
tw_contrast:
    sub rsp, 8
    call decorated_window
    SEES 4, 2, 0xFF3E4C78
    SEES 60, 40, 0xFF202030
    INJECT INPUT_KEY, 125, 1            ; Super+Shift+H
    INJECT INPUT_KEY, 42, 1
    INJECT INPUT_KEY, 35, 1
    INJECT INPUT_KEY, 35, 0
    INJECT INPUT_KEY, 42, 0
    INJECT INPUT_KEY, 125, 0
    call poll
    SEES 4, 2, 0xFFFFFFFF
    SEES 60, 40, 0xFF000000
    INJECT INPUT_KEY, 125, 1
    INJECT INPUT_KEY, 42, 1
    INJECT INPUT_KEY, 35, 1
    INJECT INPUT_KEY, 35, 0
    INJECT INPUT_KEY, 42, 0
    INJECT INPUT_KEY, 125, 0
    call poll
    SEES 4, 2, 0xFF3E4C78
    SEES 60, 40, 0xFF202030
    PASS

; The magnifier at 2x round the pointer at the top left: the bar there fills
; the screen; the pointer at the far corner: background there; off, as it
; was; Super+Shift+M turns it on
tw_magnifier:
    sub rsp, 8
    call decorated_window               ; a bar along the top, the pointer at 0, 0
    SEES 60, 40, 0xFF202030
    lea rdi, [rel server]
    mov esi, 2
    call server_set_magnifier
    test rax, rax
    jnz .fail
    call poll
    SEES 60, 40, 0xFF3E4C78             ; the bar, twice the size
    SEES 0, 0, 0xFF3E4C78
    POINTER 63, 47                      ; the far corner
    call poll
    SEES 0, 0, 0xFF202030
    lea rdi, [rel server]               ; off
    xor esi, esi
    call server_set_magnifier
    call poll
    SEES 4, 2, 0xFF3E4C78
    SEES 60, 40, 0xFF202030
    INJECT INPUT_KEY, 125, 1            ; Super+Shift+M: 2x
    INJECT INPUT_KEY, 42, 1
    INJECT INPUT_KEY, 50, 1
    INJECT INPUT_KEY, 50, 0
    INJECT INPUT_KEY, 42, 0
    INJECT INPUT_KEY, 125, 0
    call poll
    cmp qword [rel server + Server.magnify], 2
    jne .fail
    PASS

; The magnifier follows the keyboard: an 8x6 green window A at 50, 36, the
; pointer at 0, 0 and 2x on, the view at the top left. A given the keyboard
; while the pointer is elsewhere: the view goes round it (kept inside, so
; from 32, 24), A at 36, 24 on the screen. The pointer moving leads again;
; on A, giving it the keyboard leaves the pointer leading. Alt+Tab from a
; window B under the pointer back to A: the view follows A
tw_magnify_focus:
    sub rsp, 8
    POINTER 50, 36
    mov edi, 8
    mov esi, 6
    call new_surface
    mov [rel surface_a], eax
    mov rdi, [rel server + Server.buffer_table]  ; all of it green
    mov esi, [rel buffer]
    call handle_resolve
    mov rdi, [rax + Buffer.base]
    mov ecx, [rax + Buffer.stride]
    imul ecx, ecx, 6
    shr ecx, 2
    mov eax, 0xFF00FF00
    rep stosd
    TOPLEVEL TL_CREATE, surface_a, 0
    mov edi, [rel surface_a]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    SEES 52, 38, 0xFF00FF00             ; there
    POINTER 0, 0
    lea rdi, [rel server]
    mov esi, 2
    call server_set_magnifier
    call poll
    SEES 60, 44, 0xFF202030             ; the top left, zoomed: not A
    mov edi, [rel surface_a]
    call surface_of
    mov rsi, rax
    lea rdi, [rel server]
    call magnify_focus
    call poll
    cmp qword [rel server + Server.magnify_follow], 1
    jne .fail
    SEES 40, 28, 0xFF00FF00             ; A, zoomed, from 36, 24
    SEES 2, 2, 0xFF202030
    POINTER 52, 38                      ; on A: the pointer leads
    call poll
    cmp qword [rel server + Server.magnify_follow], 0
    jne .fail
    mov edi, [rel surface_a]
    call surface_of
    mov rsi, rax
    lea rdi, [rel server]
    call magnify_focus
    cmp qword [rel server + Server.magnify_follow], 0
    jne .fail
    POINTER 0, 0                        ; B under the pointer, then
    mov edi, 8                          ; Alt+Tab back to A
    mov esi, 6
    call new_window
    mov [rel surface_b], eax
    call poll
    cmp qword [rel server + Server.magnify_follow], 0
    jne .fail
    INJECT INPUT_KEY, 56, 1
    INJECT INPUT_KEY, 15, 1
    INJECT INPUT_KEY, 15, 0
    INJECT INPUT_KEY, 56, 0
    call poll
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail
    cmp qword [rel server + Server.magnify_follow], 1
    jne .fail
    lea rdi, [rel server]               ; off
    xor esi, esi
    call server_set_magnifier
    PASS

; a raw touch record from device %1: slot %2, phase %3, at x %4, y %5
%macro TOUCH 5
    lea rdi, [rel server]
    mov esi, INPUT_TOUCH
    mov edx, %2 | (%3 << 8) | (1 << 12)
    mov ecx, %4 | (%5 << 16)
    mov r8d, %1
    call virtual_input_inject
%endmacro
; the next %1 event's surface is variable %2, a is %3 and b is %4
%macro EVENT_IS 4
    FIND %1
    mov eax, [rel %2]
    cmp [rel ans + 8], eax
    jne .fail
    cmp dword [rel ans + 12], %3
    jne .fail
    cmp dword [rel ans + 16], %4
    jne .fail
%endmacro

; Fingers: down on each of two windows, each window hears its own, in its
; own pixels, the second taking the keyboard; frame to both; a move, then
; up; a device with a range (the host's device 7, 1000 units) scaled onto
; the 64x48 output
tw_touch:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    POINTER 40, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_b], eax
    call drain
    TOUCH 0, 0, 0, 12, 12               ; slot 0 down on A
    TOUCH 0, 1, 0, 45, 12               ; slot 1 on B
    TOUCH 0, 0, 3, 0, 0                 ; the scan's end
    call poll
    EVENT_IS {CWP_OBJ_TOUCH, TOUCH_EV_DOWN}, surface_a, 0, 2 | (2 << 16)
    EVENT_IS {CWP_OBJ_TOUCH, TOUCH_EV_DOWN}, surface_b, 1, 5 | (2 << 16)
    FIND CWP_OBJ_TOUCH, TOUCH_EV_FRAME
    FIND CWP_OBJ_TOUCH, TOUCH_EV_FRAME
    mov edi, [rel surface_b]            ; the last tapped has the keyboard
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail
    TOUCH 0, 0, 1, 14, 13               ; slot 0 moves: still A's
    TOUCH 0, 0, 2, 14, 13               ; and is up
    TOUCH 0, 0, 3, 0, 0
    call poll
    EVENT_IS {CWP_OBJ_TOUCH, TOUCH_EV_MOTION}, surface_a, 0, 4 | (3 << 16)
    EVENT_IS {CWP_OBJ_TOUCH, TOUCH_EV_UP}, surface_a, 0, 0
    TOUCH 7, 2, 0, 250, 250             ; device 7: 250 of 1000 is 16, 12
    call poll
    EVENT_IS {CWP_OBJ_TOUCH, TOUCH_EV_DOWN}, surface_a, 2, 6 | (2 << 16)
    PASS

; a record of type %1, code %2, value %3 from device %4
%macro INJECT_FROM 4
    lea rdi, [rel server]
    mov esi, %1
    mov edx, %2
    mov ecx, %3
    mov r8d, %4
    call virtual_input_inject
%endmacro
; the next axis_value120 and axis events for window A
%macro SCROLLED 2                       ; 120ths, whole steps (none: skip)
    EVENT_IS {CWP_OBJ_POINTER, POINTER_EV_AXIS_VALUE120}, surface_a, 0, %1
  %if %2 != 0
    EVENT_IS {CWP_OBJ_POINTER, POINTER_EV_AXIS}, surface_a, 0, %2
  %endif
%endmacro

; PTR-03, PTR-04: two steps are 240 and 2; a fine wheel's 60 and 60 make
; one step only at the second; natural scrolling reverses; device 3 at
; double speed; cw_seat.set_pointer sets the default
tw_scroll:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    POINTER 15, 15
    call poll
    call drain
    INJECT INPUT_AXIS, 0, 2
    call poll
    SCROLLED 240, 2
    INJECT INPUT_AXIS, 0x100, 60
    call poll
    SCROLLED 60, 0
    mov edi, CWP_OBJ_POINTER            ; no whole step yet
    mov esi, POINTER_EV_AXIS
    call find_event
    test eax, eax
    jnz .fail
    INJECT INPUT_AXIS, 0x100, 60
    call poll
    SCROLLED 60, 1
    lea rdi, [rel server]
    mov esi, -1
    mov edx, POINTER_NATURAL
    xor ecx, ecx
    call server_set_pointer
    INJECT INPUT_AXIS, 0, 1
    call poll
    SCROLLED -120, -1
    lea rdi, [rel server]
    mov esi, 3
    xor edx, edx
    mov ecx, 240
    call server_set_pointer
    INJECT_FROM INPUT_AXIS, 0, 1, 3
    call poll
    SCROLLED 240, 2
    mov dword [rel req], -1             ; the protocol: default natural off
    mov dword [rel req + 4], 0
    mov dword [rel req + 8], 0
    SEND CWP_OBJ_SEAT, SEAT_SET_POINTER, 12
    call poll
    INJECT INPUT_AXIS, 0, 1
    call poll
    SCROLLED 120, 1
    PASS

; PTR-05: left-handed, a left press is the right button and a right the
; left; device 4 maps
; its button 2 to 7
tw_buttons:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    POINTER 15, 15
    call poll
    call drain
    lea rdi, [rel server]
    mov esi, -1
    mov edx, POINTER_LEFT_HANDED
    xor ecx, ecx
    call server_set_pointer
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
    EVENT_IS {CWP_OBJ_POINTER, POINTER_EV_BUTTON}, surface_a, 1, 1
    EVENT_IS {CWP_OBJ_POINTER, POINTER_EV_BUTTON}, surface_a, 1, 0
    INJECT INPUT_BUTTON, 1, 1           ; and a right press the left
    INJECT INPUT_BUTTON, 1, 0
    call poll
    EVENT_IS {CWP_OBJ_POINTER, POINTER_EV_BUTTON}, surface_a, 0, 1
    EVENT_IS {CWP_OBJ_POINTER, POINTER_EV_BUTTON}, surface_a, 0, 0
    lea rdi, [rel button_map]           ; every button itself, 2 as 7
    mov al, 0xFF
    mov ecx, 32
    rep stosb
    mov byte [rel button_map + 2], 7
    lea rdi, [rel server]
    mov esi, 4
    lea rdx, [rel button_map]
    call server_set_button_map
    test rax, rax
    jnz .fail
    INJECT_FROM INPUT_BUTTON, 2, 1, 4
    INJECT_FROM INPUT_BUTTON, 2, 0, 4
    call poll
    EVENT_IS {CWP_OBJ_POINTER, POINTER_EV_BUTTON}, surface_a, 7, 1
    PASS

; PTR-08: a window that asks hears the raw motion over it, 5, -3
tw_relative:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    POINTER 15, 15
    call poll
    call drain
    mov eax, [rel surface_a]
    mov [rel req], eax
    mov dword [rel req + 4], 1
    SEND CWP_OBJ_POINTER, POINTER_SET_RELATIVE, 8
    call poll
    INJECT INPUT_MOTION, 5, -3
    call poll
    EVENT_IS {CWP_OBJ_POINTER, POINTER_EV_RELATIVE_MOTION}, surface_a, 5, -3
    PASS

; a raw pen record: type %1, code %2, value %3
%macro PEN 3
    lea rdi, [rel server]
    mov esi, %1
    mov edx, %2
    mov ecx, %3
    xor r8d, r8d
    call virtual_input_inject
%endmacro

; The pen: in range over a window, it comes in and moves there; its axes
; pass on; the tip down keeps it with the window outside it; up and away,
; the tip lifts and it goes out
tw_pen:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    PEN INPUT_PEN, 1, 12 | (12 << 16)   ; in range, over the window
    PEN INPUT_PEN_AXES, 1000 | (5 << 16), 10 | (20 << 8) | (90 << 16)
    call poll
    EVENT_IS {CWP_OBJ_TABLET_TOOL, TABLET_TOOL_EV_PROXIMITY_IN}, surface_a, 0, 0
    EVENT_IS {CWP_OBJ_TABLET_TOOL, TABLET_TOOL_EV_MOTION}, surface_a, 2, 2
    EVENT_IS {CWP_OBJ_TABLET_TOOL, TABLET_TOOL_EV_AXES}, surface_a, 1000 | (5 << 16), 10 | (20 << 8) | (90 << 16)
    PEN INPUT_PEN, 3, 12 | (12 << 16)   ; the tip down
    PEN INPUT_PEN, 3, 40 | (40 << 16)   ; dragged off the window: kept
    call poll
    EVENT_IS {CWP_OBJ_TABLET_TOOL, TABLET_TOOL_EV_TIP}, surface_a, 1, 0
    EVENT_IS {CWP_OBJ_TABLET_TOOL, TABLET_TOOL_EV_MOTION}, surface_a, 30, 30
    PEN INPUT_PEN, 1, 40 | (40 << 16)   ; lifted there: tip up
    PEN INPUT_PEN, 1, 41 | (41 << 16)   ; moved on, over nothing: out
    call poll
    EVENT_IS {CWP_OBJ_TABLET_TOOL, TABLET_TOOL_EV_TIP}, surface_a, 0, 0
    FIND CWP_OBJ_TABLET_TOOL, TABLET_TOOL_EV_PROXIMITY_OUT
    PASS

; a pad record: what %1, which %2, value %3
%macro PAD 3
    lea rdi, [rel server]
    mov esi, INPUT_PAD
    mov edx, %1 | (%2 << 8)
    mov ecx, %3
    xor r8d, r8d
    call virtual_input_inject
%endmacro

; The pad: button 2 down and up, ring 0 at 90 and let go, strip 1 at 1000,
; each to the window with the keyboard; one of another kind is dropped
tw_pad:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    PAD INPUT_PAD_BUTTON, 2, 1
    PAD INPUT_PAD_BUTTON, 2, 0
    PAD INPUT_PAD_RING, 0, 90
    PAD INPUT_PAD_RING, 0, -1
    PAD 7, 0, 5                         ; no such kind
    PAD INPUT_PAD_STRIP, 1, 1000
    call poll
    EVENT_IS {CWP_OBJ_TABLET_PAD, TABLET_PAD_EV_BUTTON}, surface_a, 2, 1
    EVENT_IS {CWP_OBJ_TABLET_PAD, TABLET_PAD_EV_BUTTON}, surface_a, 2, 0
    EVENT_IS {CWP_OBJ_TABLET_PAD, TABLET_PAD_EV_RING}, surface_a, 0, 90
    EVENT_IS {CWP_OBJ_TABLET_PAD, TABLET_PAD_EV_RING}, surface_a, 0, -1
    EVENT_IS {CWP_OBJ_TABLET_PAD, TABLET_PAD_EV_STRIP}, surface_a, 1, 1000
    PASS

; a touchpad (host device 8) contact: slot %1, phase %2, at x %3, y %4
%macro PADTOUCH 4
    TOUCH 8, %1, %2, %3, %4
%endmacro
; the next cw_gesture event %1 has a = %2, b = %3, to window A
%macro GESTURE_IS 3
    EVENT_IS {CWP_OBJ_GESTURE, %1}, surface_a, %2, %3
%endmacro

; Touchpad gestures over window A, device 8's 1000 units on the 64x48
; output: three fingers down hold; moved together 13 pixels they swipe (the
; hold cancelled), then 10 more is an update; lifted, the swipe ends. Two
; fingers spreading from 12 to 25 pinch, 28 more is a scale of 28/12; lifted,
; it ends. Their contacts are not cw_touch
tw_gestures:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    PADTOUCH 0, 0, 100, 100
    PADTOUCH 1, 0, 200, 100
    PADTOUCH 2, 0, 300, 100
    PADTOUCH 0, 3, 0, 0
    call poll
    GESTURE_IS GESTURE_EV_HOLD_BEGIN, 3, 0
    PADTOUCH 0, 1, 300, 100             ; x 6, 12, 19 to 19, 25, 32
    PADTOUCH 1, 1, 400, 100
    PADTOUCH 2, 1, 500, 100
    PADTOUCH 0, 3, 0, 0
    call poll
    GESTURE_IS GESTURE_EV_HOLD_END, 1, 0
    GESTURE_IS GESTURE_EV_SWIPE_BEGIN, 3, 0
    PADTOUCH 0, 1, 460, 100             ; the middle 25 to 35
    PADTOUCH 1, 1, 560, 100
    PADTOUCH 2, 1, 660, 100
    PADTOUCH 0, 3, 0, 0
    call poll
    GESTURE_IS GESTURE_EV_SWIPE_UPDATE, 10, 3
    PADTOUCH 0, 2, 0, 0
    PADTOUCH 1, 2, 0, 0
    PADTOUCH 2, 2, 0, 0
    PADTOUCH 0, 3, 0, 0
    call poll
    GESTURE_IS GESTURE_EV_SWIPE_END, 0, 0

    PADTOUCH 0, 0, 300, 500             ; x 19 and 44: spread 12
    PADTOUCH 1, 0, 700, 500
    PADTOUCH 0, 3, 0, 0
    call poll
    GESTURE_IS GESTURE_EV_HOLD_BEGIN, 2, 0
    PADTOUCH 0, 1, 100, 500             ; 6 and 57: 25
    PADTOUCH 1, 1, 900, 500
    PADTOUCH 0, 3, 0, 0
    call poll
    GESTURE_IS GESTURE_EV_HOLD_END, 1, 0
    GESTURE_IS GESTURE_EV_PINCH_BEGIN, 2, 0
    PADTOUCH 0, 1, 50, 500              ; 3 and 60: 28
    PADTOUCH 1, 1, 950, 500
    PADTOUCH 0, 3, 0, 0
    call poll
    GESTURE_IS GESTURE_EV_PINCH_UPDATE, (28 << 16) / 12, 0
    PADTOUCH 0, 2, 0, 0
    PADTOUCH 1, 2, 0, 0
    PADTOUCH 0, 3, 0, 0
    call poll
    GESTURE_IS GESTURE_EV_PINCH_END, 0, 0

    PADTOUCH 0, 0, 300, 300             ; one more: a hold, no cw_touch
    PADTOUCH 0, 3, 0, 0
    call poll
    mov edi, CWP_OBJ_TOUCH
    call any_event
    test eax, eax
    jnz .fail
    PASS

; four touchpad fingers at x %1 (phase %2: 0 down, 1 moved), a frame
%macro FOUR_AT 2
    PADTOUCH 0, %2, %1, 100
    PADTOUCH 1, %2, %1 + 20, 300
    PADTOUCH 2, %2, %1 + 40, 500
    PADTOUCH 3, %2, %1 + 60, 700
    PADTOUCH 0, 3, 0, 0
%endmacro
; four fingers lifted, a frame
%macro FOUR_UP 0
    PADTOUCH 0, 2, 0, 0
    PADTOUCH 1, 2, 0, 0
    PADTOUCH 2, 2, 0, 0
    PADTOUCH 3, 2, 0, 0
    PADTOUCH 0, 3, 0, 0
%endmacro

; Four fingers swiped 51 pixels left show workspace 1, no swipe to the
; client; right, back to 0; right again, nothing before 0; a short swipe
; does nothing
tw_workspace_swipe:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    FOUR_AT 800, 0
    FOUR_AT 0, 1
    FOUR_UP
    call poll
    cmp qword [rel server + Server.workspace], 1
    jne .fail
    mov edi, CWP_OBJ_GESTURE            ; a hold, but no swipe for it
    mov esi, GESTURE_EV_SWIPE_BEGIN
    call find_event
    test eax, eax
    jnz .fail
    FOUR_AT 0, 0                        ; right: back
    FOUR_AT 800, 1
    FOUR_UP
    call poll
    cmp qword [rel server + Server.workspace], 0
    jne .fail
    FOUR_AT 0, 0                        ; right again: none before 0
    FOUR_AT 800, 1
    FOUR_UP
    call poll
    cmp qword [rel server + Server.workspace], 0
    jne .fail
    FOUR_AT 400, 0                      ; short: 19 pixels, nothing
    FOUR_AT 100, 1
    FOUR_UP
    call poll
    cmp qword [rel server + Server.workspace], 0
    jne .fail
    PASS

; The pen curve: with both inner heights at 65535, a quarter press (16384)
; comes out at 1 - (3/4)^3 of full (37888), the hover distance kept; no
; curve, it passes as it came
tw_pen_curve:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    lea rdi, [rel server]
    mov esi, 65535
    mov edx, 65535
    call server_set_pen_curve
    test rax, rax
    jnz .fail
    PEN INPUT_PEN, 1, 12 | (12 << 16)
    PEN INPUT_PEN_AXES, 16384 | (5 << 16), 0
    call poll
    EVENT_IS {CWP_OBJ_TABLET_TOOL, TABLET_TOOL_EV_AXES}, surface_a, 37888 | (5 << 16), 0
    lea rdi, [rel server]
    xor esi, esi
    xor edx, edx
    call server_set_pen_curve
    PEN INPUT_PEN_AXES, 16384 | (5 << 16), 0
    call poll
    EVENT_IS {CWP_OBJ_TABLET_TOOL, TABLET_TOOL_EV_AXES}, surface_a, 16384 | (5 << 16), 0
    lea rdi, [rel server]               ; out of range
    mov esi, 70000
    xor edx, edx
    call server_set_pen_curve
    cmp rax, -(EINVAL)
    jne .fail
    PASS

; the next cw_seat event %1 says %2, then %3
%macro SEAT_IS 3
    FIND CWP_OBJ_SEAT, %1
    cmp dword [rel ans], %2
    jne .fail
    cmp dword [rel ans + 4], %3
    jne .fail
%endmacro

; cw_seat: a switch on before watching is told at watch, then done; the
; same again tells nothing, off tells off; device 7 removed with a finger
; down cancels it, frames, then tells device(removed, 7, its caps)
tw_seat:
    sub rsp, 8
    INJECT INPUT_SWITCH, 1, 1           ; tablet mode on
    call poll
    SEND CWP_OBJ_SEAT, SEAT_WATCH, 0
    call poll
    SEAT_IS SEAT_EV_SWITCHED, 1, 1
    FIND CWP_OBJ_SEAT, SEAT_EV_DONE
    INJECT INPUT_SWITCH, 1, 1           ; as it was: nothing
    INJECT INPUT_SWITCH, 1, 0
    call poll
    SEAT_IS SEAT_EV_SWITCHED, 1, 0      ; (1, 1) here if the same was told
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    TOUCH 7, 3, 0, 250, 250             ; slot 3 down on A
    call poll
    EVENT_IS {CWP_OBJ_TOUCH, TOUCH_EV_DOWN}, surface_a, 3, 6 | (2 << 16)
    lea rdi, [rel server]               ; device 7 gone
    mov esi, INPUT_DEVICE
    mov edx, INPUT_DEVICE_REMOVED
    mov ecx, 4
    mov r8d, 7
    call virtual_input_inject
    call poll
    EVENT_IS {CWP_OBJ_TOUCH, TOUCH_EV_CANCEL}, surface_a, 3, 0
    FIND CWP_OBJ_TOUCH, TOUCH_EV_FRAME
    FIND CWP_OBJ_SEAT, SEAT_EV_DEVICE
    cmp dword [rel ans], INPUT_DEVICE_REMOVED
    jne .fail
    cmp dword [rel ans + 4], 7
    jne .fail
    cmp dword [rel ans + 8], 4
    jne .fail
    mov rax, [rel server + Server.input_seat]
    lea rcx, [rax + InputSeat.touches]  ; no contact left
    xor edx, edx
.contacts:
    cmp qword [rcx + TouchContact.surface], 0
    jne .fail
    add rcx, TouchContact_size
    inc edx
    cmp edx, TOUCH_SLOTS
    jb .contacts
    PASS

; pixel x, y of the first output's pixels (at a scale: Output.pixel_fb) is
; %3
%macro PIXEL_IS 3
    mov rax, [rel server + Server.outputs]
    mov rcx, [rax + Output.pixel_stride]
    mov rax, [rax + Output.pixel_fb]
    test rax, rax
    jz .fail
    imul rcx, rcx, %2
    add rax, rcx
    cmp dword [rax + (%1) * 4], %3
    jne .fail
%endmacro

; The logical layout: a second output to the right, then the first at 2x.
; It is 32x24 in the layout, the second moves from 64 to 32 and the pointer
; at 40 is on the second; clients hear both. An 8x6 green window at 10, 10
; on the first covers pixels 20-35 by 20-31 there (scaled up, its edges
; blended), the background around it. Back at 1, all is as it was
tw_logical:
    sub rsp, 8
    lea rdi, [rel server]
    mov esi, 64
    mov edx, 48
    call server_add_output
    test rax, rax
    jz .fail
    mov [rel output_b], rax
    SEND CWP_OBJ_OUTPUT, OUTPUT_LIST, 0
    call poll
    call drain
    lea rdi, [rel server]
    mov rsi, [rel server + Server.outputs]
    mov edx, 240
    call output_set_scale
    test rax, rax
    jnz .fail
    mov rax, [rel server + Server.outputs]
    cmp dword [rax + Output.width], 32
    jne .fail
    cmp dword [rax + Output.height], 24
    jne .fail
    cmp dword [rax + Output.pixel_width], 64
    jne .fail
    mov rax, [rel output_b]
    cmp qword [rax + Output.x], 32
    jne .fail
    lea rdi, [rel server]
    mov esi, 40
    mov edx, 10
    call compositor_output_at
    cmp rax, [rel output_b]
    jne .fail
    FIND CWP_OBJ_OUTPUT, OUTPUT_EV_OUTPUT   ; the first: 32 wide, 2x
    cmp dword [rel ans + 12], 32
    jne .fail
    cmp dword [rel ans + 20], 240
    jne .fail
    FIND CWP_OBJ_OUTPUT, OUTPUT_EV_OUTPUT   ; the second, at 32
    cmp dword [rel ans + 4], 32
    jne .fail

    POINTER 10, 10
    mov edi, 8
    mov esi, 6
    call new_surface
    mov [rel surface_a], eax
    mov rdi, [rel server + Server.buffer_table]  ; all of it green
    mov esi, [rel buffer]
    call handle_resolve
    mov rdi, [rax + Buffer.base]
    mov ecx, [rax + Buffer.stride]
    imul ecx, ecx, 6
    shr ecx, 2
    mov eax, 0xFF00FF00
    rep stosd
    TOPLEVEL TL_CREATE, surface_a, 0
    mov edi, [rel surface_a]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    call poll
    PIXEL_IS 22, 22, 0xFF00FF00         ; inside its corners, in pixels
    PIXEL_IS 33, 29, 0xFF00FF00         ; (the edge ones blend, bilinear)
    PIXEL_IS 40, 22, 0xFF202030         ; past them: the background
    PIXEL_IS 22, 36, 0xFF202030
    PIXEL_IS 16, 22, 0xFF202030
    POINTER 17, 15                      ; its last logical pixel: on it
    call poll
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.pointer_focus], rax
    jne .fail

    lea rdi, [rel server]               ; 1 again
    mov rsi, [rel server + Server.outputs]
    mov edx, 120
    call output_set_scale
    mov rax, [rel server + Server.outputs]
    cmp dword [rax + Output.width], 64
    jne .fail
    cmp qword [rax + Output.pixel_fb], 0
    jne .fail
    mov rax, [rel output_b]
    cmp qword [rax + Output.x], 64
    jne .fail
    call poll
    SEES 10, 10, 0xFF00FF00             ; drawn 1:1 again
    SEES 18, 10, 0xFF202030
    PASS

; Composed in the pixels: the first output at 1.5 (43x32 in the layout).
; A 25x18 buffer drawn at 1.5 is about a 16x12 window; at 10, 10 its edges
; come to pixels 15 across and 15 and 33 down, within a pixel of its size,
; so it is copied pixel for pixel: red and blue columns stay apart (scaled,
; they would blend). With the magnifier on it composes logical, then
; scales; off, in the pixels again
tw_pixels:
    sub rsp, 8
    lea rdi, [rel server]
    mov rsi, [rel server + Server.outputs]
    mov edx, 180
    call output_set_scale
    test rax, rax
    jnz .fail
    POINTER 10, 10
    mov edi, 25
    mov esi, 18
    call new_surface
    mov [rel surface_a], eax
    mov rdi, [rel server + Server.buffer_table]
    mov esi, [rel buffer]
    call handle_resolve
    mov rdi, [rax + Buffer.base]        ; even columns red, odd ones blue
    mov r8d, [rax + Buffer.stride]
    xor edx, edx
.fill_row:
    xor ecx, ecx
.fill_column:
    mov eax, 0xFFFF0000
    test ecx, 1
    jz .even
    mov eax, 0xFF0000FF
.even:
    mov [rdi + rcx * 4], eax
    inc ecx
    cmp ecx, 25
    jb .fill_column
    add rdi, r8
    inc edx
    cmp edx, 18
    jb .fill_row
    mov eax, [rel surface_a]
    mov [rel req], eax
    mov dword [rel req + 4], 180
    SEND CWP_OBJ_SURFACE, SURFACE_SET_BUFFER_SCALE, 8
    TOPLEVEL TL_CREATE, surface_a, 0
    mov edi, [rel surface_a]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    call poll
    mov rax, [rel server + Server.outputs]
    cmp dword [rax + Output.compose_px], 1
    jne .fail
    PIXEL_IS 15, 15, 0xFFFF0000         ; its first column
    PIXEL_IS 16, 15, 0xFF0000FF
    PIXEL_IS 17, 20, 0xFFFF0000
    PIXEL_IS 35, 15, 0xFFFF0000         ; column 20, not a blend
    PIXEL_IS 38, 32, 0xFF0000FF         ; column 23, the last row
    PIXEL_IS 14, 15, 0xFF202030         ; round it, the background
    PIXEL_IS 20, 33, 0xFF202030
    lea rdi, [rel server]               ; the magnifier: logical, scaled
    mov esi, 2
    call server_set_magnifier
    call poll
    mov rax, [rel server + Server.outputs]
    cmp dword [rax + Output.compose_px], 0
    jne .fail
    lea rdi, [rel server]
    xor esi, esi
    call server_set_magnifier
    call poll
    mov rax, [rel server + Server.outputs]
    cmp dword [rax + Output.compose_px], 1
    jne .fail
    PIXEL_IS 15, 15, 0xFFFF0000
    PIXEL_IS 16, 15, 0xFF0000FF
    PASS

; What the server draws, in the pixels at 1.5: a focused window's title bar
; along the top (its colour at pixel 3, 3); the pointer at 30, 26 has its
; tip at pixel 45, 39 and is drawn at 2x (its fill at 47, 43); at 31, 27
; (46.5, 40.5) the tip is rounded to 47, 41; at 30, 4 its edge reaches 20
; pixels down, as only a 2x arrow does
tw_pixel_parts:
    sub rsp, 8
    lea rdi, [rel server]
    mov rsi, [rel server + Server.outputs]
    mov edx, 180
    call output_set_scale
    call decorated_window
    call poll
    PIXEL_IS 3, 3, 0xFF3E4C78
    mov rax, [rel server + Server.compositor]
    mov qword [rax + Compositor.cursor_on], 1
    POINTER 30, 26
    call poll
    PIXEL_IS 45, 39, 0xFF000000         ; the tip
    PIXEL_IS 47, 43, 0xFFFFFFFF         ; the fill, at 2x
    POINTER 31, 27                      ; 46.5, 40.5: rounded to 47, 41
    call poll
    PIXEL_IS 47, 41, 0xFF000000
    PIXEL_IS 46, 41, 0xFF202030
    POINTER 30, 4                       ; 2x: its edge 20 rows down (past
    call poll                           ; a 1x arrow's 17)
    PIXEL_IS 45, 26, 0xFF000000
    mov rax, [rel server + Server.compositor]
    mov qword [rax + Compositor.cursor_on], 0
    PASS

; Snapped: at 1.25 a window placed at the pointer, 10, 10, goes to 8, 8, a
; whole 10 pixels; at 1.5, to 10, 10 itself (15 pixels); at 1 it stays at 11
tw_snap:
    sub rsp, 8
    lea rdi, [rel server]
    mov rsi, [rel server + Server.outputs]
    mov edx, 150
    call output_set_scale
    POINTER 10, 10
    mov edi, 8
    mov esi, 6
    call new_window
    mov [rel surface_a], eax
    mov edi, [rel surface_a]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 8
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 8
    jne .fail
    lea rdi, [rel server]
    mov rsi, [rel server + Server.outputs]
    mov edx, 180
    call output_set_scale
    POINTER 11, 10
    mov edi, 8
    mov esi, 6
    call new_window
    mov [rel surface_b], eax
    mov edi, [rel surface_b]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 10
    jne .fail
    lea rdi, [rel server]
    mov rsi, [rel server + Server.outputs]
    mov edx, 120
    call output_set_scale
    POINTER 11, 10
    mov edi, 8
    mov esi, 6
    call new_window
    mov edi, eax
    call surface_of
    test rax, rax
    jz .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 11
    jne .fail
    PASS

; a cw_toplevel request %1 on surface variable %2 with dwords %3, %4
%macro TL_REQ 4
    mov eax, [rel %2]
    mov [rel req], eax
    mov dword [rel req + 4], %3
    mov dword [rel req + 8], %4
    SEND CWP_OBJ_TOPLEVEL, %1, 12
%endmacro
; surface variable %1 is the keyboard's
%macro KEYBOARD_ON 1
    mov edi, [rel %1]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail
%endmacro
; a click at %1, %2, then a turn
%macro CLICK_AT_XY 2
    POINTER %1, %2
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
%endmacro
; window variable %1's Window.state has WINDOW_URGENT (%2 = 1) or not (0)
%macro URGENT_IS 2
    mov edi, [rel %1]
    call surface_of
    mov rax, [rax + Surface.window]
    mov eax, [rax + Window.state]
    and eax, WINDOW_URGENT
  %if %2
    jz .fail
  %else
    jnz .fail
  %endif
%endmacro

; edi = width, esi = height: a window that belongs to surface_a, made with
; set_parent before its first buffer -> eax = its handle
child_window:
    push rbx
    call new_surface
    mov ebx, eax
    mov [rel req], eax
    SEND CWP_OBJ_TOPLEVEL, TL_CREATE, 4
    mov [rel req], ebx
    mov eax, [rel surface_a]
    mov [rel req + 4], eax
    SEND CWP_OBJ_TOPLEVEL, TOPLEVEL_SET_PARENT, 8
    mov edi, ebx
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    mov eax, ebx
    pop rbx
    ret

; WIN-08: limits 20x15 to 40x30; maximized on the 64x48 output it is asked
; to be 40x30
tw_size_limits:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    call drain
    TL_REQ TOPLEVEL_SET_MIN_SIZE, surface_a, 20, 15
    TL_REQ TOPLEVEL_SET_MAX_SIZE, surface_a, 40, 30
    TOPLEVEL TL_SET_MAX, surface_a, 0
    call poll
    CONFIGURED 40, 30, 1
    PASS

; WIN-11: B, A's child, opens centred on A (22, 19), not at the pointer;
; a click on A raises B with it; A moved takes B along; A to workspace 2
; takes B; A's role gone, B belongs to none
tw_transient:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 32
    mov esi, 24
    call new_window
    mov [rel surface_a], eax
    POINTER 50, 40
    mov edi, 8
    mov esi, 6
    call child_window
    mov [rel surface_b], eax
    call poll
    mov edi, [rel surface_b]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 22
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 19
    jne .fail
    CLICK_AT_XY 12, 12                  ; A raised: B still above it
    mov edi, [rel surface_b]
    call surface_of
    mov rcx, [rax + Surface.z_order_next]
    test rcx, rcx
    jnz .fail                           ; B is the top
    lea rdi, [rel server]
    mov edi, [rel surface_a]            ; A moved 5 right, 3 down: B too
    call surface_of
    lea rdi, [rel server]
    mov rsi, rax
    mov edx, 15
    mov ecx, 13
    call window_move
    mov edi, [rel surface_b]
    call surface_of
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 27
    jne .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 22
    jne .fail
    mov edi, [rel surface_a]
    call surface_of
    lea rdi, [rel server]
    mov rsi, rax
    mov edx, 2
    call window_move_to_workspace
    mov edi, [rel surface_b]
    call surface_of
    mov rax, [rax + Surface.window]
    cmp dword [rax + Window.workspace], 2
    jne .fail
    mov eax, [rel surface_a]            ; A's role ends
    mov [rel req], eax
    SEND CWP_OBJ_TOPLEVEL, TL_DESTROY, 4
    call poll
    mov edi, [rel surface_b]
    call surface_of
    mov rax, [rax + Surface.window]
    cmp qword [rax + Window.transient], 0
    jne .fail
    PASS

; WIN-10: B, A's modal child, has the keyboard; a click on A leaves it with
; B; not modal, a click on A gives it to A
tw_modal:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 32
    mov esi, 24
    call new_window
    mov [rel surface_a], eax
    mov edi, 8
    mov esi, 6
    call child_window
    mov [rel surface_b], eax
    TL_REQ TOPLEVEL_SET_MODAL, surface_b, 1, 0
    call poll
    KEYBOARD_ON surface_b
    CLICK_AT_XY 12, 12
    KEYBOARD_ON surface_b
    TL_REQ TOPLEVEL_SET_MODAL, surface_b, 0, 0
    call poll
    CLICK_AT_XY 12, 12
    KEYBOARD_ON surface_a
    PASS

; WIN-14: B has the keyboard; A asks for attention: urgent; clicked, not;
; B asking while it has the keyboard is not marked
tw_attention:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    POINTER 40, 30
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_b], eax
    TL_REQ TOPLEVEL_REQUEST_ATTENTION, surface_a, 0, 0
    TL_REQ TOPLEVEL_REQUEST_ATTENTION, surface_b, 0, 0
    call poll
    URGENT_IS surface_a, 1
    URGENT_IS surface_b, 0
    CLICK_AT_XY 12, 12
    KEYBOARD_ON surface_a
    URGENT_IS surface_a, 0
    PASS

; WIN-12: A has the keyboard and a key was just pressed; B, another client,
; shows a window: A keeps the keyboard, B's is urgent. With no press lately
; B's next window takes it
tw_focus_steal:
    sub rsp, 8
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    INJECT INPUT_KEY, 30, 1
    INJECT INPUT_KEY, 30, 0
    call poll
    lea rdi, [rel server]               ; B, another client
    lea rsi, [rel pair_b]
    mov edx, CAP_SHELL | CAP_POINTER | CAP_KEYBOARD
    call client_accept
    test rax, rax
    js .fail
    AS pair_b
    call drain
    POINTER 40, 30
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_b], eax
    AS pair
    KEYBOARD_ON surface_a
    URGENT_IS surface_b, 1
    mov rax, [rel server + Server.input_seat]
    mov qword [rax + InputSeat.last_input], 0
    AS pair_b
    POINTER 40, 10
    mov edi, 8
    mov esi, 6
    call new_window
    mov [rel surface_c], eax
    AS pair
    KEYBOARD_ON surface_c
    PASS

; %1 (a table field of Server) still resolves handle variable %2
%macro STILL_THERE 2
    mov rdi, [rel server + Server.%1]
    mov esi, [rel %2]
    call handle_resolve
    test rax, rax
    jz .fail
%endmacro
; a request as the current client: interface, opcode, handle variable %3
%macro ON_HANDLE 3
    mov eax, [rel %3]
    mov [rel req], eax
    mov dword [rel req + 4], 0
    mov qword [rel req + 8], 0
    mov qword [rel req + 16], 0
    SEND %1, %2, 24
%endmacro

; SEC-01: another client cannot touch A's region, fence or timeline. A makes
; one of each; B, a standard client, destroys each and signals the fence and
; timeline; every one is still there and still A's
tw_foreign_objects:
    sub rsp, 8
    SEND CWP_OBJ_REGION, REGION_CREATE, 0
    call poll
    call next_reply
    mov eax, [rel ans]
    mov [rel foreign_region], eax
    mov dword [rel req], 0
    SEND CWP_OBJ_FENCE, FENCE_CREATE, 4
    call poll
    call next_reply
    mov eax, [rel ans]
    mov [rel foreign_fence], eax
    SEND CWP_OBJ_TIMELINE, TIMELINE_CREATE, 0
    call poll
    call next_reply
    mov eax, [rel ans]
    mov [rel foreign_timeline], eax
    STILL_THERE region_table, foreign_region
    STILL_THERE fence_table, foreign_fence
    STILL_THERE timeline_table, foreign_timeline

    lea rdi, [rel server]               ; B, a standard client
    lea rsi, [rel pair_b]
    mov edx, CAP_SURFACE | CAP_BUFFER
    call client_accept
    test rax, rax
    js .fail
    AS pair_b
    call drain
    ON_HANDLE CWP_OBJ_REGION, REGION_DESTROY, foreign_region
    ON_HANDLE CWP_OBJ_REGION, REGION_CLEAR, foreign_region
    ON_HANDLE CWP_OBJ_FENCE, FENCE_SIGNAL, foreign_fence
    ON_HANDLE CWP_OBJ_FENCE, FENCE_DESTROY, foreign_fence
    ON_HANDLE CWP_OBJ_TIMELINE, TIMELINE_SIGNAL, foreign_timeline
    ON_HANDLE CWP_OBJ_TIMELINE, TIMELINE_DESTROY, foreign_timeline
    call poll
    call drain
    AS pair
    STILL_THERE region_table, foreign_region
    STILL_THERE fence_table, foreign_fence
    STILL_THERE timeline_table, foreign_timeline
    PASS

; Input wakes the event loop: each record queued is a wake of its task
; (here a made-up one, 7)
tw_wake:
    sub rsp, 8
    mov qword [rel server + Server.loop_task], 7
    mov rax, [rel server + Server.wakes]
    mov [rsp], rax
    INJECT INPUT_KEY, 30, 1
    INJECT INPUT_KEY, 30, 0
    mov rax, [rel server + Server.wakes]
    sub rax, [rsp]
    cmp rax, 2
    jne .fail
    mov qword [rel server + Server.loop_task], 0
    PASS

; the lid closed (1) or open (0), then a turn
%macro LID 1
    INJECT INPUT_SWITCH, INPUT_SWITCH_LID, %1
    call poll
%endmacro
; the first output (the built-in panel): dpms state %1, mirror of %2 (0 or
; a variable holding an Output*)
%macro PANEL 2
    mov rax, [rel server + Server.outputs]
    cmp byte [rax + Output.dpms_state], %1
    jne .fail
%ifidn %2, 0
    cmp qword [rax + Output.mirror_of], 0
%else
    mov rcx, [rel %2]
    cmp [rax + Output.mirror_of], rcx
%endif
    jne .fail
%endmacro

; The first output marked the built-in panel. Alone, the lid closed turns
; it off and open on. With a second output the lid closed also makes it a
; mirror of that one, its window moving there; open, it is its own again.
; Closed, the second unplugged leaves it its own part, still off; another
; plugged in takes its place
tw_clamshell:
    sub rsp, 8
    mov rax, [rel server + Server.outputs]
    mov byte [rax + Output.builtin], 1
    POINTER 10, 10
    mov edi, 16
    mov esi, 12
    call new_window
    mov [rel surface_a], eax
    LID 1
    PANEL 3, 0
    LID 0
    PANEL 0, 0
    lea rdi, [rel server]
    mov esi, 64
    mov edx, 48
    call server_add_output
    test rax, rax
    jz .fail
    mov [rel output_b], rax
    LID 1
    PANEL 3, output_b
    mov edi, [rel surface_a]            ; the window went to the second
    call surface_of
    mov rcx, [rel output_b]
    cmp [rax + Surface.output], rcx
    jne .fail
    LID 0
    PANEL 0, 0
    LID 1
    lea rdi, [rel server]               ; the second unplugged
    mov rsi, [rel output_b]
    call server_remove_output
    test rax, rax
    jnz .fail
    PANEL 3, 0
    lea rdi, [rel server]               ; another plugged in
    mov esi, 64
    mov edx, 48
    call server_add_output
    test rax, rax
    jz .fail
    mov [rel output_b], rax
    PANEL 3, output_b
    LID 0
    PANEL 0, 0
    PASS

; -> eax = how many outputs the server has
output_count:
    xor eax, eax
    mov rcx, [rel server + Server.outputs]
.next:
    test rcx, rcx
    jz .out
    inc eax
    mov rcx, [rcx + Output.next]
    jmp .next
.out:
    ret

; type, framebuffer index: reported as the kernel would, then acted on.
; Through displays_event itself, so the test names nothing only the host
; stand-ins have and links into the test image too.
%macro DISPLAY 2
    mov dword [rel display_record], %1
    mov dword [rel display_record + 4], %2
    lea rdi, [rel display_record]
    lea rsi, [rel server]
    call displays_event
    lea rdi, [rel server]
    call displays_step
%endmacro

; A server on a framebuffer is told of a second display (the host's
; framebuffer 1): an output to the right shows in its own display memory,
; its rows' padding untouched; told again, or of one ut_fb_info does not
; know, nothing more; removed, it goes; the last does not
tw_displays:
    sub rsp, 8
    lea rdi, [rel arena]                ; a server on a framebuffer this time
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rax, [rel fb0]
    mov [rel fb0_conf + Config.fb_base], rax
    mov dword [rel fb0_conf + Config.fb_width], 64
    mov dword [rel fb0_conf + Config.fb_height], 48
    mov dword [rel fb0_conf + Config.fb_stride], 64 * 4
    mov qword [rel fb0_conf + Config.fb_size], 64 * 4 * 48
    lea rdi, [rel server]
    lea rsi, [rel arena]
    mov edx, 64
    mov ecx, 48
    lea r8, [rel fb0_conf]
    call server_init
    test rax, rax
    js .fail
    lea rdi, [rel server]
    call displays_start
    test rax, rax
    jnz .fail

    DISPLAY 1, 1
    call output_count
    cmp eax, 2
    jne .fail
    mov rax, [rel server + Server.outputs]
    mov rax, [rax + Output.next]
    cmp dword [rax + Output.x], 64
    jne .fail
    cmp dword [rax + Output.fb_index], 1
    jne .fail
    cmp qword [rax + Output.scanout_pitch], 40 * 4
    jne .fail                           ; the host's framebuffer 1
    mov rcx, [rax + Output.scanout]
    test rcx, rcx
    jz .fail
    mov [rel fb1], rcx
    call poll                           ; drawn, and shown there
    mov eax, [rel fb0]                  ; the background, as on the first
    test eax, eax
    jz .fail
    mov rcx, [rel fb1]
    cmp [rcx], eax
    jne .fail
    cmp [rcx + (23 * 40 + 31) * 4], eax
    jne .fail
    cmp dword [rcx + 32 * 4], 0
    jne .fail                           ; past its row: untouched

    DISPLAY 1, 1                        ; again: shown already
    DISPLAY 1, 5                        ; no such framebuffer
    call output_count
    cmp eax, 2
    jne .fail
    DISPLAY 2, 1                        ; taken out
    call output_count
    cmp eax, 1
    jne .fail
    DISPLAY 2, 0                        ; the last stays
    call output_count
    cmp eax, 1
    jne .fail
    PASS

; Server.locked to edi, every output redrawn, a turn
lock_to:
    sub rsp, 8
    mov [rel server + Server.locked], rdi
    lea rdi, [rel server]
    call compositor_damage_all
    call poll
    add rsp, 8
    ret

; Locked, a window on the second output is not drawn, the pointer does not
; find it and one shown meanwhile does not take the keyboard; unlocked, it
; is back
tw_locked:
    sub rsp, 8
    lea rdi, [rel server]
    mov esi, 64
    mov edx, 48
    call server_add_output
    test rax, rax
    jz .fail
    mov [rel output_b], rax
    call poll                           ; drawn a first time
    mov edi, 60                         ; the second's background, for later
    mov esi, 40
    call second_pixel
    mov [rel region_h], eax
    POINTER 80, 0                       ; A with a bar: pixels to see
    mov edi, 16
    mov esi, 12
    call new_surface
    mov [rel surface_a], eax
    TOPLEVEL TL_CREATE, surface_a, 0
    TOPLEVEL TL_SET_DECO, surface_a, 1
    mov edi, [rel surface_a]
    mov esi, [rel buffer]
    xor edx, edx
    xor ecx, ecx
    call show
    mov edi, 80 - 64 + 2
    mov esi, 2
    call second_pixel
    cmp eax, [rel region_h]
    je .fail                            ; drawn

    mov edi, 1
    call lock_to
    mov edi, 80 - 64 + 2
    mov esi, 2
    call second_pixel
    cmp eax, [rel region_h]
    jne .fail                           ; locked: background
    POINTER 85, 30                      ; over its content
    call poll
    mov rax, [rel server + Server.input_seat]
    cmp qword [rax + InputSeat.pointer_focus], 0
    jne .fail                           ; nothing under the pointer
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail                           ; A keeps what it had
    POINTER 10, 10
    mov edi, 16                         ; B shown while locked: no keyboard
    mov esi, 12
    call new_window
    mov [rel surface_b], eax
    mov edi, [rel surface_a]
    call surface_of
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail

    xor edi, edi
    call lock_to
    mov edi, 80 - 64 + 2
    mov esi, 2
    call second_pixel
    cmp eax, [rel region_h]
    je .fail                            ; back
    PASS

section .data
align 8
scale_src:      dd 1, 2, 3, 4           ; 2 x 2
blend_src:      dd 0xFF000000, 0xFFFFFFFF   ; 2 x 1
clip_type:      db "text/plain"
                times CLIP_TYPE_LEN - 10 db 0
clip_remote:    db "remote"
corner_src:     dd 0xFF000000, 0xFF000000   ; 2 x 2, the bottom left white
                dd 0xFFFFFFFF, 0xFF000000

section .bss
alignb 16
server:         resb Server_size
scale_dst:      resd 16                 ; 4 x 4
fb0:            resd 64 * 48            ; tw_displays' boot framebuffer
fb0_conf:       resb Config_size
fb1:            resq 1                  ; framebuffer 1's display memory
display_record: resd 2                  ; type, index
fr_ctx:         resb FrameCtx_size
scaled_size:    resd 2
scale_job:      resb UgfxScale_SIZE
arena:          resb Arena_size
pair:           resb ChannelPair_size
pair_b:         resb ChannelPair_size   ; a second client, when a case wants one
cur_pair:       resq 1                  ; the one the helpers talk through
client_a:       resq 1                  ; pair's client id
clip_serial:    resd 1
output_id_a:    resd 1
output_id_b:    resd 1
hdr:            resb MsgHdr_size
surface_a:      resd 1
surface_b:      resd 1
surface_c:      resd 1
buffer_a:       resd 1
region_h:       resd 1
fence_a:        resd 1
timeline:       resd 1
fence_r:        resd 1
buffer_b:       resd 1
zero:           resd 1
alignb 8
foreign_region: resd 1
foreign_fence:  resd 1
foreign_timeline: resd 1
alignb 8
button_map:     resb 32
output_b:       resq 1
alignb 8
picked:         resq 1
buffer:         resd 1
alignb 16
req:            resb 128
ans:            resb 256
alignb 16
heap:           resb HEAP_SIZE
