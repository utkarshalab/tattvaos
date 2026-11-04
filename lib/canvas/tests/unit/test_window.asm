; ============================================================================
; Unit Test — Windows (src/shell/window.asm, proto/canvas-shell.cwp)
; ============================================================================
; test_window_suite -> eax = failed cases (each case returns 0 / 1).
; A server on 64x48 and one client with the shell capability. The cases send
; cw_toplevel requests and read the events and the server's own records.

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
extern client_accept
extern handle_resolve
extern msgbuf_read
extern msgbuf_write
extern server_init
extern server_poll
extern virtual_input_inject

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
%define TL_CONFIGURE    0

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

; the pointer to x, y
%macro POINTER 2
    lea rdi, [rel server]
    mov esi, INPUT_POSITION
    mov edx, %1
    mov ecx, %2
    xor r8d, r8d
    call virtual_input_inject
%endmacro

; edi = capabilities: a started server and a client with them
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
    call client_accept
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

; create answers with configure(surface, 1, 0, 0); an ack of a serial never
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
    cmp rax, 16
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
