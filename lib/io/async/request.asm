; =============================================================================
; lib/io/async/request.asm
; Request structure builder and state transition validation.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ASYNC_REQUEST_ASM
%define IO_ASYNC_REQUEST_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

; =============================================================================
; io_request_init — Initialize a new asynchronous I/O request block
; In : RDI = -> io_request_t block to initialize
;      RSI = -> device_t target device
;      RDX = Opcode (IO_OP_READ / IO_OP_WRITE, etc.)
;      RCX = LBA (starting sector)
;      R8  = Number of blocks
;      R9  = -> iovec_t array
;      [rsp + 8] = iovec count (pushed stack argument)
; Out: RAX = 0 on success
; =============================================================================
IO_FUNC io_request_init
    guard_null rdi
    guard_null rsi

    push    rbx
    push    rcx
    push    rdx
    push    rdi

    mov     rbx, rdi                ; RBX = -> io_request_t

    ; 1. Clear request structure to zero
    mov     rdi, rbx
    xor     rax, rax
    mov     rcx, io_request_t_size / 8
    cld
    rep     stosq                   ; Zero out all fields

    ; 2. Populate caller fields
    mov     [rbx + io_request_t.device], rsi
    mov     [rbx + io_request_t.opcode], rdx
    mov     [rbx + io_request_t.lba], rcx
    mov     [rbx + io_request_t.nblocks], r8
    mov     [rbx + io_request_t.iov], r9

    ; Fetch stack argument (iovec count)
    ; Since we pushed rbx, rcx, rdx, rdi (32 bytes) + RBP push (8 bytes in prologue),
    ; the stack offset to find [rsp + 8] at entry is now [rsp + 8 + 40] = [rsp + 48]
    mov     rax, [rsp + 48]
    mov     [rbx + io_request_t.iov_cnt], rax

    ; 3. Configure initial state
    mov     qword [rbx + io_request_t.state], IO_REQ_INIT

    ; 4. Capture submission timestamp (rdtsc)
    rdtsc                           ; EDX:EAX = TSC
    shl     rdx, 32
    or      rax, rdx                ; RAX = 64-bit TSC
    mov     [rbx + io_request_t.submit_tsc], rax

    xor     rax, rax                ; Return 0 (Success)
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC io_request_init

; =============================================================================
; io_request_transition — Validate and execute request state transition
; In : RDI = -> io_request_t structure
;      RSI = Target state to transition to (IO_REQ_*)
; Out: RAX = 0 on success, or negative error code (IO_ERR_BADARG) on invalid transition
; =============================================================================
IO_FUNC io_request_transition
    guard_null rdi
    push    rbx

    mov     rax, [rdi + io_request_t.state] ; RAX = current state
    mov     rbx, rsi                ; RBX = target state

    ; Check if target state is valid
    cmp     rbx, 6                  ; Maximum state is IO_REQ_TIMEOUT (6)
    ja      .err_invalid

    ; Terminal states (COMPLETE=3, ERROR=4, CANCELLED=5, TIMEOUT=6) cannot transition
    cmp     rax, 3
    jae     .err_invalid

    ; State machine transition check
    cmp     rax, IO_REQ_INIT
    je      .from_init

    cmp     rax, IO_REQ_SUBMITTED
    je      .from_submitted

    cmp     rax, IO_REQ_IN_FLIGHT
    je      .from_inflight

    jmp     .err_invalid            ; Unknown state transition

.from_init:
    ; INIT (0) -> can only transition to SUBMITTED (1)
    cmp     rbx, IO_REQ_SUBMITTED
    jne     .err_invalid
    jmp     .transition_ok

.from_submitted:
    ; SUBMITTED (1) -> can transition to IN_FLIGHT (2), CANCELLED (5), or TIMEOUT (6)
    cmp     rbx, IO_REQ_IN_FLIGHT
    je      .transition_ok
    cmp     rbx, IO_REQ_CANCELLED
    je      .transition_ok
    cmp     rbx, IO_REQ_TIMEOUT
    je      .transition_ok
    jmp     .err_invalid

.from_inflight:
    ; IN_FLIGHT (2) -> can transition to COMPLETE (3), ERROR (4), CANCELLED (5), or TIMEOUT (6)
    cmp     rbx, IO_REQ_COMPLETE
    je      .transition_ok
    cmp     rbx, IO_REQ_ERROR
    je      .transition_ok
    cmp     rbx, IO_REQ_CANCELLED
    je      .transition_ok
    cmp     rbx, IO_REQ_TIMEOUT
    je      .transition_ok
    jmp     .err_invalid

.transition_ok:
    ; Set next state
    mov     [rdi + io_request_t.state], rbx
    xor     rax, rax                ; Return 0
    jmp     .done

.err_invalid:
    mov     rax, IO_ERR_BADARG      ; Return invalid argument code

.done:
    pop     rbx
    ret
IO_ENDFUNC io_request_transition

%endif ; IO_ASYNC_REQUEST_ASM
