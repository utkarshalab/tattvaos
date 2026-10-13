; ============================================================================
; Accounting — Memory Accounting (per-client + global totals)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define Accounting_size    48

section .text

struc Accounting
    .server:         resq 1
    .total_mem:      resq 1
    .client_mem:     resq 1
    .buffer_mem:     resq 1
    .server_mem:     resq 1
    .peak_mem:       resq 1
endstruc

; ---------------------------------------------------------------------------
; accounting_init
; ---------------------------------------------------------------------------
global accounting_init
accounting_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, Accounting_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + Accounting.server], rdi
    mov qword [rbx + Accounting.total_mem], 0
    mov qword [rbx + Accounting.client_mem], 0
    mov qword [rbx + Accounting.buffer_mem], 0
    mov qword [rbx + Accounting.server_mem], 0
    mov qword [rbx + Accounting.peak_mem], 0
    mov qword [rdi + Server.accounting], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; accounting_add_client
; ---------------------------------------------------------------------------
global accounting_add_client
accounting_add_client:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ASSERT_PTR rsi
    add [rbx + Accounting.client_mem], rsi
    add [rbx + Accounting.total_mem], rsi
    mov rax, [rbx + Accounting.total_mem]
    cmp rax, [rbx + Accounting.peak_mem]
    jbe .done
    mov [rbx + Accounting.peak_mem], rax
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; accounting_remove_client
; ---------------------------------------------------------------------------
global accounting_remove_client
accounting_remove_client:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ASSERT_PTR rsi
    sub [rbx + Accounting.client_mem], rsi
    jns .no_under1
    mov qword [rbx + Accounting.client_mem], 0
.no_under1:
    sub [rbx + Accounting.total_mem], rsi
    jns .done
    mov qword [rbx + Accounting.total_mem], 0
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; accounting_add_buffer
; ---------------------------------------------------------------------------
global accounting_add_buffer
accounting_add_buffer:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ASSERT_PTR rsi
    add [rbx + Accounting.buffer_mem], rsi
    add [rbx + Accounting.total_mem], rsi
    mov rax, [rbx + Accounting.total_mem]
    cmp rax, [rbx + Accounting.peak_mem]
    jbe .done
    mov [rbx + Accounting.peak_mem], rax
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; accounting_remove_buffer
; ---------------------------------------------------------------------------
global accounting_remove_buffer
accounting_remove_buffer:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ASSERT_PTR rsi
    sub [rbx + Accounting.buffer_mem], rsi
    jns .no_under1
    mov qword [rbx + Accounting.buffer_mem], 0
.no_under1:
    sub [rbx + Accounting.total_mem], rsi
    jns .done
    mov qword [rbx + Accounting.total_mem], 0
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; accounting_snapshot
;   IN: rdi = accounting*, rsi = out_total*, rdx = out_client*,
;       rcx = out_buffer*, r8 = out_peak*
; ---------------------------------------------------------------------------
global accounting_snapshot
accounting_snapshot:
    PROLOGUE
    ASSERT_PTR rdi
    test rsi, rsi
    jz .s1
    mov rax, [rdi + Accounting.total_mem]
    mov [rsi], rax
.s1:
    test rdx, rdx
    jz .s2
    mov rax, [rdi + Accounting.client_mem]
    mov [rdx], rax
.s2:
    test rcx, rcx
    jz .s3
    mov rax, [rdi + Accounting.buffer_mem]
    mov [rcx], rax
.s3:
    test r8, r8
    jz .done
    mov rax, [rdi + Accounting.peak_mem]
    mov [r8], rax
.done:
    xor rax, rax
    leave
    ret

section .data
global accounting_version
accounting_version: dq 0x010000
