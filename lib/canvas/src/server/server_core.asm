; ============================================================================
; Server Core — Startup and Client Requests
; ============================================================================
; server_init wires the subsystems; server_poll is one turn of the event loop:
; each client's waiting requests, up to a fair share, then a frame.
;
; On the wire hdr.obj is the interface (CWP_OBJ_*), hdr.opcode the request's
; index in that interface in its proto/*.cwp file, and handles are in the
; payload. A request's handler is h_<interface>_<request>; the generated
; inc/cwp_dispatch.inc registers each one this file defines, and a request
; without one is refused as an unknown opcode. Handlers run as handler(client*, hdr*, payload, handles) and return
; 0 or a negative error, which becomes an error event; the client stays
; connected. Every handle is checked to belong to the client asking.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"
%include "inc/color.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/cwp_dispatch.inc"
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
extern compositor_layout_bounds
extern compositor_damage_all
extern compositor_damage_surface
extern input_keep_pointer
extern window_output_gone
extern sw_cursor_redraw
extern region_add_rect
extern region_clear
extern ut_mem_free
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
extern window_layer_set_output
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
extern commit_retry
extern fence_create
extern fence_destroy
extern fence_get_status
extern fence_init
extern fence_own
extern fence_reset
extern fence_signal
extern clipboard_data
extern clipboard_init
extern clipboard_offer
extern clipboard_receive
extern clipboard_send_held
extern dnd_start
extern dnd_accept
extern dnd_set_actions
extern dnd_set_icon
extern output_announce
extern output_list
extern seat_watch
extern clamshell_update
extern greeter_lock
extern output_withdraw
extern timeline_create
extern timeline_destroy
extern timeline_get_point
extern timeline_init
extern timeline_own
extern timeline_signal
extern regions_add
extern regions_clear
extern regions_create
extern regions_destroy
extern regions_own
extern regions_subtract
extern surface_set_input_region
extern surface_set_opaque_region
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
    START fence_init
    START timeline_init
    START clipboard_init

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
    mov rdi, rbx                        ; every request it has a handler for
    call server_register_requests
    test rax, rax
    js .out

    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    jmp .out




; ---------------------------------------------------------------------------
; server_add_output
;   Another headless output, of width x height, to the right of the layout
;   (virtual screens, tests), placed by server_place_output
;   IN:  rdi = server*, esi = width, edx = height
;   OUT: rax = Output*, 0 on error
; ---------------------------------------------------------------------------
global server_add_output
server_add_output:
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov ecx, esi
    mov r8d, edx
    mov rdi, [rbx + Server.backend]
    mov esi, ecx
    mov edx, r8d
    mov ecx, DRM_FORMAT_BGRA8888
    call headless_create_virtual_output
    test rax, rax
    jz .out
    mov rdi, rbx
    mov rsi, rax
    call server_place_output
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx

; ---------------------------------------------------------------------------
; server_place_output
;   An output just made, already on the backend's list: to the right of the
;   rest of the layout, at its top, all of it damaged where it now is (the
;   damage it was made with, in its own pixels, goes)
;   IN:  rdi = server*, rsi = Output*
;   OUT: rax = the Output*
; ---------------------------------------------------------------------------
global server_place_output
server_place_output:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 16                         ; a rect; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov qword [r12 + Output.mirror_of], 1   ; out of the bounds while they
    call compositor_layout_bounds           ; are worked out
    mov qword [r12 + Output.mirror_of], 0
    movsxd rcx, ecx
    mov [r12 + Output.x], rcx
    movsxd rdx, edx
    mov [r12 + Output.y], rdx
    mov [rsp], ecx
    mov [rsp + 4], edx
    mov eax, [r12 + Output.width]
    mov [rsp + 8], eax
    mov eax, [r12 + Output.height]
    mov [rsp + 12], eax
    mov rdi, [r12 + Output.damage]
    call region_clear
    mov rdi, [r12 + Output.damage]
    mov rsi, rsp
    call region_add_rect
    mov rdi, rbx                        ; clients watching hear of it
    mov rsi, r12
    call output_announce
    mov rdi, rbx                        ; the lid closed: it takes the
    call clamshell_update               ; built-in panel's place
    mov rax, r12
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; server_remove_output
;   An output taken out of the layout (unplugged, a virtual screen closed):
;   what was on it goes to the first one left (window_output_gone), the
;   pointer is kept on what is left, and every output is redrawn. Its pixels'
;   memory is freed; its record stays, with the server's arena. The last
;   output cannot go.
;   IN:  rdi = server*, rsi = Output*
;   OUT: rax = 0, -ENOENT if it is not in the layout, -EBUSY if it is the
;        last
; ---------------------------------------------------------------------------
global server_remove_output
server_remove_output:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    lea rcx, [rbx + Server.outputs]
.find:
    mov rax, [rcx]
    test rax, rax
    jz .missing
    cmp rax, r12
    je .found
    lea rcx, [rax + Output.next]
    jmp .find
.found:
    cmp qword [rbx + Server.outputs], r12
    jne .unlink
    cmp qword [r12 + Output.next], 0
    je .last
.unlink:
    mov rax, [r12 + Output.next]
    mov [rcx], rax
    mov rdx, [rbx + Server.backend]     ; the backend's list is the same one
    mov rax, [rbx + Server.outputs]
    mov [rdx + Backend.outputs], rax
    dec qword [rdx + Backend.output_count]
    mov rcx, [rbx + Server.outputs]     ; its mirrors show their own part
.mirrors:
    test rcx, rcx
    jz .unmirrored
    cmp [rcx + Output.mirror_of], r12
    jne .next_mirror
    push rcx
    push rcx                            ; 16-byte aligned
    mov rdi, rbx
    mov rsi, rcx
    xor edx, edx
    call server_mirror_output
    pop rcx
    pop rcx
.next_mirror:
    mov rcx, [rcx + Output.next]
    jmp .mirrors
.unmirrored:
    mov rdi, rbx                        ; what was on it, to the first left
    mov rsi, r12
    call first_own_output
    mov rdx, rax
    call window_output_gone
    mov rdi, rbx                        ; clients watching hear it went
    mov rsi, r12
    call output_withdraw
    mov rdi, rbx
    call input_keep_pointer
    mov rdi, rbx
    call compositor_damage_all
    mov rdi, [r12 + Output.fb_region]   ; its pixels, megabytes of them
    test rdi, rdi
    jz .freed
    call ut_mem_free
    mov qword [r12 + Output.fb_region], 0
    mov qword [r12 + Output.framebuffer], 0
.freed:
    mov rdi, [r12 + Output.pixel_region]    ; at a scale, its pixels too
    test rdi, rdi
    jz .no_pixels
    call ut_mem_free
    mov qword [r12 + Output.pixel_region], 0
    mov qword [r12 + Output.pixel_fb], 0
.no_pixels:
    mov rdi, rbx                        ; the lid closed and no screen left
    call clamshell_update               ; on: locked
    test eax, eax
    jnz .done
    cmp qword [rbx + Server.lid_closed], 0
    je .done
    mov rdi, [rbx + Server.greeter]
    test rdi, rdi
    jz .done
    call greeter_lock
.done:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12
.missing:
    mov rax, -(ENOENT)
    jmp .out
.last:
    mov rax, -(EBUSY)
    jmp .out

; rdi = server -> rax = the first output that is no mirror (else the first);
; rdi and rsi kept
first_own_output:
    mov rax, [rdi + Server.outputs]
.next:
    test rax, rax
    jz .any
    cmp qword [rax + Output.mirror_of], 0
    je .done
    mov rax, [rax + Output.next]
    jmp .next
.any:
    mov rax, [rdi + Server.outputs]
.done:
    ret

; ---------------------------------------------------------------------------
; server_mirror_output
;   An output shows another's part of the layout, from its top-left corner
;   and at the same size (no scaling): it goes where that one is, what was
;   on it goes there, and it is no part of the layout of its own. With no
;   source it shows its own part again, to the right of the layout.
;   IN:  rdi = server*, rsi = Output*, rdx = the Output* it shows, 0: none
;   OUT: rax = 0, -EINVAL for itself, or a source that is a mirror itself
; ---------------------------------------------------------------------------
global server_mirror_output
server_mirror_output:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .own
    mov rax, -(EINVAL)
    cmp r13, r12
    je .out
    cmp qword [r13 + Output.mirror_of], 0
    jne .out
    mov rcx, [rbx + Server.outputs]     ; nothing may show it
.mirrored:
    test rcx, rcx
    jz .free
    cmp [rcx + Output.mirror_of], r12
    je .out
    mov rcx, [rcx + Output.next]
    jmp .mirrored
.free:
    mov rdi, rbx                        ; what is on it goes where it will show
    mov rsi, r12
    mov rdx, r13
    call window_output_gone
    mov rdi, rbx                        ; no part of the layout now
    mov rsi, r12
    call output_withdraw
    mov [r12 + Output.mirror_of], r13
    mov rax, [r13 + Output.x]
    mov [r12 + Output.x], rax
    mov rax, [r13 + Output.y]
    mov [r12 + Output.y], rax
    jmp .redraw
.own:
    cmp qword [r12 + Output.mirror_of], 0
    je .done
    mov rdi, rbx                        ; to the right, mirrors aside
    call compositor_layout_bounds
    movsxd rcx, ecx
    mov [r12 + Output.x], rcx
    movsxd rdx, edx
    mov [r12 + Output.y], rdx
    mov qword [r12 + Output.mirror_of], 0
    mov rdi, rbx                        ; part of the layout again
    mov rsi, r12
    call output_announce
.redraw:
    mov rdi, rbx
    call input_keep_pointer
    mov rdi, rbx
    call compositor_damage_all
.done:
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; server_set_high_contrast
;   What the server draws itself (the background, title bars, Alt+Tab) in
;   high contrast (1) or its usual colours (0), every output redrawn
;   IN:  rdi = server*, esi = 1 on, 0 off
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global server_set_high_contrast
server_set_high_contrast:
    and esi, 1
    mov [rdi + Server.high_contrast], rsi
    mov rax, [rdi + Server.compositor]
    test rax, rax
    jz .redraw
    mov dword [rax + Compositor.bg_color], HC_BACKGROUND
    test esi, esi
    jnz .redraw
    mov dword [rax + Compositor.bg_color], COMPOSITOR_BG
.redraw:
    jmp compositor_damage_all

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
    mov rdi, rbx                        ; commits whose fences are now signaled
    call commit_retry
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
%define HAVE_%1                         ; for CWP_REGISTER_ALL
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

; edx = fence handle -> ZF clear if it is 0 or the client's own fence, set if
; it is neither; in a handler
own_fence_or_none:
    test edx, edx
    jz .fine
    sub rsp, 8
    mov rdi, r14
    mov rsi, rbx
    call fence_own
    add rsp, 8
    test rax, rax
    ret
.fine:
    or edx, 1                           ; clears ZF
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
    mov edx, [r13 + 16]                 ; its fences are the client's own
    call own_fence_or_none
    jz .bad_object
    mov edx, [r13 + 20]
    call own_fence_or_none
    jz .bad_object
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

; cw_clipboard.offer(selection, count, types: 4 x 32 bytes)
HANDLER h_clipboard_offer, 8 + CLIP_TYPES * CLIP_TYPE_LEN
    NEEDS_CAP CAP_CLIPBOARD
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r13
    call clipboard_offer
HANDLER_END

; receive(selection, type: 32 bytes) -> (serial); the server's own data
; follows the answer
HANDLER h_clipboard_receive, 4 + CLIP_TYPE_LEN
    NEEDS_CAP CAP_CLIPBOARD
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r13
    call clipboard_receive
    test rax, rax
    js .return
    mov [r13 + 8], edx                  ; 1: the server's own (reply needs r12)
    mov ecx, [r13]                      ; the selection, before the answer
    mov [r13 + 4], ecx
    mov [r13], eax
    mov rdi, r13
    mov esi, 4
    call reply
    cmp dword [r13 + 8], 0
    je .return
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13 + 4]
    mov ecx, [r13]
    call clipboard_send_held
HANDLER_END

; data(serial, done, length, bytes): the owner's, passed on
HANDLER h_clipboard_data, 12
    NEEDS_CAP CAP_CLIPBOARD
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r13
    mov ecx, [r12 + MsgHdr.len]
    call clipboard_data
HANDLER_END

; cw_surface.set_buffer_scale(surface, scale: 120ths; 0 is 120): redrawn
; where it was and where it is at the new size
HANDLER h_surface_set_buffer_scale, 8
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov r12, rax                        ; the header is not needed again
    mov ecx, [r13 + 4]
    cmp ecx, 120 * 8
    ja .bad_object                      ; past 8x: no such buffer
    mov rdi, r14
    mov rsi, r12
    call compositor_damage_surface
    mov ecx, [r13 + 4]
    mov [r12 + Surface.buffer_scale], ecx
    mov rdi, r14
    mov rsi, r12
    call compositor_damage_surface
HANDLER_END

; cw_output.list(): every output, then done; told of changes from now
HANDLER h_output_list, 0
    NEEDS_CAP CAP_OUTPUT
    mov rdi, r14
    mov rsi, rbx
    call output_list
HANDLER_END

; cw_seat.watch(): the switches on, then done; told of switches and
; devices from now
HANDLER h_seat_watch, 0
    NEEDS_CAP CAP_SEAT
    mov rdi, r14
    mov rsi, rbx
    call seat_watch
HANDLER_END

; cw_dnd.start(surface, count, types: 4 x 32 bytes)
HANDLER h_dnd_start, 8 + CLIP_TYPES * CLIP_TYPE_LEN
    NEEDS_CAP CAP_DATA
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rbx
    mov rdx, rax
    mov rcx, r13
    call dnd_start
HANDLER_END

; cw_dnd.set_actions(actions), accept(action): the one dragging, the one
; under the pointer
HANDLER h_dnd_set_actions, 4
    NEEDS_CAP CAP_DATA
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13]
    call dnd_set_actions
HANDLER_END

HANDLER h_dnd_accept, 4
    NEEDS_CAP CAP_DATA
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13]
    call dnd_accept
HANDLER_END

; set_icon(surface): one of the dragging client's own
HANDLER h_dnd_set_icon, 4
    NEEDS_CAP CAP_DATA
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rbx
    mov rdx, rax
    call dnd_set_icon
HANDLER_END

; cw_pointer.set_shape(surface, shape): the pointer's shape over it, redrawn
HANDLER h_pointer_set_shape, 8
    NEEDS_CAP CAP_POINTER
    cmp dword [r13 + 4], 2              ; default, text, crosshair
    ja .bad_object
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov ecx, [r13 + 4]
    mov [rax + Surface.cursor_shape], rcx
    mov rdi, r14
    call sw_cursor_redraw
HANDLER_END

; cw_layer.set_output(surface, output: the nth, 0 the first)
HANDLER h_layer_set_output, 8
    NEEDS_CAP CAP_LAYER
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    mov edx, [r13 + 4]
    call window_layer_set_output
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

; cw_region: create() -> (region)
HANDLER h_region_create, 0
    mov rdi, r14
    mov rsi, rbx
    call regions_create
    test rax, rax
    js .return
    mov [r13], rax
    mov rdi, r13
    mov esi, 4
    call reply
HANDLER_END

; destroy(region)
HANDLER h_region_destroy, 4
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13]
    call regions_destroy
    test rax, rax
    jnz .bad_object
HANDLER_END

; add(region, x, y, width, height), subtract(...), clear(region): the
; client's own region, then rax = it; .bad_object if it is not
%macro OWN_REGION 0
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13]
    call regions_own
    test rax, rax
    jz .bad_object
%endmacro

HANDLER h_region_add, 20
    OWN_REGION
    mov rdi, rax
    lea rsi, [r13 + 4]                  ; x, y, width, height as they came
    call regions_add
HANDLER_END

HANDLER h_region_subtract, 20
    OWN_REGION
    mov rdi, rax
    lea rsi, [r13 + 4]
    call regions_subtract
HANDLER_END

HANDLER h_region_clear, 4
    OWN_REGION
    mov rdi, rax
    call regions_clear
    xor eax, eax
HANDLER_END

; cw_surface: set_opaque_region(surface, region), set_input_region(...);
; region 0 is none. (handler, the setter)
%macro REGION_SETTER 2
HANDLER %1, 8
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov r12, rax                        ; the surface; the header is not
    xor edx, edx                        ; needed again
    cmp dword [r13 + 4], 0
    je .set
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13 + 4]
    call regions_own
    test rax, rax
    jz .bad_object
    mov rdx, rax
.set:
    mov rdi, r14
    mov rsi, r12
    call %2
HANDLER_END
%endmacro
REGION_SETTER h_surface_set_opaque_region, surface_set_opaque_region
REGION_SETTER h_surface_set_input_region, surface_set_input_region

; cw_fence: create(type) -> (fence)
HANDLER h_fence_create, 4
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13]
    call fence_create
    test rax, rax
    js .return
    mov [r13], eax
    mov rdi, r13
    mov esi, 4
    call reply
HANDLER_END

; destroy(fence)
HANDLER h_fence_destroy, 4
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13]
    call fence_destroy
    test rax, rax
    jnz .bad_object
HANDLER_END

; signal(fence), reset(fence), get_status(fence) -> (signaled): the client's
; own fence, then (handler, what is done)
%macro FENCE_HANDLER 2
HANDLER %1, 4
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13]
    call fence_own
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov esi, [r13]
    call %2
%endmacro
FENCE_HANDLER h_fence_signal, fence_signal
HANDLER_END
FENCE_HANDLER h_fence_reset, fence_reset
HANDLER_END
FENCE_HANDLER h_fence_get_status, fence_get_status
    mov [r13], eax
    mov rdi, r13
    mov esi, 4
    call reply
HANDLER_END

; cw_timeline: create() -> (timeline)
HANDLER h_timeline_create, 0
    mov rdi, r14
    mov rsi, rbx
    call timeline_create
    test rax, rax
    js .return
    mov [r13], eax
    mov rdi, r13
    mov esi, 4
    call reply
HANDLER_END

; destroy(timeline)
HANDLER h_timeline_destroy, 4
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13]
    call timeline_destroy
    test rax, rax
    jnz .bad_object
HANDLER_END

; signal(timeline, pad, point: ulong): it reaches the point, if it is not
; past it already
HANDLER h_timeline_signal, 16
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13]
    call timeline_own
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov esi, [r13]
    mov rdx, [r13 + 8]
    call timeline_signal
HANDLER_END

; get_point(timeline) -> (point: ulong)
HANDLER h_timeline_get_point, 4
    mov rdi, r14
    mov rsi, rbx
    mov edx, [r13]
    call timeline_own
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov esi, [r13]
    call timeline_get_point
    mov [r13], rax
    mov rdi, r13
    mov esi, 8
    call reply
HANDLER_END

; cw_buffer.set_timeline(buffer, timeline: handle, acquire_point,
; release_point: ulong): shown once the timeline reaches the acquire point,
; the timeline moved to the release point when it is let go; timeline 0
; takes it off. Both the client's own.
HANDLER h_buffer_set_timeline, 24
    mov esi, [r13]
    call own_buffer
    test rax, rax
    jz .bad_object
    mov r12, rax                        ; the header is not needed again
    mov edx, [r13 + 4]
    test edx, edx
    jz .set
    mov rdi, r14
    mov rsi, rbx
    call timeline_own
    test rax, rax
    jz .bad_object
.set:
    mov ecx, [r13 + 4]
    mov [r12 + Buffer.timeline], rcx
    mov rcx, [r13 + 8]
    mov [r12 + Buffer.acquire_point], rcx
    mov rcx, [r13 + 16]
    mov [r12 + Buffer.release_point], rcx
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
    cmp dword [r13 + 4], 3              ; an overlay: shown, and taking input,
    jne .not_overlay                    ; while the screen is locked
    NEEDS_CAP CAP_OVERLAY
.not_overlay:
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

; cw_popup.destroy(surface) and cw_layer.destroy(surface)
HANDLER h_popup_destroy, 4
    NEEDS_CAP CAP_SHELL
    mov esi, [r13]
    call own_surface
    test rax, rax
    jz .bad_object
    mov rdi, r14
    mov rsi, rax
    call window_destroy
HANDLER_END

HANDLER h_layer_destroy, 4
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

; ---------------------------------------------------------------------------
; server_register_requests
;   Every request this file has a handler for, from inc/cwp_dispatch.inc;
;   here at the end, where each handler's HAVE_ name is defined
;   IN:  rdi = server*
;   OUT: rax = 0, negative error from the dispatcher
; ---------------------------------------------------------------------------
server_register_requests:
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
%macro CWP_REQUEST 3                    ; interface, request, handler
    mov rdi, [rbx + Server.dispatch]
    mov esi, %1
    mov edx, %2
    lea rcx, [rel %3]
    call dispatch_register
    test rax, rax
    js .out
%endmacro
    CWP_REGISTER_ALL
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx


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
