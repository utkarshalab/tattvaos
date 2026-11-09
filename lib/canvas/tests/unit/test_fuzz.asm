; ============================================================================
; Unit Test — Fuzzing the Server's Wire and Input (FND-10)
; ============================================================================
; test_fuzz_suite -> eax = failed cases (each case returns 0 / 1).
; A trusted client holding every capability sends random messages: random
; objects, opcodes, lengths and bytes (so random handles, sizes and counts),
; mixed with random raw input records of every type. The server must not
; crash (a crash fails the suite, ending the process), and afterwards a
; second client, well behaved, must still get its answer. Each case starts
; from a fixed seed, so a failure repeats.
;
; To reach past the handle checks, A makes real buffers and surfaces every
; 32 rounds, and the handles the server's replies give are put back into
; random messages' first two dwords half of the time.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"
%include "inc/color.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_init
extern client_accept_trusted
extern msgbuf_read
extern msgbuf_write
extern server_init
extern server_poll
extern virtual_input_inject

%define HEAP_SIZE   (4 * 1024 * 1024)  ; small, so a stray read past it faults
%define ROUNDS      12000               ; messages and records a case
%define PAYLOAD_MAX 128                 ; random bytes a message carries
%define OBJECTS     40                  ; object ids tried: 0 to 39
%define OPCODES     24
%define INPUT_TYPES 13                  ; 0 to 12: every type and past them
%define OP_SYNC     1
%define OP_CREATE   0
%define HANDLES     16                  ; replies' handles kept, a ring

section .text

global test_fuzz_suite
global test_fuzz_main
test_fuzz_suite:
test_fuzz_main:
    push rbx
    xor ebx, ebx
%macro CASE 2
    mov rdi, %2
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tf_wire, 0x9E3779B97F4A7C15
    CASE tf_wire, 0x0123456789ABCDEF
    CASE tf_input, 0xD1B54A32D192ED03
    CASE tf_mixed, 0x8CB92BA72F3D8DD7
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

; rdi = the seed: a started server on 64x48, the fuzzing client A with every
; capability and the well-behaved client B, both drained
fresh:
    sub rsp, 8
    mov [rel seed], rdi
    mov qword [rel handled], 0
    mov dword [rel handle_next], 0
    lea rdi, [rel handles]
    xor eax, eax
    mov ecx, HANDLES
    rep stosd
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
    lea rsi, [rel pair_a]
    mov edx, 0x03FFFFFF                 ; every capability there is
    call client_accept_trusted
    lea rdi, [rel server]
    lea rsi, [rel pair_b]
    mov edx, CAP_DISPLAY
    call client_accept_trusted
    call drain
    add rsp, 8
    ret

; -> rax = the next random number (xorshift64*)
random:
    mov rax, [rel seed]
    mov rcx, rax
    shr rcx, 12
    xor rax, rcx
    mov rcx, rax
    shl rcx, 25
    xor rax, rcx
    mov rcx, rax
    shr rcx, 27
    xor rax, rcx
    mov [rel seed], rax
    mov rcx, 0x2545F4914F6CDD1D
    imul rax, rcx
    ret

; edi = n -> eax = a random number below n
below:
    push rbx
    mov ebx, edi
    call random
    shr rax, 32
    xor edx, edx
    div ebx
    mov eax, edx
    pop rbx
    ret

; One random message from A: its object, opcode, length, every byte random.
message:
    push rbx
    mov edi, OBJECTS
    call below
    mov [rel hdr + MsgHdr.obj], eax
    mov edi, OPCODES
    call below
    mov [rel hdr + MsgHdr.opcode], ax
    mov word [rel hdr + MsgHdr.flags], 0
    mov edi, PAYLOAD_MAX + 1
    call below
    mov [rel hdr + MsgHdr.len], eax
    xor ebx, ebx                        ; the bytes; small numbers often,
.byte:                                  ; so sizes and handles are near real
    call random
    test al, 3
    jnz .keep
    and rax, 0xFF                       ; a quarter of the dwords small
.keep:
    lea rcx, [rel payload]
    mov [rcx + rbx * 8], rax
    inc ebx
    cmp ebx, PAYLOAD_MAX / 8
    jb .byte
    call random                         ; known handles, half the time
    test al, 1
    jz .first_done
    call known
    mov [rel payload], eax
.first_done:
    call random
    test al, 2
    jz .second_done
    call known
    mov [rel payload + 4], eax
.second_done:
    mov rdi, [rel pair_a + ChannelPair.client_to_server]
    lea rsi, [rel hdr]
    lea rdx, [rel payload]
    call msgbuf_write                   ; full: dropped, the next poll empties
    pop rbx
    ret

; -> eax = one of the handles replies gave (0 before any)
known:
    sub rsp, 8
    mov edi, HANDLES
    call below
    lea rcx, [rel handles]
    mov eax, [rcx + rax * 4]
    add rsp, 8
    ret

; Real objects from A: a buffer of a random size up to 64x64, a surface.
objects:
    sub rsp, 8
    mov edi, 64
    call below
    inc eax
    mov [rel payload], eax
    mov edi, 64
    call below
    inc eax
    mov [rel payload + 4], eax
    mov dword [rel payload + 8], DRM_FORMAT_BGRA8888
    mov dword [rel payload + 12], 0
    mov qword [rel payload + 16], 0
    mov dword [rel hdr + MsgHdr.obj], CWP_OBJ_BUFFER
    mov word [rel hdr + MsgHdr.opcode], OP_CREATE
    mov word [rel hdr + MsgHdr.flags], 0
    mov dword [rel hdr + MsgHdr.len], 24
    mov rdi, [rel pair_a + ChannelPair.client_to_server]
    lea rsi, [rel hdr]
    lea rdx, [rel payload]
    call msgbuf_write
    mov dword [rel hdr + MsgHdr.obj], CWP_OBJ_SURFACE
    mov dword [rel hdr + MsgHdr.len], 0
    mov rdi, [rel pair_a + ChannelPair.client_to_server]
    lea rsi, [rel hdr]
    lea rdx, [rel payload]
    call msgbuf_write
    add rsp, 8
    ret

; One random raw input record: any type, code, value and device 0-9.
record:
    push rbx
    push r12
    push r13
    mov edi, INPUT_TYPES
    call below
    mov ebx, eax
    call random
    mov r12d, eax
    test r12d, 0x10000000               ; often a small code
    jz .code
    and r12d, 0xFFFF
.code:
    call random
    mov r13d, eax
    mov edi, 10
    call below
    mov r8d, eax
    lea rdi, [rel server]
    mov esi, ebx
    mov edx, r12d
    mov ecx, r13d
    call virtual_input_inject
    pop r13
    pop r12
    pop rbx
    ret

; A turn, and what both clients were sent read and dropped.
turn:
    sub rsp, 8
    lea rdi, [rel server]
    call server_poll
    test rax, rax
    js .counted
    add [rel handled], rax
.counted:
    call drain
    add rsp, 8
    ret

drain:
    sub rsp, 8
.a:
    mov rdi, [rel pair_a + ChannelPair.server_to_client]
    lea rsi, [rel ans_hdr]
    lea rdx, [rel ans]
    mov ecx, 4096
    call msgbuf_read
    test rax, rax
    js .b
    test word [rel ans_hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jz .a
    cmp rax, 4
    jb .a
    mov ecx, [rel handle_next]          ; a reply's first dword, kept
    and ecx, HANDLES - 1
    lea rdx, [rel handles]
    mov eax, [rel ans]
    mov [rdx + rcx * 4], eax
    inc dword [rel handle_next]
    jmp .a
.b:
    mov rdi, [rel pair_b + ChannelPair.server_to_client]
    lea rsi, [rel ans_hdr]
    lea rdx, [rel ans]
    mov ecx, 4096
    call msgbuf_read
    test rax, rax
    jns .b
    add rsp, 8
    ret

; -> eax = 1 if client B, after everything, still has its sync answered
b_answered:
    sub rsp, 8
    mov dword [rel hdr + MsgHdr.obj], CWP_OBJ_DISPLAY
    mov word [rel hdr + MsgHdr.opcode], OP_SYNC
    mov word [rel hdr + MsgHdr.flags], 0
    mov dword [rel hdr + MsgHdr.len], 0
    mov rdi, [rel pair_b + ChannelPair.client_to_server]
    lea rsi, [rel hdr]
    lea rdx, [rel payload]
    call msgbuf_write
    lea rdi, [rel server]
    call server_poll
.next:
    mov rdi, [rel pair_b + ChannelPair.server_to_client]
    lea rsi, [rel ans_hdr]
    lea rdx, [rel ans]
    mov ecx, 4096
    call msgbuf_read
    test rax, rax
    js .no
    test word [rel ans_hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jz .next
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, 8
    ret

; %1: 1 for messages, 2 for records, 3 for both; ROUNDS of them, a turn
; every eight, then B answered
%macro FUZZ 1
    push rbx
    xor ebx, ebx
%%round:
  %if %1 == 3
    mov edi, 4
    call below
    test eax, eax
    jz %%input
  %endif
  %if %1 != 2
    call message
  %endif
  %if %1 == 3
    jmp %%sent
%%input:
  %endif
  %if %1 != 1
    call record
  %endif
%%sent:
    test ebx, 31
    jnz %%no_objects
    call objects
%%no_objects:
    test ebx, 7
    jnz %%no_turn
    call turn
%%no_turn:
    inc ebx
    cmp ebx, ROUNDS
    jb %%round
    call turn
    pop rbx
    call b_answered
    test eax, eax
    jz .fail
%endmacro

; Random messages only; most of them reach the dispatcher (the client is
; not cut off early, which would make the rest of the case empty)
tf_wire:
    sub rsp, 8
    FUZZ 1
    cmp qword [rel handled], ROUNDS / 2
    jb .fail
    PASS

; Random input records only
tf_input:
    sub rsp, 8
    FUZZ 2
    PASS

; Both, a quarter of them records
tf_mixed:
    sub rsp, 8
    FUZZ 3
    PASS

section .bss
alignb 16
server:         resb Server_size
arena:          resb Arena_size
pair_a:         resb ChannelPair_size
pair_b:         resb ChannelPair_size
hdr:            resb MsgHdr_size
ans_hdr:        resb MsgHdr_size
seed:           resq 1
handled:        resq 1                  ; requests the server took
handle_next:    resd 1
handles:        resd HANDLES            ; replies' first dwords
alignb 16
payload:        resb PAYLOAD_MAX
ans:            resb 4096
alignb 16
heap:           resb HEAP_SIZE
