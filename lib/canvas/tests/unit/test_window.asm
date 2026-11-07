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
extern scale_fractional_calculate_dest
extern scale_fractional_render
extern displays_step
extern host_display_report
extern host_fb1
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
    or ebx, CAP_POINTER | CAP_KEYBOARD | CAP_TOUCH
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

; edi = type, esi = framebuffer index: reported, then acted on
%macro DISPLAY 2
    mov edi, %1
    mov esi, %2
    call host_display_report
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
    lea rcx, [rel host_fb1]
    cmp [rax + Output.scanout], rcx
    jne .fail
    call poll                           ; drawn, and shown there
    mov eax, [rel fb0]                  ; the background, as on the first
    test eax, eax
    jz .fail
    cmp [rel host_fb1], eax
    jne .fail
    cmp [rel host_fb1 + (23 * 40 + 31) * 4], eax
    jne .fail
    cmp dword [rel host_fb1 + 32 * 4], 0
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
corner_src:     dd 0xFF000000, 0xFF000000   ; 2 x 2, the bottom left white
                dd 0xFFFFFFFF, 0xFF000000

section .bss
alignb 16
server:         resb Server_size
scale_dst:      resd 16                 ; 4 x 4
fb0:            resd 64 * 48            ; tw_displays' boot framebuffer
fb0_conf:       resb Config_size
fr_ctx:         resb FrameCtx_size
scaled_size:    resd 2
scale_job:      resb UgfxScale_SIZE
arena:          resb Arena_size
pair:           resb ChannelPair_size
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
output_b:       resq 1
alignb 8
picked:         resq 1
buffer:         resd 1
alignb 16
req:            resb 128
ans:            resb 256
alignb 16
heap:           resb HEAP_SIZE
