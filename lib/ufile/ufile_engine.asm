; =============================================================================
; Tattva OS — lib/ufile/ufile_engine.asm
; =============================================================================
; Bytecode Pattern Matcher Engine (YARA/eBPF-Style Rule Evaluator).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "ufile.inc"

; Opcodes
OP_MATCH_BYTES  equ 1              ; Match N bytes at current offset
OP_CHECK_OFFSET equ 2              ; Move offset pointer
OP_AND          equ 3              ; Logical AND condition
OP_OR           equ 4              ; Logical OR condition
OP_END          equ 0              ; End of bytecode rule

section .text

; -----------------------------------------------------------------------------
; ufile_eval_rule — Evaluate bytecode rule against buffer
; Input:  RDI = Buffer pointer
;         RSI = Buffer length
;         RDX = Bytecode rule program pointer
; Output: RAX = 1 if rule matches, 0 if match failed
; -----------------------------------------------------------------------------
ufile_eval_rule:
    push rbx
    push rcx
    push r8
    push r9

    mov r8, rdi                     ; R8 = buffer
    mov r9, rsi                     ; R9 = length
    mov rbx, rdx                    ; RBX = rule pointer
    xor rcx, rcx                    ; Current buffer offset = 0

.fetch_op:
    mov al, [rbx]                   ; Read opcode byte
    inc rbx
    
    cmp al, OP_END
    je .match_success
    cmp al, OP_CHECK_OFFSET
    je .do_offset
    cmp al, OP_MATCH_BYTES
    je .do_match
    jmp .match_failed

.do_offset:
    mov rcx, [rbx]                  ; Read 64-bit target offset
    add rbx, 8
    
    ; Bounds check
    cmp rcx, r9
    jae .match_failed
    jmp .fetch_op

.do_match:
    mov rdi, [rbx]                  ; RDI = match len
    add rbx, 8
    
    ; Bounds check
    mov rax, rcx
    add rax, rdi
    cmp rax, r9
    jae .match_failed

    ; Compare bytes
    push rsi
    push rdi
    mov rsi, rbx                    ; Pattern pointer
    lea rdi, [r8 + rcx]             ; Buffer offset
    mov rcx, [rbx - 8]              ; Match len
    repe cmpsb
    pop rdi
    pop rsi
    jne .match_failed

    add rbx, [rbx - 8]              ; Skip pattern bytes in rule
    jmp .fetch_op

.match_success:
    mov rax, 1
    jmp .done

.match_failed:
    xor rax, rax

.done:
    pop r9
    pop r8
    pop rcx
    pop rbx
    ret
