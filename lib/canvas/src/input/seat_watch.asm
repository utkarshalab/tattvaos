; ============================================================================
; Seat Watch — What Clients Learn of Switches and Devices (cw_seat)
; ============================================================================
; A client with CAP_SEAT asks cw_seat.watch and hears switched(which, 1) for
; each switch that is on, then done; from then on each switch that changes
; (records type 9) and each input device added, removed or changed (records
; type 10), as input.asm tells them here. Up to SEAT_WATCHERS clients watch.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/struct_offsets.inc"

extern sync_event

section .text

; ---------------------------------------------------------------------------
; seat_watch
;   The switches on to the client, then done; it is told of changes from now
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0, -ENOSPC with SEAT_WATCHERS watching already
; ---------------------------------------------------------------------------
global seat_watch
seat_watch:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    xor ecx, ecx                        ; watching already, or a free place
    mov edx, -1
.find:
    mov rax, [rbx + Server.seat_watchers + rcx * 8]
    cmp rax, r12
    je .watching
    test rax, rax
    jnz .next
    cmp edx, -1
    jne .next
    mov edx, ecx
.next:
    inc ecx
    cmp ecx, SEAT_WATCHERS
    jb .find
    mov rax, -(ENOSPC)
    cmp edx, -1
    je .out
    mov [rbx + Server.seat_watchers + rdx * 8], r12
.watching:
    xor r13d, r13d
.switch:
    mov rax, [rbx + Server.input_seat]
    test rax, rax
    jz .done                            ; no seat: no switches
    mov eax, [rax + InputSeat.switches]
    bt eax, r13d
    jnc .off
    sub rsp, 16                         ; switched(which, 1)
    mov [rsp], r13d
    mov dword [rsp + 4], 1
    mov rdi, r12
    mov esi, CWP_OBJ_SEAT
    mov edx, SEAT_EV_SWITCHED
    mov rcx, rsp
    mov r8d, 8
    call sync_event
    add rsp, 16
.off:
    inc r13d
    cmp r13d, 32
    jb .switch
.done:
    mov rdi, r12                        ; and that is all of them
    mov esi, CWP_OBJ_SEAT
    mov edx, SEAT_EV_DONE
    xor ecx, ecx
    xor r8d, r8d
    call sync_event
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; seat_tell_switch
;   A switch changed: switched(which, state) to every watcher
;   IN:  rdi = server*, esi = which, edx = state (1 on or closed, 0 off)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global seat_tell_switch
seat_tell_switch:
    sub rsp, 24                         ; the event; 16-byte aligned
    mov [rsp], esi
    mov [rsp + 4], edx
    mov esi, SEAT_EV_SWITCHED
    mov rdx, rsp
    mov ecx, 8
    call tell_all
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; seat_tell_device
;   A device added, removed or changed: device(change, id, caps) to every
;   watcher
;   IN:  rdi = server*, esi = change (INPUT_DEVICE_*), edx = the device,
;        ecx = its capability bits
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global seat_tell_device
seat_tell_device:
    sub rsp, 24                         ; the event; 16-byte aligned
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov esi, SEAT_EV_DEVICE
    mov rdx, rsp
    mov ecx, 12
    call tell_all
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; seat_client_gone
;   A client going watches no more
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global seat_client_gone
seat_client_gone:
    xor ecx, ecx
.next:
    cmp [rdi + Server.seat_watchers + rcx * 8], rsi
    jne .other
    mov qword [rdi + Server.seat_watchers + rcx * 8], 0
.other:
    inc ecx
    cmp ecx, SEAT_WATCHERS
    jb .next
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; rdi = server, esi = the cw_seat event, rdx = its payload, ecx = its bytes:
; to every watcher -> eax = 0
tell_all:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    xor r15d, r15d
.watcher:
    mov rdi, [rbx + Server.seat_watchers + r15 * 8]
    test rdi, rdi
    jz .next
    mov esi, CWP_OBJ_SEAT
    mov edx, r12d
    mov rcx, r13
    mov r8d, r14d
    call sync_event
.next:
    inc r15d
    cmp r15d, SEAT_WATCHERS
    jb .watcher
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

section .data
global seat_watch_version
seat_watch_version: dq 0x010000
