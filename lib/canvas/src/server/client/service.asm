; ============================================================================
; Service — How Other Programs Reach the Server (KRN-03, PRO-01)
; ============================================================================
; canvasd publishes service_connect under the name "canvas"
; (ut_service_publish). A client's canvas_connect finds it (ut_service_lookup)
; and calls it on the client's own task with a ChannelPair it owns. That call
; touches nothing of the server's but one of CONNECT_SLOTS slots, taken with
; a compare-and-swap, so any number of clients may call at once; then it
; wakes the server. The server's loop accepts what is waiting (service_step,
; at the start of every turn) and sets the pair's state: 1 ready, or the
; negative error. The client waits for that state, then talks over the pair.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/channel.inc"
%include "inc/struct_offsets.inc"

extern client_accept
extern server_wake
extern ut_service_publish

section .text

; ---------------------------------------------------------------------------
; service_start
;   Publish the server for other programs to connect to
;   IN:  rdi = server*
;   OUT: rax = 0, or the kernel's negative error (-ENOSYS without it)
; ---------------------------------------------------------------------------
global service_start
service_start:
    sub rsp, 8
    mov rdx, rdi
    lea rdi, [rel service_name]
    lea rsi, [rel service_connect]
    call ut_service_publish
    add rsp, 8
    ret

; ---------------------------------------------------------------------------
; service_connect
;   A client asks to connect: its pair queued for the server's loop, which is
;   woken. Runs on the client's task.
;   IN:  rdi = server* (the published cookie), rsi = ChannelPair* (the
;        client's, its state set to 0 here), rdx = capabilities wanted
;   OUT: rax = 0 queued, -EAGAIN with every slot taken
; ---------------------------------------------------------------------------
global service_connect
service_connect:
    push rbx
    mov rbx, rdi
    mov qword [rsi + ChannelPair.state], 0
    xor ecx, ecx
.slot:
    imul r8d, ecx, ConnectSlot_size
    lea r8, [rbx + Server.connects + r8]
    xor eax, eax                        ; free (0) to this pair, at once
    lock cmpxchg [r8 + ConnectSlot.pair], rsi
    je .taken
    inc ecx
    cmp ecx, CONNECT_SLOTS
    jb .slot
    mov rax, -(EAGAIN)
    pop rbx
    ret
.taken:
    mov [r8 + ConnectSlot.caps], rdx
    mov qword [r8 + ConnectSlot.ready], 1   ; last: the server may take it
    mov rdi, rbx
    call server_wake
    xor eax, eax
    pop rbx
    ret

; ---------------------------------------------------------------------------
; service_step
;   Every client waiting accepted (client_accept, the standard profile), its
;   pair's state set, its slot freed. On the server's loop.
;   IN:  rdi = server*
;   OUT: rax = clients accepted
; ---------------------------------------------------------------------------
global service_step
service_step:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    xor r12d, r12d                      ; the slot
    xor r14d, r14d                      ; accepted
.slot:
    imul eax, r12d, ConnectSlot_size
    lea r13, [rbx + Server.connects + rax]
    cmp qword [r13 + ConnectSlot.ready], 0
    je .next
    mov rdi, rbx
    mov rsi, [r13 + ConnectSlot.pair]
    mov rdx, [r13 + ConnectSlot.caps]
    call client_accept
    mov rsi, [r13 + ConnectSlot.pair]
    mov ecx, 1                          ; the pair filled first, then ready
    test rax, rax
    cmovs rcx, rax
    mov [rsi + ChannelPair.state], rcx
    jl .refused
    inc r14d
.refused:
    mov qword [r13 + ConnectSlot.ready], 0
    mov qword [r13 + ConnectSlot.pair], 0   ; free for the next
.next:
    inc r12d
    cmp r12d, CONNECT_SLOTS
    jb .slot
    mov eax, r14d
    EPILOGUE_RESTORE rbx, r12, r13, r14

section .rodata
global service_name
service_name:   db "canvas", 0

section .data
global service_version
service_version: dq 0x010000
