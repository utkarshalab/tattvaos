; ============================================================================
; Unit Test — Surfaces and Buffers (src/server/surface, buffer, commit)
; ============================================================================
; test_surface_suite -> eax = failed cases (each case returns 0 / 1).
; Creation and refusal of buffers; pending state staying pending until a
; commit; damage adding up across commits; a replaced buffer released; frame
; callbacks; a client's disconnect taking its surfaces and buffers with it.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/channel.inc"
%include "inc/struct_offsets.inc"

extern arena_init
extern handle_resolve
extern client_init
extern client_accept
extern client_get
extern client_disconnect
extern presentation_init
extern surface_init
extern surface_create
extern surface_destroy
extern surface_attach
extern surface_damage
extern surface_frame_callback
extern buffer_init
extern buffer_create
extern buffer_attach
extern commit_surface
extern surface_fire_frame_callbacks

%define HEAP_SIZE (1024 * 1024)

section .text

global test_surface_suite
global test_surface_main
test_surface_suite:
test_surface_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE ts_layout
    CASE ts_create
    CASE ts_buffer
    CASE ts_buffer_refused
    CASE ts_pending
    CASE ts_nothing_pending
    CASE ts_damage_adds_up
    CASE ts_attach_refused
    CASE ts_release_old
    CASE ts_frame_callback
    CASE ts_destroy
    CASE ts_disconnect
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

; a server with its tables, one client in [client], one surface in [surface]
fresh:
    sub rsp, 8
    lea rdi, [rel server]
    xor eax, eax
    mov ecx, Server_size
    rep stosb
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call client_init
    call presentation_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call surface_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call buffer_init
    lea rdi, [rel server]
    lea rsi, [rel pair]
    xor edx, edx
    call client_accept
    mov [rel client_id], rax
    lea rdi, [rel server]
    mov rsi, rax
    call client_get
    mov [rel client], rax
    lea rdi, [rel server]
    mov rsi, rax
    xor edx, edx
    call surface_create
    mov [rel surf_handle], rax
    mov rdi, [rel server + Server.surface_table]
    mov rsi, rax
    call handle_resolve
    mov [rel surface], rax
    add rsp, 8
    ret

; a 16x8 BGRA buffer -> rax = handle
new_buffer:
    sub rsp, 8
    mov dword [rel params], 16
    mov dword [rel params + 4], 8
    mov dword [rel params + 8], DRM_FORMAT_BGRA8888
    lea rdi, [rel server]
    mov rsi, [rel client]
    lea rdx, [rel params]
    xor ecx, ecx
    call buffer_create
    add rsp, 8
    ret

; rax = handle -> rax = Buffer*
buffer_of:
    sub rsp, 8
    mov rdi, [rel server + Server.buffer_table]
    mov rsi, rax
    call handle_resolve
    add rsp, 8
    ret

%macro COMMIT 0
    lea rdi, [rel server]
    mov rsi, [rel surface]
    xor edx, edx
    call commit_surface
%endmacro
%macro DAMAGE 4
    lea rdi, [rel server]
    mov rsi, [rel surface]
    mov edx, %1
    mov ecx, %2
    mov r8d, %3
    mov r9d, %4
    call surface_damage
%endmacro

ts_layout:
    sub rsp, 8
    mov eax, Surface.pending - Surface.current
    cmp eax, SurfaceState_size          ; embedded whole, nothing overlapping
    jne .fail
    PASS

ts_create:
    sub rsp, 8
    cmp qword [rel surf_handle], 0
    jle .fail
    mov rax, [rel surface]
    test rax, rax
    jz .fail
    mov rcx, [rel client]
    cmp [rax + Surface.client], rcx
    jne .fail
    cmp [rcx + Client.surfaces], rax
    jne .fail
    mov rcx, [rel surf_handle]
    cmp [rax + Surface.id], rcx
    jne .fail
    PASS

ts_buffer:
    sub rsp, 8
    call new_buffer
    test rax, rax
    jle .fail
    call buffer_of
    test rax, rax
    jz .fail
    cmp qword [rax + Buffer.stride], 64
    jne .fail
    cmp qword [rax + Buffer.size], 64 * 8
    jne .fail
    cmp qword [rax + Buffer.width], 16
    jne .fail
    mov rcx, [rax + Buffer.base]
    test rcx, rcx
    jz .fail
    mov dword [rcx + 64 * 8 - 4], 0x12345678    ; the last pixel is writable
    PASS

ts_buffer_refused:
    sub rsp, 8
    mov dword [rel params], 16
    mov dword [rel params + 4], 8
    mov dword [rel params + 8], 0x20202020
    lea rdi, [rel server]
    mov rsi, [rel client]
    lea rdx, [rel params]
    xor ecx, ecx
    call buffer_create
    cmp rax, -(EBUF_FORMAT)
    jne .fail
    mov dword [rel params], 0
    mov dword [rel params + 8], DRM_FORMAT_BGRA8888
    lea rdi, [rel server]
    mov rsi, [rel client]
    lea rdx, [rel params]
    xor ecx, ecx
    call buffer_create
    cmp rax, -(EBUF_SIZE)
    jne .fail
    PASS

ts_pending:
    push rbx
    call new_buffer
    mov rbx, rax
    lea rdi, [rel server]
    mov rsi, [rel surface]
    mov rdx, rbx
    mov ecx, 3
    mov r8d, 4
    call surface_attach
    test rax, rax
    jnz .bad
    mov rax, [rel surface]
    cmp qword [rax + Surface.current + SurfaceState.buffer], 0
    jne .bad                            ; not visible yet
    COMMIT
    test rax, rax
    jnz .bad
    mov rax, [rel surface]
    cmp [rax + Surface.current + SurfaceState.buffer], rbx
    jne .bad
    cmp dword [rax + Surface.current + SurfaceState.buf_x], 3
    jne .bad
    cmp dword [rax + Surface.current + SurfaceState.buf_y], 4
    jne .bad
    cmp dword [rax + Surface.pending + SurfaceState.pending], 0
    jne .bad
    cmp qword [rax + Surface.frame_seq], 1
    jne .bad
    xor eax, eax
    pop rbx
    ret
.bad:
    mov eax, 1
    pop rbx
    ret

ts_nothing_pending:
    sub rsp, 8
    COMMIT
    test rax, rax
    jnz .fail
    mov rax, [rel surface]
    cmp qword [rax + Surface.frame_seq], 0
    jne .fail
    PASS

ts_damage_adds_up:
    sub rsp, 8
    DAMAGE 0, 0, 10, 10
    COMMIT
    DAMAGE 20, 20, 4, 5
    COMMIT
    mov rax, [rel surface]
    mov rcx, [rax + Surface.current + SurfaceState.damage]
    cmp qword [rcx + Region.count], 2   ; a frame has not taken the first yet
    jne .fail
    mov rcx, [rax + Surface.pending + SurfaceState.damage]
    cmp qword [rcx + Region.count], 0
    jne .fail
    PASS

ts_attach_refused:
    sub rsp, 8
    lea rdi, [rel server]
    mov rsi, [rel surface]
    mov edx, 0x7777
    xor ecx, ecx
    xor r8d, r8d
    call surface_attach
    cmp rax, -(EBUF_FORMAT)
    jne .fail
    lea rdi, [rel server]
    mov rsi, [rel surface]
    xor edx, edx                        ; detaching needs no buffer
    xor ecx, ecx
    xor r8d, r8d
    call surface_attach
    test rax, rax
    jnz .fail
    PASS

ts_release_old:
    push rbx
    push r12
    sub rsp, 8
    call new_buffer
    mov rbx, rax
    call new_buffer
    mov r12, rax
%macro ATTACH 1
    lea rdi, [rel server]
    mov rsi, [rel surface]
    mov rdx, %1
    xor ecx, ecx
    xor r8d, r8d
    call buffer_attach
%endmacro
    ATTACH rbx
    test rax, rax
    jnz .bad
    COMMIT
    ATTACH r12
    test rax, rax
    jnz .bad
    COMMIT
    mov rax, rbx
    call buffer_of
    cmp qword [rax + Buffer.state], 1   ; ALLOCATED: the client may reuse it
    jne .bad
    mov rax, r12
    call buffer_of
    cmp qword [rax + Buffer.state], 2   ; ATTACHED: on screen
    jne .bad
    ATTACH rbx                          ; the released one can come back
    test rax, rax
    jnz .bad
    xor eax, eax
    jmp .out
.bad:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; (surface, user data, sequence)
frame_cb:
    mov [rel cb_surface], rdi
    mov [rel cb_user], rsi
    mov [rel cb_seq], rdx
    ret

ts_frame_callback:
    sub rsp, 8
    mov qword [rel cb_user], 0
    lea rdi, [rel server]
    mov rsi, [rel surface]
    lea rdx, [rel frame_cb]
    mov ecx, 55
    call surface_frame_callback
    test rax, rax
    jnz .fail
    cmp qword [rel cb_user], 0
    jne .fail                           ; pending until the commit
    COMMIT
    cmp qword [rel cb_user], 0
    jne .fail                           ; and until the frame is done
    mov rdi, [rel surface]
    call surface_fire_frame_callbacks
    cmp qword [rel cb_user], 55
    jne .fail
    mov rax, [rel surface]
    cmp [rel cb_surface], rax
    jne .fail
    cmp qword [rel cb_seq], 1
    jne .fail
    mov rax, [rel surface]              ; the spent node waits to be reused
    mov rcx, [rax + Surface.cb_free]
    test rcx, rcx
    jz .fail
    lea rdi, [rel server]
    mov rsi, [rel surface]
    lea rdx, [rel frame_cb]
    mov ecx, 56
    call surface_frame_callback
    mov rax, [rel surface]
    cmp qword [rax + Surface.cb_free], 0
    jne .fail
    PASS

ts_destroy:
    sub rsp, 8
    lea rdi, [rel server]
    mov rsi, [rel surf_handle]
    call surface_destroy
    test rax, rax
    jnz .fail
    mov rax, [rel client]
    cmp qword [rax + Client.surfaces], 0
    jne .fail
    mov rdi, [rel server + Server.surface_table]
    mov rsi, [rel surf_handle]
    call handle_resolve
    test rax, rax
    jnz .fail
    lea rdi, [rel server]
    mov rsi, [rel surf_handle]          ; twice
    call surface_destroy
    cmp rax, -(ENOENT)
    jne .fail
    PASS

ts_disconnect:
    push rbx
    call new_buffer
    mov rbx, rax
    lea rdi, [rel server]
    mov rsi, [rel client_id]
    call client_disconnect
    test rax, rax
    jnz .bad
    mov rdi, [rel server + Server.surface_table]
    mov rsi, [rel surf_handle]
    call handle_resolve
    test rax, rax
    jnz .bad
    mov rax, rbx
    call buffer_of
    test rax, rax
    jnz .bad
    xor eax, eax
    pop rbx
    ret
.bad:
    mov eax, 1
    pop rbx
    ret

section .bss
alignb 16
server:         resb Server_size
arena:          resb Arena_size
pair:           resb ChannelPair_size
params:         resb 24
client_id:      resq 1
client:         resq 1
surface:        resq 1
surf_handle:    resq 1
cb_surface:     resq 1
cb_user:        resq 1
cb_seq:         resq 1
alignb 16
heap:           resb HEAP_SIZE
