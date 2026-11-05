; ============================================================================
; Server Core — Startup and Client Requests
; ============================================================================
; server_init wires the subsystems; server_poll is one turn of the event loop:
; each client's waiting requests, up to a fair share, then a frame.
;
; On the wire hdr.obj is the interface (CWP_OBJ_*), hdr.opcode the request's
; index in that interface in proto/canvas-core.cwp, and handles are in the
; payload. Handlers run as handler(client*, hdr*, payload, handles) and return
; 0 or a negative error, which becomes an error event; the client stays
; connected. Every handle is checked to belong to the client asking.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"
%include "inc/color.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/channel.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern buffer_create
extern buffer_destroy
extern buffer_init
extern client_init
extern commit_surface
extern compositor_add_surface
extern compositor_composite
extern compositor_init
extern dispatch_call
extern dispatch_init
extern dispatch_register
extern errors_from_errno
extern errors_send
extern fb_linear_create_output
extern fb_linear_init
extern handle_resolve
extern headless_create_virtual_output
extern headless_init
extern input_dispatch
extern window_ack_configure
extern window_create
extern window_destroy
extern window_fullscreen
extern window_maximize
extern window_minimize
extern window_set_decorated
extern window_activate
extern window_close
extern window_layer_exclusive
extern window_list_find
extern window_list_subscribe
extern window_move_to_workspace
extern window_switch_workspace
extern window_layer_create
extern window_popup_create
extern window_set_name
extern input_init
extern msgbuf_read
extern msgbuf_write
extern presentation_init
extern regions_init
extern str_len
extern surface_attach
extern surface_create
extern surface_damage
extern surface_destroy
extern surface_init
extern surface_frame_callback
extern ut_time_now_ns

%define MESSAGES_PER_TURN   64          ; a client's share of one turn

section .text

; ---------------------------------------------------------------------------
; server_init
;   Start a server: subsystems, a headless output, compositor, request table
;   IN:  rdi = server*, rsi = arena*, rdx = output width, rcx = output height,
;        r8 = Config* of a linear framebuffer, whose size then replaces rdx and
;        rcx (0: headless)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global server_init
server_init:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    xor eax, eax
    mov ecx, Server_size
    rep stosb
    mov [rbx + Server.arena], r12

%macro START 1                          ; %1(server, arena); stop on an error
    mov rdi, rbx
    mov rsi, r12
    call %1
    test rax, rax
    js .out
%endmacro
    START client_init
    call presentation_init
    START surface_init
    START buffer_init
    START regions_init

    ; Backend and its output
    mov rdi, r12
    mov esi, Backend_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Server.backend], rax
    mov [rax + Backend.arena], r12
    mov [rax + Backend.server], rbx
    mov rdi, rax
    test r15, r15
    jnz .framebuffer
    lea rsi, [rel server_config]
    call headless_init
    test rax, rax
    js .out
    mov rdi, [rbx + Server.backend]
    mov rsi, r13
    mov rdx, r14
    mov ecx, DRM_FORMAT_BGRA8888
    call headless_create_virtual_output
    jmp .output_made
.framebuffer:
    mov rsi, r15
    call fb_linear_init
    test rax, rax
    js .out
    mov rdi, [rbx + Server.backend]
    call fb_linear_create_output
.output_made:
    test rax, rax
    jz .oom

    ; Compositor
    mov rdi, r12
    mov esi, Compositor_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Server.compositor], rax
    mov rdi, rax
    xor eax, eax
    mov ecx, Compositor_size
    rep stosb
    mov rdi, [rbx + Server.compositor]
    mov rsi, rbx
    mov rdx, r12
    call compositor_init
    test rax, rax
    js .out

    ; Input, after the output its pointer starts on
    START input_init

    ; Requests
    mov rdi, r12
    mov esi, 64
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Server.dispatch], rax
    mov rdi, rax
    mov rsi, r12
    call dispatch_init
%macro REQUEST 3                        ; interface, opcode, handler
    mov rdi, [rbx + Server.dispatch]
    mov esi, %1
    mov edx, %2
    lea rcx, [rel %3]
    call dispatch_register
    test rax, rax
    js .out
%endmacro
    REQUEST CWP_OBJ_DISPLAY, DISPLAY_SYNC, h_display_sync
    REQUEST CWP_OBJ_DISPLAY, DISPLAY_GET_VERSION, h_display_get_version
    REQUEST CWP_OBJ_BUFFER, BUFFER_CREATE, h_buffer_create
    REQUEST CWP_OBJ_BUFFER, BUFFER_DESTROY, h_buffer_destroy
    REQUEST CWP_OBJ_SURFACE, SURFACE_CREATE, h_surface_create
    REQUEST CWP_OBJ_SURFACE, SURFACE_DESTROY, h_surface_destroy
    REQUEST CWP_OBJ_SURFACE, SURFACE_ATTACH, h_surface_attach
    REQUEST CWP_OBJ_SURFACE, SURFACE_DAMAGE, h_surface_damage
    REQUEST CWP_OBJ_SURFACE, SURFACE_FRAME_CALLBACK, h_surface_frame_callback
    REQUEST CWP_OBJ_SURFACE, SURFACE_COMMIT, h_surface_commit
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_CREATE, h_toplevel_create
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_DESTROY, h_toplevel_destroy
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_SET_TITLE, h_toplevel_set_title
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_SET_APP_ID, h_toplevel_set_app_id
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_ACK_CONFIGURE, h_toplevel_ack_configure
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_SET_MAXIMIZED, h_toplevel_set_maximized
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_UNSET_MAXIMIZED, h_toplevel_unset_maximized
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_SET_FULLSCREEN, h_toplevel_set_fullscreen
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_UNSET_FULLSCREEN, h_toplevel_unset_fullscreen
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_SET_MINIMIZED, h_toplevel_set_minimized
    REQUEST CWP_OBJ_TOPLEVEL, TOPLEVEL_SET_DECORATED, h_toplevel_set_decorated
    REQUEST CWP_OBJ_POPUP, POPUP_CREATE, h_popup_create
    REQUEST CWP_OBJ_POPUP, POPUP_DESTROY, h_role_destroy_shell
    REQUEST CWP_OBJ_LAYER, LAYER_CREATE, h_layer_create
    REQUEST CWP_OBJ_LAYER, LAYER_DESTROY, h_role_destroy_layer
    REQUEST CWP_OBJ_LAYER, LAYER_SET_EXCLUSIVE, h_layer_set_exclusive
    REQUEST CWP_OBJ_WINDOW_LIST, WINDOW_LIST_SUBSCRIBE, h_window_list_subscribe
    REQUEST CWP_OBJ_WINDOW_LIST, WINDOW_LIST_ACTIVATE, h_window_list_activate
    REQUEST CWP_OBJ_WINDOW_LIST, WINDOW_LIST_CLOSE, h_window_list_close
    REQUEST CWP_OBJ_WINDOW_LIST, WINDOW_LIST_MINIMIZE, h_window_list_minimize
    REQUEST CWP_OBJ_WINDOW_LIST, WINDOW_LIST_SET_MAXIMIZED, h_window_list_set_maximized
    REQUEST CWP_OBJ_WINDOW_LIST, WINDOW_LIST_SET_WORKSPACE, h_window_list_set_workspace
    REQUEST CWP_OBJ_WINDOW_LIST, WINDOW_LIST_MOVE_TO_WORKSPACE, h_window_list_move_to_workspace

    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    jmp .out




; ---------------------------------------------------------------------------
; server_poll
;   One turn: queued input, every client's requests up to its share, then a
;   frame
;   IN:  rdi = server*
;   OUT: rax = requests handled, negative error from the compositor
; ---------------------------------------------------------------------------
global server_poll
server_poll:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, MsgHdr_size + 12            ; the header; 16-byte aligned
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rdi, rbx
    call input_dispatch
    xor r13d, r13d                      ; handled
    mov r12, [rbx + Server.client_list]
.client:
    test r12, r12
    jz .frame
    mov r14d, MESSAGES_PER_TURN
.message:
    mov rdi, [r12 + Client.tx_ring]
    mov rsi, rsp
    lea rdx, [rel request_payload]
    mov ecx, MAX_PAYLOAD_SIZE
    call msgbuf_read
    test rax, rax
    js .next_client
    inc r13
    mov rdi, [rbx + Server.dispatch]
    mov esi, [rsp + MsgHdr.obj]
    movzx edx, word [rsp + MsgHdr.opcode]
    mov rcx, r12
    mov r8, rsp
    lea r9, [rel request_payload]
    xor r10d, r10d
    call dispatch_call
    test rax, rax
    jns .handled
    mov rdi, r12
    mov rsi, rax
    call server_report_error
.handled:
    dec r14d
    jnz .message
.next_client:
    mov r12, [r12 + Client.next_client]
    jmp .client
.frame:
    mov rdi, [rbx + Server.compositor]
    call compositor_composite
    test rax, rax
    js .out
    mov rax, r13
.out:
    add rsp, MsgHdr_size + 12
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; server_report_error
;   Send a client an error event
;   IN:  rdi = client*, rsi = negative error
; ---------------------------------------------------------------------------
server_report_error:
    PROLOGUE_SAVE rbx
    sub rsp, 24 + 16                    ; { code, message, length }
    mov rbx, rdi
    mov rdi, rsi
    neg rdi
    mov rax, rdi
    cmp rdi, ECWP_VERSION               ; protocol codes go through as they are
    jae .code
    call errors_from_errno
.code:
    mov [rsp], eax
    mov dword [rsp + 4], 0
    lea rax, [rel s_refused]
    mov [rsp + 8], rax
    mov qword [rsp + 16], s_refused_len
    mov rdi, rbx
    mov rsi, rsp
    call errors_send
    add rsp, 24 + 16
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; Handlers: rbx = client, r12 = hdr, r13 = payload, r14 = server
; ---------------------------------------------------------------------------
%macro HANDLER 2                        ; name, least payload bytes
%1:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [rbx + Client.server]
    mov rax, -(ECWP_PAYLOAD)
    cmp dword [r12 + MsgHdr.len], %2
    jb .return
%endmacro
%macro HANDLER_END 0
.return:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.denied:
    mov rax, -(ECWP_CAP)
    jmp .return
.bad_object:
    mov rax, -(ECWP_OBJECT)
    jmp .return
%endmacro
%macro NEEDS_CAP 1
    test qword [rbx + Client.caps], %1
    jz .denied
%endmacro

; rsi = handle -> rax = the client's own surface or buffer, 0 if not its own
own_surface:
    sub rsp, 8
    mov rdi, [r14 + Server.surface_table]
    call handle_resolve
    add rsp, 8
    test rax, rax
    jz .done
    cmp [rax + Surface.client], rbx
    je .done
    xor eax, eax
.done:
    ret

own_buffer:
    sub rsp, 8
    mov rdi, [r14 + Server.buffer_table]
    call handle_resolve
    add rsp, 8
    test rax, rax
    jz .done
    cmp [rax + Buffer.client], rbx
    je .done
    xor eax, eax
.done:
    ret

; Answer a request: rdi = payload, esi = bytes -> rax = 0, or the ring's error
reply:
    sub rsp, MsgHdr_size + 12
    mov rdx, rdi
    mov eax, [r12 + MsgHdr.obj]
    mov [rsp + MsgHdr.obj], eax
    mov ax, [r12 + MsgHdr.opcode]
    mov [rsp + MsgHdr.opcode], ax
    mov word [rsp + MsgHdr.flags], CWP_MSG_FLAG_IS_EVENT | CWP_MSG_FLAG_REPLY
    mov [rsp + MsgHdr.len], esi
    mov rdi, [rbx + Client.rx_ring]
    mov rsi, rsp
    call msgbuf_write
    add rsp, MsgHdr_size + 12
    ret

; sync() -> (serial: ulong)
HANDLER h_display_sync, 0
    inc qword [rbx + Client.ping_serial]
    lea rdi, [rbx + Client.ping_serial]
    mov esi, 8
    call reply
HANDLER_END

; get_version() -> (major, minor, patch: uint)
HANDLER h_display_get_version, 0
    lea rdi, [rel s_version]
    mov esi, 12
    call reply
HANDLER_END

; create(params) -> (buffer: handle, pad, base: pointer). The base stands in
; for sharing the pixels until handles pass between tasks (KRN-04).
HANDLER h_buffer_create, 24
    NEEDS_CAP CAP_BUFFER
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r13
    xor ecx, ecx
    call buffer_create
    test rax, rax
    js .return
    mov rsi, rax
    mov [r13], rax                      ; the payload is the server's to reuse
    call own_buffer
    mov rax, [rax + Buffer.base]
    mov [r13 + 8], rax
    mov rdi, r13
    mov esi, 16
    call reply
HANDLER_END

; destroy(buffer: handle)
HANDLER h_buffer_destroy, 4
    mov esi, [r13]
    call own_buffer
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov esi, [r13]
    call buffer_destroy
HANDLER_END

; create() -> (surface: handle)
HANDLER h_surface_create, 0
    NEEDS_CAP CAP_SURFACE
    mov rdi, r14
    mov rsi, rbx
    xor edx, edx
    call surface_create
    test rax, rax
    js .return
    mov [r13], rax
    mov rsi, rax
    call own_surface
    mov rdi, [r14 + Server.outputs]
    mov rsi, rax
    call compositor_add_surface
    mov rdi, r13
    mov esi, 4
    call reply
HANDLER_END

; destroy(surface: handle)
HANDLER h_surface_destroy, 4
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov esi, [r13]
    call surface_destroy
HANDLER_END

; attach(surface, buffer: handle, x, y: int, acquire, release: handle)
HANDLER h_surface_attach, 24
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov r12, rax                        ; surface*; no reply here
    mov esi, [r13 + 4]
    test esi, esi
    jz .attach                          ; 0: detach
    call own_buffer
    test rax, rax
    jz .bad_object
    mov qword [rax + Buffer.state], 2   ; attached
    mov ecx, [r13 + 16]
    mov [rax + Buffer.acquire_fence], rcx
    mov ecx, [r13 + 20]
    mov [rax + Buffer.release_fence], rcx
.attach:
    mov rdi, r14
    mov rsi, r12
    mov edx, [r13 + 4]
    mov ecx, [r13 + 8]
    mov r8d, [r13 + 12]
    call surface_attach
HANDLER_END

; damage(surface: handle, x, y: int, width, height: uint)
HANDLER h_surface_damage, 20
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    mov edx, [r13 + 4]
    mov ecx, [r13 + 8]
    mov r8d, [r13 + 12]
    mov r9d, [r13 + 16]
    call surface_damage
HANDLER_END

; frame_callback(surface: handle) -> (callback: handle)
HANDLER h_surface_frame_callback, 4
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rsi, rax
    inc qword [rbx + Client.next_obj]
    mov rcx, [rbx + Client.next_obj]
    mov rdi, r14
    lea rdx, [rel server_frame_done]
    call surface_frame_callback
    test rax, rax
    js .return
    lea rdi, [rbx + Client.next_obj]
    mov esi, 4
    call reply
HANDLER_END

; commit(surface: handle, flags: uint)
HANDLER h_surface_commit, 8
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    mov edx, [r13 + 4]
    call commit_surface
HANDLER_END

; create(surface)
HANDLER h_toplevel_create, 4
    NEEDS_CAP CAP_SHELL
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    call window_create
HANDLER_END

; destroy(surface)
HANDLER h_toplevel_destroy, 4
    NEEDS_CAP CAP_SHELL
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    call window_destroy
HANDLER_END

; set_title(surface, title: string)
HANDLER h_toplevel_set_title, 8
    NEEDS_CAP CAP_SHELL
    xor edx, edx
    call name_request
HANDLER_END

; set_app_id(surface, app_id: string)
HANDLER h_toplevel_set_app_id, 8
    NEEDS_CAP CAP_SHELL
    mov edx, 1
    call name_request
HANDLER_END

; ack_configure(surface, serial)
HANDLER h_toplevel_ack_configure, 8
    NEEDS_CAP CAP_SHELL
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, rax
    mov esi, [r13 + 4]
    call window_ack_configure
HANDLER_END

; set_maximized(surface) and the like: (handler, function, 1 set / 0 clear)
%macro STATE_HANDLER 3
HANDLER %1, 4
    NEEDS_CAP CAP_SHELL
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    mov edx, %3
    call %2
HANDLER_END
%endmacro
STATE_HANDLER h_toplevel_set_maximized, window_maximize, 1
STATE_HANDLER h_toplevel_unset_maximized, window_maximize, 0
STATE_HANDLER h_toplevel_set_fullscreen, window_fullscreen, 1
STATE_HANDLER h_toplevel_unset_fullscreen, window_fullscreen, 0
STATE_HANDLER h_toplevel_set_minimized, window_minimize, 0

; cw_layer.set_exclusive(surface, size)
HANDLER h_layer_set_exclusive, 8
    NEEDS_CAP CAP_LAYER
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    mov edx, [r13 + 4]
    call window_layer_exclusive
HANDLER_END

; cw_window_list.subscribe()
HANDLER h_window_list_subscribe, 0
    NEEDS_CAP CAP_WINDOWS
    mov rdi, r14
    mov rsi, rbx
    call window_list_subscribe
HANDLER_END

; cw_window_list requests on a window by id: (handler, least bytes); the
; body runs with rax = its surface
%macro WINDOW_LIST_HANDLER 2
HANDLER %1, %2
    NEEDS_CAP CAP_WINDOWS
    mov rdi, r14
    mov esi, [r13]
    call window_list_find
    test rax, rax
    jz .bad_object
%endmacro

; activate(id)
WINDOW_LIST_HANDLER h_window_list_activate, 4
    mov rdi, r14
    mov rsi, rax
    call window_activate
HANDLER_END

; close(id)
WINDOW_LIST_HANDLER h_window_list_close, 4
    mov rdi, rax
    call window_close
    xor eax, eax
HANDLER_END

; minimize(id)
WINDOW_LIST_HANDLER h_window_list_minimize, 4
    mov rdi, r14
    mov rsi, rax
    call window_minimize
HANDLER_END

; set_maximized(id, maximized)
WINDOW_LIST_HANDLER h_window_list_set_maximized, 8
    mov rdi, r14
    mov rsi, rax
    xor edx, edx
    cmp dword [r13 + 4], 0
    setne dl
    call window_maximize
HANDLER_END

; set_workspace(index)
HANDLER h_window_list_set_workspace, 4
    NEEDS_CAP CAP_WINDOWS
    mov rdi, r14
    mov esi, [r13]
    call window_switch_workspace
HANDLER_END

; move_to_workspace(id, index)
WINDOW_LIST_HANDLER h_window_list_move_to_workspace, 8
    mov rdi, r14
    mov rsi, rax
    mov edx, [r13 + 4]
    call window_move_to_workspace
HANDLER_END

; set_decorated(surface, decorated)
HANDLER h_toplevel_set_decorated, 8
    NEEDS_CAP CAP_SHELL
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    mov edx, [r13 + 4]
    call window_set_decorated
HANDLER_END

; cw_popup.create(surface, parent, x, y)
HANDLER h_popup_create, 16
    NEEDS_CAP CAP_SHELL
    mov esi, [r13 + 4]
    call own_surface
    test rax, rax
    jz .bad_object
    push rax
    push rax                            ; 16-byte aligned
    mov esi, [r13]
    call own_surface
    pop rdx
    pop rdx
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    mov ecx, [r13 + 8]
    mov r8d, [r13 + 12]
    call window_popup_create
HANDLER_END

; cw_layer.create(surface, layer, anchor, margin)
HANDLER h_layer_create, 16
    NEEDS_CAP CAP_LAYER
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    mov edx, [r13 + 4]
    mov ecx, [r13 + 8]
    mov r8d, [r13 + 12]
    call window_layer_create
HANDLER_END

; cw_popup.destroy(surface), cw_layer.destroy(surface)
HANDLER h_role_destroy_shell, 4
    NEEDS_CAP CAP_SHELL
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    call window_destroy
HANDLER_END

HANDLER h_role_destroy_layer, 4
    NEEDS_CAP CAP_LAYER
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    call window_destroy
HANDLER_END

; A window's name from a (surface, length, bytes) payload; in a handler.
; edx = 0 title, 1 app id -> rax
name_request:
    push r15
    mov r15d, edx
    mov eax, [r13 + 4]                  ; the bytes must all be there
    add rax, 8
    mov edx, [r12 + MsgHdr.len]
    cmp rax, rdx
    ja .short
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .not_own
    mov rdi, rax
    mov esi, r15d
    lea rdx, [r13 + 8]
    mov ecx, [r13 + 4]
    call window_set_name
    pop r15
    ret
.short:
    mov rax, -(ECWP_PAYLOAD)
    pop r15
    ret
.not_own:
    mov rax, -(ECWP_OBJECT)
    pop r15
    ret

; ---------------------------------------------------------------------------
; server_frame_done
;   A frame callback: the event frame_done(surface, callback, time, flags)
;   IN:  rdi = surface*, rsi = callback id, rdx = frame sequence
; ---------------------------------------------------------------------------
server_frame_done:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 32 + 16                    ; header, payload
    mov rbx, rdi
    mov r12, rsi
    call ut_time_now_ns
    mov ecx, [rbx + Surface.id]
    mov [rsp + 16], ecx
    mov [rsp + 20], r12d
    mov [rsp + 24], rax
    mov dword [rsp + 32], 0
    mov dword [rsp + MsgHdr.obj], CWP_OBJ_SURFACE
    mov word [rsp + MsgHdr.opcode], SURFACE_EV_FRAME_DONE
    mov word [rsp + MsgHdr.flags], CWP_MSG_FLAG_IS_EVENT
    mov dword [rsp + MsgHdr.len], 20
    mov rax, [rbx + Surface.client]
    mov rdi, [rax + Client.rx_ring]
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call msgbuf_write
    add rsp, 32 + 16
    EPILOGUE_RESTORE rbx, r12
    ret

section .rodata
s_refused:      db "request refused"
s_refused_len   equ $ - s_refused
alignb 4
s_version:      dd CWP_VERSION_MAJOR, CWP_VERSION_MINOR, 0

section .bss
alignb 16
request_payload:    resb MAX_PAYLOAD_SIZE
server_config:      resq 8

section .data
global server_core_version
server_core_version: dq 0x010000
