; ============================================================================
; Activation — Tokens That Let One App Bring Up Another's Window
; ============================================================================
; PRO-18. A window that has the keyboard may ask for a token
; (cw_toplevel.get_activation_token): the user is working there, so what it
; starts or opens may come to the front. Whoever holds the token activates a
; window with it (cw_toplevel.activate): raised, given the keyboard, past
; the guard against windows taking it while the user types (WIN-12).
;
; A token is 64 bits from SipHash under a key the kernel's entropy gives the
; first time one is made, of a count and the time: not to be guessed. Each is
; good once, for ACT_TTL_NS; ACT_TOKENS are kept, the oldest giving way.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern siphash24
extern ut_entropy_siphash_key
extern ut_time_now_ns

%define ACT_TTL_NS      10000000000     ; ten seconds

section .text

; ---------------------------------------------------------------------------
; activation_issue
;   A token, if the surface has the keyboard
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = the token, 0 if the surface does not have the keyboard
; ---------------------------------------------------------------------------
global activation_issue
activation_issue:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 16                         ; what is hashed: the count, the time
    mov rbx, rdi
    xor eax, eax
    mov rcx, [rbx + Server.input_seat]
    test rcx, rcx
    jz .out
    cmp [rcx + InputSeat.keyboard_focus], rsi
    jne .out
    cmp qword [rbx + Server.act_keyed], 0
    jne .keyed
    lea rdi, [rbx + Server.act_key]
    call ut_entropy_siphash_key
    mov qword [rbx + Server.act_keyed], 1
.keyed:
    inc qword [rbx + Server.act_seq]
    mov rax, [rbx + Server.act_seq]
    mov [rsp], rax
    call ut_time_now_ns
    mov [rsp + 8], rax
    mov r12, rax
    mov rdi, rsp
    mov esi, 16
    lea rdx, [rbx + Server.act_key]
    call siphash24
    test rax, rax                       ; 0 means none
    jnz .valued
    inc rax
.valued:
    mov rcx, [rbx + Server.act_seq]     ; its slot: the oldest goes
    and ecx, ACT_TOKENS - 1
    shl ecx, 4
    mov [rbx + Server.act_tokens + rcx], rax
    mov rdx, ACT_TTL_NS
    add r12, rdx
    mov [rbx + Server.act_tokens + rcx + 8], r12
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; activation_redeem
;   Use a token
;   IN:  rdi = server*, rsi = the token
;   OUT: eax = 1 it was good (and is no longer), 0 not
; ---------------------------------------------------------------------------
global activation_redeem
activation_redeem:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    xor eax, eax
    test r12, r12
    jz .out
    call ut_time_now_ns
    xor ecx, ecx
.slot:
    mov edx, ecx
    shl edx, 4
    cmp [rbx + Server.act_tokens + rdx], r12
    jne .next
    cmp rax, [rbx + Server.act_tokens + rdx + 8]
    jae .next                           ; too late
    mov qword [rbx + Server.act_tokens + rdx], 0
    mov eax, 1
    jmp .out
.next:
    inc ecx
    cmp ecx, ACT_TOKENS
    jb .slot
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12

section .data
global activation_version
activation_version: dq 0x010000
