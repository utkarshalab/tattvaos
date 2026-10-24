; =============================================================================
; Utkarsha OS — kernel/exec/exports.asm
; =============================================================================
; What the kernel exports to UBF programs: the names their imports resolve
; against (docs/UBF_SPEC.md §6), and the small functions behind them.
;
; Adding an export is one UBF_EXPORT line: the name's FNV-1a hash is
; computed when the kernel is assembled, so a lookup compares hashes first
; and the name only on a match.
; =============================================================================

%ifndef KERNEL_EXEC_EXPORTS_ASM
%define KERNEL_EXEC_EXPORTS_ASM

%include "kernel/exec/ubf.inc"

; UBF_EXPORT "name", symbol — one ubf_export_t in .data, the name in .rodata
%macro UBF_EXPORT 2
    %strlen %%len %1
    %assign %%h 0x811C9DC5
    %assign %%i 1
    %rep %%len
        %substr %%c %1 %%i
        %assign %%h ((%%h ^ %%c) * 0x01000193) & 0xFFFFFFFF
        %assign %%i %%i + 1
    %endrep
    section .rodata
%%name: db %1, 0
    align 8, db 0                   ; the ULF image stays a multiple of 8 bytes
    section .data
    dd %%h
    dd %%len
    dq %%name
    dq %2
%endmacro

section .data
align 8
global ubf_kernel_exports
ubf_kernel_exports:
    UBF_EXPORT "ut_console_print", ut_console_print
    UBF_EXPORT "ut_yield", ut_yield
ubf_kernel_exports_end:

section .text

; -----------------------------------------------------------------------------
; ut_console_print — write a NUL-terminated string to the console
; Input:  RDI = the string
; Output: none; preserves every register
; -----------------------------------------------------------------------------
global ut_console_print
ut_console_print:
    push rsi
    mov rsi, rdi
    call uart_print_str
    pop rsi
    ret

; -----------------------------------------------------------------------------
; ut_yield — let the other ready fibers run
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global ut_yield
ut_yield:
    jmp fiber_yield

; -----------------------------------------------------------------------------
; ubf_export_find — the kernel symbol an import names
; Input:  RDI = the name (NUL-terminated), ESI = its FNV-1a hash
; Output: RAX = the symbol's address, or 0 when the kernel exports no such name
; Clobbers: RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
global ubf_export_find
ubf_export_find:
    lea r8, [rel ubf_kernel_exports]
.next:
    lea rax, [rel ubf_kernel_exports_end]
    cmp r8, rax
    jae .none
    cmp [r8 + ubf_export_t.hash], esi
    jne .skip
    ; same hash: compare the names, including the terminating NUL
    mov r9, [r8 + ubf_export_t.name]
    xor ecx, ecx
.cmp:
    mov dl, [rdi + rcx]
    cmp dl, [r9 + rcx]
    jne .skip
    inc rcx
    test dl, dl
    jnz .cmp
    mov rax, [r8 + ubf_export_t.addr]
    ret
.skip:
    add r8, ubf_export_t_size
    jmp .next
.none:
    xor eax, eax
    ret

%endif ; KERNEL_EXEC_EXPORTS_ASM
