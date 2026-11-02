; ============================================================================
; Unit Test — The Server End to End (src/server/server_core.asm)
; ============================================================================
; test_server_suite -> eax = failed cases (each case returns 0 / 1).
; A client that only writes messages to its ring and reads the answers: the
; golden frame reached through the protocol alone, the frame_done event, and
; requests refused without harm: unknown, short, without the capability, or
; naming another client's objects.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"
%include "inc/color.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern adler32
extern arena_init
extern client_accept
extern client_get
extern msgbuf_read
extern msgbuf_write
extern server_init
extern server_poll

%define HEAP_SIZE (2 * 1024 * 1024)
%define GOLDEN_FIRST 0x5720AE00

%define OP_SYNC     1
%define OP_VERSION  2
%define OP_CREATE   0
%define OP_DESTROY  1
%define OP_ATTACH   2
%define OP_DAMAGE   3
%define OP_FRAME    11
%define OP_COMMIT   12

section .text

global test_server_suite
global test_server_main
test_server_suite:
test_server_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE ts_version
    CASE ts_sync
    CASE ts_golden_frame
    CASE ts_frame_done
    CASE ts_unknown
    CASE ts_short
    CASE ts_no_capability
    CASE ts_foreign
    CASE ts_fair_share
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

; a started server on 64x48 and client A, its capability grant read
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
    call server_init
    mov [rel init_result], rax
    lea rdi, [rel server]
    lea rsi, [rel pair_a]
    xor edx, edx
    call client_accept
    lea rax, [rel pair_a]
    mov [rel current], rax
    call next_event
    add rsp, 8
    ret

; send interface, opcode, the first %3 bytes of [req]
%macro SEND 3
    mov dword [rel hdr + MsgHdr.obj], %1
    mov word [rel hdr + MsgHdr.opcode], %2
    mov word [rel hdr + MsgHdr.flags], 0
    mov dword [rel hdr + MsgHdr.len], %3
    call send
%endmacro

send:
    sub rsp, 8
    mov rax, [rel current]
    mov rdi, [rax + ChannelPair.client_to_server]
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
    mov rax, [rel current]
    mov rdi, [rax + ChannelPair.server_to_client]
    lea rsi, [rel hdr]
    lea rdx, [rel ans]
    mov ecx, 256
    call msgbuf_read
    add rsp, 8
    ret

; the next reply: events may arrive before it, as for any client
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

; a buffer w x h -> eax = handle, rdx = pixels
new_buffer:
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
    mov rdx, [rel ans + 8]
    add rsp, 8
    ret

; a surface -> eax = handle
new_surface:
    sub rsp, 8
    SEND CWP_OBJ_SURFACE, OP_CREATE, 0
    call poll
    call next_reply
    mov eax, [rel ans]
    add rsp, 8
    ret

; attach buffer esi at (edx, ecx) to surface edi, damage w r8d x h r9d, commit
show:
    sub rsp, 8
    mov [rel req], edi
    mov [rel req + 4], esi
    mov [rel req + 8], edx
    mov [rel req + 12], ecx
    mov qword [rel req + 16], 0
    mov [rel show_w], r8d
    mov [rel show_h], r9d
    SEND CWP_OBJ_SURFACE, OP_ATTACH, 24
    mov eax, [rel show_w]
    mov ecx, [rel show_h]
    mov dword [rel req + 4], 0
    mov dword [rel req + 8], 0
    mov [rel req + 12], eax
    mov [rel req + 16], ecx
    SEND CWP_OBJ_SURFACE, OP_DAMAGE, 20
    mov dword [rel req + 4], 0
    SEND CWP_OBJ_SURFACE, OP_COMMIT, 8
    add rsp, 8
    ret

; the error event's code -> eax; 0 if the next message is not an error
error_code:
    sub rsp, 8
    call next_event
    xor ecx, ecx
    test rax, rax
    js .none
    cmp dword [rel hdr + MsgHdr.obj], CWP_OBJ_DISPLAY
    jne .none
    cmp word [rel hdr + MsgHdr.opcode], 1   ; event error
    jne .none
    test word [rel hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jnz .none
    mov ecx, [rel ans + 4]
.none:
    mov eax, ecx
    add rsp, 8
    ret

ts_version:
    sub rsp, 8
    cmp qword [rel init_result], 0
    jne .fail
    SEND CWP_OBJ_DISPLAY, OP_VERSION, 0
    call poll
    cmp rax, 1
    jne .fail
    call next_event
    cmp rax, 12
    jne .fail
    test word [rel hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jz .fail
    cmp dword [rel ans], CWP_VERSION_MAJOR
    jne .fail
    PASS

ts_sync:
    sub rsp, 8
    SEND CWP_OBJ_DISPLAY, OP_SYNC, 0
    SEND CWP_OBJ_DISPLAY, OP_SYNC, 0
    call poll
    call next_event
    cmp qword [rel ans], 1
    jne .fail
    call next_event
    cmp qword [rel ans], 2
    jne .fail
    PASS

; the scene of test_golden, by protocol alone: the same checksum
ts_golden_frame:
    push rbx
    push r12
    sub rsp, 8
    mov edi, 32
    mov esi, 24
    call new_buffer
    mov ebx, eax
    mov rdi, rdx
    xor ecx, ecx
.row:
    xor edx, edx
.pixel:
    lea eax, [rcx * 8]
    and eax, 255
    shl eax, 8
    or eax, 0xFF000010
    lea r8d, [rdx * 4]
    and r8d, 255
    shl r8d, 16
    or eax, r8d
    mov [rdi], eax
    add rdi, 4
    inc edx
    cmp edx, 32
    jb .pixel
    inc ecx
    cmp ecx, 24
    jb .row
    call new_surface
    mov r12d, eax
    mov edi, eax
    mov esi, ebx
    mov edx, 8
    mov ecx, 8
    mov r8d, 32
    mov r9d, 24
    call show
    mov edi, 16
    mov esi, 16
    call new_buffer
    mov ebx, eax
    mov rdi, rdx
    mov eax, 0x80004000
    mov ecx, 16 * 16
    rep stosd
    call new_surface
    mov edi, eax
    mov esi, ebx
    mov edx, 24
    mov ecx, 16
    mov r8d, 16
    mov r9d, 16
    call show
    call poll
    mov rax, [rel server + Server.outputs]
    mov rdi, [rax + Output.framebuffer]
    mov esi, 64 * 48 * 4
    mov edx, 1
    call adler32
    xor ecx, ecx
    cmp eax, GOLDEN_FIRST
    setne cl
    mov eax, ecx
    add rsp, 8
    pop r12
    pop rbx
    ret

ts_frame_done:
    push rbx
    mov edi, 4
    mov esi, 4
    call new_buffer
    call new_surface
    mov ebx, eax
    mov [rel req], eax
    SEND CWP_OBJ_SURFACE, OP_FRAME, 4
    mov edi, ebx
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    mov r8d, 4
    mov r9d, 4
    call show
    call poll
    call next_event                     ; the callback's id
    cmp rax, 4
    jne .bad
    mov edx, [rel ans]
    mov [rel callback], edx
    call next_event                     ; frame_done
    cmp rax, 20
    jne .bad
    cmp dword [rel hdr + MsgHdr.obj], CWP_OBJ_SURFACE
    jne .bad
    test word [rel hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jnz .bad
    cmp [rel ans], ebx
    jne .bad
    mov edx, [rel callback]
    cmp [rel ans + 4], edx
    jne .bad
    xor eax, eax
    pop rbx
    ret
.bad:
    mov eax, 1
    pop rbx
    ret

ts_unknown:
    sub rsp, 8
    SEND CWP_OBJ_SURFACE, 200, 0
    SEND CWP_OBJ_DISPLAY, OP_VERSION, 0
    call poll
    call error_code
    cmp eax, ECWP_OPCODE
    jne .fail
    call next_event                     ; and the next request still works
    cmp rax, 12
    jne .fail
    PASS

ts_short:
    sub rsp, 8
    SEND CWP_OBJ_SURFACE, OP_DAMAGE, 8  ; damage needs 20 bytes
    call poll
    call error_code
    cmp eax, ECWP_PAYLOAD
    jne .fail
    PASS

ts_no_capability:
    sub rsp, 8
    lea rdi, [rel server]
    mov esi, 1
    call client_get
    mov qword [rax + Client.caps], CAP_DISPLAY
    SEND CWP_OBJ_SURFACE, OP_CREATE, 0
    call poll
    call error_code
    cmp eax, ECWP_CAP
    jne .fail
    PASS

ts_foreign:
    push rbx
    call new_surface                    ; A's
    mov ebx, eax
    lea rdi, [rel server]
    lea rsi, [rel pair_b]
    xor edx, edx
    call client_accept
    lea rax, [rel pair_b]
    mov [rel current], rax
    call next_event
    mov [rel req], ebx                  ; B reaches for it
    mov dword [rel req + 4], 0
    SEND CWP_OBJ_SURFACE, OP_COMMIT, 8
    call poll
    call error_code
    cmp eax, ECWP_OBJECT
    jne .bad
    mov [rel req], ebx
    SEND CWP_OBJ_SURFACE, OP_DESTROY, 4
    call poll
    call error_code
    cmp eax, ECWP_OBJECT
    jne .bad
    mov rdi, [rel server + Server.surface_table]
    mov esi, ebx
    extern handle_resolve
    call handle_resolve                 ; still A's
    test rax, rax
    jz .bad
    xor eax, eax
    pop rbx
    ret
.bad:
    mov eax, 1
    pop rbx
    ret

; a flood waits its turn: one client's share per poll
ts_fair_share:
    push rbx
    mov ebx, 100
.flood:
    SEND CWP_OBJ_DISPLAY, OP_SYNC, 0
    dec ebx
    jnz .flood
    call poll
    mov ebx, eax
    call poll
    cmp ebx, 64
    jne .bad
    cmp rax, 36
    jne .bad
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
pair_a:         resb ChannelPair_size
pair_b:         resb ChannelPair_size
hdr:            resb MsgHdr_size
current:        resq 1
init_result:    resq 1
callback:       resd 1
show_w:         resd 1
show_h:         resd 1
alignb 16
req:            resb 64
ans:            resb 256
alignb 16
heap:           resb HEAP_SIZE
