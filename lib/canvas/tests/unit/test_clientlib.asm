; ============================================================================
; Unit Test — the Client Library against the Server (src/client/*)
; ============================================================================
; test_clientlib_suite -> eax = failed cases (each case returns 0 / 1).
; A server on 64x48 in this process; the library connects over the channel
; pair client_accept makes, with server_poll as its pump, so a call that
; waits for a reply turns the server.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"
%include "inc/color.inc"
%include "inc/event.inc"
%include "inc/backend.inc"
%include "inc/canvas_client.inc"

extern arena_init
extern canvas_buffer_create
extern canvas_buffer_destroy
extern canvas_buffer_mmap
extern canvas_buffer_stride
extern canvas_connect_pair
extern canvas_event_poll
extern canvas_frame_request
extern canvas_get_caps
extern canvas_surface_attach
extern canvas_surface_commit
extern canvas_surface_create
extern canvas_surface_damage
extern canvas_toplevel_ack_configure
extern canvas_toplevel_create
extern canvas_toplevel_set_title
extern canvas_fence_create
extern canvas_fence_wait
extern canvas_timeline_create
extern canvas_timeline_signal
extern canvas_timeline_wait
extern fence_signal
extern timeline_signal
extern client_accept
extern service_start
extern canvas_connect_with
extern canvas_disconnect
extern handle_resolve
extern server_init
extern server_poll
extern virtual_input_inject

%define HEAP_SIZE (2 * 1024 * 1024)

section .text

global test_clientlib_suite
test_clientlib_suite:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tc_connect
    CASE tc_wake
    CASE tc_service
    CASE tc_window
    CASE tc_refused
    CASE tc_buffers
    CASE tc_sync
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

; the next event of type %1 into [event], skipping others; .fail if none
%macro EXPECT 1
    mov esi, %1
    call find_event
    test eax, eax
    jz .fail
%endmacro

; a started server and a connection with the shell capability
fresh:
    sub rsp, 8
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
    mov edx, CLIENT_CAP_SHELL | CLIENT_CAP_POINTER | CLIENT_CAP_KEYBOARD
    call client_accept
    lea rdi, [rel pair]
    lea rsi, [rel server_poll]
    lea rdx, [rel server]
    call canvas_connect_pair
    mov [rel conn], rax
    add rsp, 8
    ret

poll:
    sub rsp, 8
    lea rdi, [rel server]
    call server_poll
    add rsp, 8
    ret

; A pump that turns the server, then once signals what is pending, as if
; another client did it meanwhile: pending_fence, or pending_timeline to
; pending_point. rdi = server
signal_pump:
    push rbx
    mov rbx, rdi
    call server_poll
    mov esi, [rel pending_fence]
    test esi, esi
    jz .timeline
    mov dword [rel pending_fence], 0
    mov rdi, rbx
    call fence_signal
.timeline:
    mov esi, [rel pending_timeline]
    test esi, esi
    jz .out
    mov dword [rel pending_timeline], 0
    mov rdi, rbx
    mov rdx, [rel pending_point]
    call timeline_signal
.out:
    pop rbx
    ret

; esi = type -> eax = 1 with that event in [event], 0 if none came
find_event:
    push rbx
    mov ebx, esi
.next:
    mov rdi, [rel conn]
    lea rsi, [rel event]
    call canvas_event_poll
    test eax, eax
    jz .out
    cmp [rel event + ClientEvent.type], ebx
    jne .next
    mov eax, 1
.out:
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

; ---------------------------------------------------------------------------
; Cases
; ---------------------------------------------------------------------------

; Connected, and the grant noted once its event is read
; A client's send wakes the server's loop: a client accepted while the loop's
; task is known (7, made up) has it in its pair, and each send wakes it; one
; accepted while it is not wakes nothing
tc_wake:
    sub rsp, 8
    mov rdi, [rel conn]                 ; no task known: nothing woken
    call canvas_timeline_create
    cmp qword [rel pair + ChannelPair.wakes], 0
    jne .fail
    mov qword [rel server + Server.loop_task], 7
    mov qword [rel pair_woken + ChannelPair.region], 0x5A5A
    lea rdi, [rel server]
    lea rsi, [rel pair_woken]
    mov edx, CLIENT_CAP_SHELL
    call client_accept
    cmp qword [rel pair_woken + ChannelPair.wake_task], 7
    jne .fail
    cmp qword [rel pair_woken + ChannelPair.region], 0x5A5A
    jne .fail                           ; the caller's own, kept (regression)
    mov qword [rel pair_woken + ChannelPair.region], 0
    lea rdi, [rel pair_woken]
    lea rsi, [rel server_poll]
    lea rdx, [rel server]
    call canvas_connect_pair
    test rax, rax
    jz .fail
    mov rdi, rax
    call canvas_timeline_create
    cmp qword [rel pair_woken + ChannelPair.wakes], 1
    jb .fail
    mov qword [rel server + Server.loop_task], 0
    PASS

; Another program's way in: the server published (service_start), a client
; finds it by name and connects (canvas_connect_with, the server's turns as
; its pump), then a request goes round over the pair it made; it
; disconnects
tc_service:
    sub rsp, 8
    lea rdi, [rel server]
    call service_start
    test rax, rax
    jnz .fail
    mov edi, CLIENT_CAP_SHELL
    lea rsi, [rel server_poll]
    lea rdx, [rel server]
    call canvas_connect_with
    test rax, rax
    jz .fail
    mov [rel conn_service], rax
    mov rcx, [rax + ClientConn.server_chan] ; the accept kept the pair's own
    cmp qword [rcx + ChannelPair.region], 0 ; memory (regression: it once
    je .fail                                ; overwrote it)
    cmp qword [rcx + ChannelPair.state], 1
    jne .fail
    mov rdi, rax
    call canvas_timeline_create
    test eax, eax
    jle .fail
    mov rdi, [rel conn_service]
    call canvas_disconnect
    PASS

tc_connect:
    sub rsp, 8
    cmp qword [rel conn], 0
    je .fail
    EXPECT CANVAS_EV_CAPS
    mov rdi, [rel conn]
    call canvas_get_caps
    test eax, CAP_SHELL
    jz .fail
    test eax, CAP_SURFACE
    jz .fail
    PASS

; A buffer, a surface, a window: configured, named, placed, focused, typed in
tc_window:
    sub rsp, 8
    mov rdi, [rel conn]
    mov esi, 16
    mov edx, 12
    mov ecx, DRM_FORMAT_BGRA8888
    call canvas_buffer_create
    test eax, eax
    jle .fail
    mov [rel buffer_a], eax
    mov rdi, [rel conn]
    mov esi, eax
    call canvas_buffer_stride
    cmp eax, 64
    jne .fail
    mov rdi, [rel conn]
    mov esi, [rel buffer_a]
    call canvas_buffer_mmap
    test rax, rax
    jz .fail
    mov dword [rax], 0xFF336699         ; the pixels are the server's
    mov rdi, [rel conn]
    call canvas_surface_create
    test eax, eax
    jle .fail
    mov [rel surface_a], eax

    mov rdi, [rel conn]
    mov esi, [rel surface_a]
    call canvas_toplevel_create
    mov rdi, [rel conn]
    mov esi, [rel surface_a]
    lea rdx, [rel s_title]
    mov ecx, 2
    call canvas_toplevel_set_title
    mov rdi, [rel conn]
    mov esi, [rel surface_a]
    mov edx, [rel buffer_a]
    xor ecx, ecx
    xor r8d, r8d
    call canvas_surface_attach
    mov rdi, [rel conn]
    mov esi, [rel surface_a]
    xor edx, edx
    xor ecx, ecx
    mov r8d, 16
    mov r9d, 12
    call canvas_surface_damage
    mov rdi, [rel conn]
    mov esi, [rel surface_a]
    xor edx, edx
    call canvas_surface_commit
    call poll

    EXPECT CANVAS_EV_CONFIGURE
    mov eax, [rel surface_a]
    cmp [rel event + ClientEvent.data], eax
    jne .fail
    cmp dword [rel event + ClientEvent.data + 4], 1
    jne .fail
    mov rdi, [rel conn]
    mov esi, [rel surface_a]
    mov edx, 1
    call canvas_toplevel_ack_configure
    EXPECT CANVAS_EV_KEY_ENTER          ; shown, so it has the keyboard
    call poll

    mov edi, [rel surface_a]
    call surface_of
    test rax, rax
    jz .fail
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 32
    jne .fail                           ; at the pointer, mid-output
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 24
    jne .fail
    mov rax, [rax + Surface.window]
    test rax, rax
    jz .fail
    cmp word [rax + Window.title], 'Hi'
    jne .fail
    cmp dword [rax + Window.acked], 1
    jne .fail

    lea rdi, [rel server]
    mov esi, INPUT_KEY
    mov edx, 30
    mov ecx, 1
    xor r8d, r8d
    call virtual_input_inject
    call poll
    EXPECT CANVAS_EV_KEY
    cmp dword [rel event + ClientEvent.data + 12], 30
    jne .fail
    EXPECT CANVAS_EV_TEXT
    cmp dword [rel event + ClientEvent.data + 12], 'a'
    jne .fail
    PASS

; A call the server refuses ends with its error, not a wait
tc_refused:
    sub rsp, 8
    mov rdi, [rel conn]
    mov esi, 999                        ; no such surface
    call canvas_frame_request
    cmp rax, -(ECWP_OBJECT)
    jne .fail
    PASS

; The buffer table: three made, the middle one gone, an unknown refused
tc_buffers:
    push rbx
    sub rsp, 16
    xor ebx, ebx
.make:
    mov rdi, [rel conn]
    mov esi, 4
    mov edx, 4
    mov ecx, DRM_FORMAT_BGRA8888
    call canvas_buffer_create
    test eax, eax
    jle .bad
    mov [rsp + rbx * 4], eax
    inc ebx
    cmp ebx, 3
    jb .make
    mov rdi, [rel conn]
    mov esi, [rsp + 4]
    call canvas_buffer_destroy
    test rax, rax
    jnz .bad
    mov rdi, [rel conn]
    mov esi, [rsp + 4]
    call canvas_buffer_mmap
    test rax, rax
    jnz .bad
    mov rdi, [rel conn]
    mov esi, [rsp]
    call canvas_buffer_mmap
    test rax, rax
    jz .bad
    mov rdi, [rel conn]
    mov esi, [rsp + 8]
    call canvas_buffer_mmap
    test rax, rax
    jz .bad
    mov rdi, [rel conn]
    mov esi, [rsp + 4]
    call canvas_buffer_destroy
    cmp rax, -(ENOENT)
    jne .bad
    xor eax, eax
    jmp .out
.bad:
    mov eax, 1
.out:
    add rsp, 16
    pop rbx
    ret

section .rodata
s_title:        db "Hi"

section .text

; Waiting: no time given, a timeline short of the point times out; at the
; point already, the server's answer is enough; a fence and a timeline
; signaled while the wait turns the pump are seen by their events, and the
; fence's event is still there for canvas_event_poll
tc_sync:
    sub rsp, 8
    mov rdi, [rel conn]
    call canvas_timeline_create
    test eax, eax
    jle .fail
    mov [rel timeline], eax
    mov rdi, [rel conn]
    mov esi, [rel timeline]
    mov edx, 1
    xor ecx, ecx
    call canvas_timeline_wait
    cmp rax, -(ETIMEDOUT)
    jne .fail
    mov rdi, [rel conn]
    mov esi, [rel timeline]
    mov edx, 3
    call canvas_timeline_signal
    mov rdi, [rel conn]
    mov esi, [rel timeline]
    mov edx, 2
    mov rcx, -1
    call canvas_timeline_wait
    test rax, rax
    jnz .fail

    mov rdi, [rel conn]                 ; by its event
    xor esi, esi
    call canvas_fence_create
    test eax, eax
    jle .fail
    mov [rel fence], eax
    mov rax, [rel conn]
    lea rcx, [rel signal_pump]
    mov [rax + CLIENT_WIRE + ClientWire.pump], rcx
    mov ecx, [rel fence]
    mov [rel pending_fence], ecx
    mov rdi, [rel conn]
    mov esi, [rel fence]
    mov rdx, -1
    call canvas_fence_wait
    test rax, rax
    jnz .fail
    mov eax, [rel timeline]
    mov [rel pending_timeline], eax
    mov qword [rel pending_point], 9
    mov rdi, [rel conn]
    mov esi, [rel timeline]
    mov edx, 8
    mov rcx, -1
    call canvas_timeline_wait
    test rax, rax
    jnz .fail
    mov rax, [rel conn]
    lea rcx, [rel server_poll]
    mov [rax + CLIENT_WIRE + ClientWire.pump], rcx
    mov esi, CWP_OBJ_FENCE << 16 | FENCE_EV_FENCE_SIGNALED
    call find_event
    test eax, eax
    jz .fail                            ; still the program's
    PASS

section .bss
timeline:           resd 1
fence:              resd 1
pending_fence:      resd 1
pending_timeline:   resd 1
pending_point:      resq 1
alignb 16
server:         resb Server_size
arena:          resb Arena_size
pair:           resb ChannelPair_size
pair_woken:     resb ChannelPair_size
conn_service:   resq 1
conn:           resq 1
surface_a:      resd 1
buffer_a:       resd 1
alignb 16
event:          resb ClientEvent_size
alignb 16
heap:           resb HEAP_SIZE
