; =============================================================================
; Tattva OS — boot/stage2/idt/idt64.asm
; =============================================================================
; Minimal emergency IDT for the interval between entering IA-32e mode and the
; kernel installing its full IDT.  The protected-mode IDT uses 8-byte gates;
; long mode requires 16-byte gates, so retaining the former across the far
; jump turns an otherwise diagnosable exception into a triple fault.
;
; Public entry points (all 64-bit):
;   idt64_init          — build all 32 gates and load IDTR (idempotent)
;   idt64_build_install — alias for idt64_init
;   idt64_install       — reload the already-built table
;   idt64_selftest      — execute INT3 and verify that it returns
;
; The table deliberately covers CPU exceptions only.  Callers must keep
; maskable interrupts disabled until the kernel installs its complete IDT.
; No TSS exists at this boot stage, so all gates use IST=0 and depend on the
; current stack being usable.  Unexpected exceptions print a compact UART
; diagnostic and halt permanently.
; =============================================================================

%ifndef IDT64_ASM
%define IDT64_ASM

%include "selectors.asm"

%ifdef IDT64_STANDALONE_CHECK
extern uart_print_64
extern uart_print_hex64
%endif

[BITS 64]

IDT64_VECTOR_COUNT equ 32
IDT64_GATE_SIZE    equ 16
IDT64_TYPE_INT     equ 0x8E         ; P=1, DPL=0, 64-bit interrupt gate

; =============================================================================
; Exception entry stubs
;
; Normalized stack on entry to idt64_common_handler:
;   [RSP +  0] vector
;   [RSP +  8] error code (real or synthetic zero)
;   [RSP + 16] interrupted RIP
;   [RSP + 24] interrupted CS
;   [RSP + 32] interrupted RFLAGS
; =============================================================================

%macro IDT64_STUB_NO_ERROR 1
idt64_vector_%1:
    push qword 0
    push qword %1
    jmp idt64_common_handler
%endmacro

%macro IDT64_STUB_ERROR 1
idt64_vector_%1:
    ; The processor has already pushed the exception error code.
    push qword %1
    jmp idt64_common_handler
%endmacro

%assign idt64_vector_number 0
%rep IDT64_VECTOR_COUNT
    ; #DF, #TS, #NP, #SS, #GP, #PF, #AC, #CP, #VC and #SX push error codes.
    %if idt64_vector_number = 8  || idt64_vector_number = 10 || \
        idt64_vector_number = 11 || idt64_vector_number = 12 || \
        idt64_vector_number = 13 || idt64_vector_number = 14 || \
        idt64_vector_number = 17 || idt64_vector_number = 21 || \
        idt64_vector_number = 29 || idt64_vector_number = 30
        IDT64_STUB_ERROR idt64_vector_number
    %else
        IDT64_STUB_NO_ERROR idt64_vector_number
    %endif
    %assign idt64_vector_number idt64_vector_number + 1
%endrep

; =============================================================================
; idt64_common_handler — return only from the intentional INT3 self-test
; =============================================================================
idt64_common_handler:
    cmp qword [rsp], 3
    jne .unexpected
    cmp byte [rel idt64_selftest_active], 1
    jne .unexpected

    ; INT3 has no error code.  Drop vector + synthetic error and resume at the
    ; instruction following INT3.  No GPR was changed on this returning path.
    mov byte [rel idt64_selftest_active], 0
    add rsp, 16
    iretq

.unexpected:
    cli
    cld
    mov r12, rsp                    ; stable pointer to normalized CPU frame

    lea rsi, [rel idt64_msg_fatal]
    call uart_print_64

    lea rsi, [rel idt64_msg_vector]
    call uart_print_64
    mov rax, [r12 + 0]
    call uart_print_hex64

    lea rsi, [rel idt64_msg_error]
    call uart_print_64
    mov rax, [r12 + 8]
    call uart_print_hex64

    lea rsi, [rel idt64_msg_rip]
    call uart_print_64
    mov rax, [r12 + 16]
    call uart_print_hex64

    lea rsi, [rel idt64_msg_cr2]
    call uart_print_64
    mov rax, cr2
    call uart_print_hex64

    lea rsi, [rel idt64_msg_cr3]
    call uart_print_64
    mov rax, cr3
    call uart_print_hex64

    lea rsi, [rel idt64_msg_crlf]
    call uart_print_64

.halt:
    cli
    hlt
    jmp .halt

; =============================================================================
; idt64_init / idt64_build_install — construct and load the emergency IDT
;
; Output: IDTR references idt64_table, interrupts disabled, DF clear
; Clobbers: flags only (all GPRs preserved)
; =============================================================================
idt64_init:
idt64_build_install:
    cli
    cld
    push rax
    push rcx
    push rsi
    push rdi

    lea rsi, [rel idt64_handler_table]
    lea rdi, [rel idt64_table]
    mov ecx, IDT64_VECTOR_COUNT

.build_gate:
    lodsq                           ; RAX = full handler address

    mov word [rdi + 0], ax          ; offset bits 15:0
    mov word [rdi + 2], SEL_CODE64  ; 64-bit ring-0 code selector
    mov byte [rdi + 4], 0           ; IST=0, reserved bits zero
    mov byte [rdi + 5], IDT64_TYPE_INT

    shr rax, 16
    mov word [rdi + 6], ax          ; offset bits 31:16
    shr rax, 16
    mov dword [rdi + 8], eax        ; offset bits 63:32
    mov dword [rdi + 12], 0         ; architecturally reserved

    add rdi, IDT64_GATE_SIZE
    dec ecx
    jnz .build_gate

    lidt [rel idt64_descriptor]
    mov byte [rel idt64_ready], 1

    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

; =============================================================================
; idt64_install — reload an emergency table previously built by idt64_init
;
; Intended for recovery paths after firmware/real-mode activity changed IDTR.
; The routine fails closed if no table has been built in this stage2 image.
; =============================================================================
idt64_install:
    cli
    cld
    cmp byte [rel idt64_ready], 1
    jne idt64_not_ready
    lidt [rel idt64_descriptor]
    ret

; =============================================================================
; idt64_selftest — verify a real 64-bit gate and IRETQ round trip
;
; Output: CF=0 on return.  Any failure prints a diagnostic and halts.
; Preserves: all GPRs and the caller's IF state
; =============================================================================
idt64_selftest:
    pushfq
    cli
    cmp byte [rel idt64_ready], 1
    jne .not_ready

    mov byte [rel idt64_selftest_active], 1
    int3
    cmp byte [rel idt64_selftest_active], 0
    jne .failed

    popfq
    clc
    ret

.not_ready:
    add rsp, 8                      ; discard saved RFLAGS before fail-stop
    jmp idt64_not_ready

.failed:
    add rsp, 8
    lea rsi, [rel idt64_msg_selftest]
    call uart_print_64
    jmp idt64_fail_halt

idt64_not_ready:
    lea rsi, [rel idt64_msg_not_ready]
    call uart_print_64

idt64_fail_halt:
    cli
    hlt
    jmp idt64_fail_halt

; =============================================================================
; Handler address vector and 16-byte gate storage
; =============================================================================
align 8
idt64_handler_table:
%assign idt64_vector_number 0
%rep IDT64_VECTOR_COUNT
    dq idt64_vector_%[idt64_vector_number]
    %assign idt64_vector_number idt64_vector_number + 1
%endrep

align 16
idt64_table:
    times IDT64_VECTOR_COUNT * IDT64_GATE_SIZE db 0
idt64_table_end:

align 8
idt64_descriptor:
    dw idt64_table_end - idt64_table - 1
    dq idt64_table

idt64_ready:           db 0
idt64_selftest_active: db 0

idt64_msg_fatal:     db 0x0D, 0x0A, "EARLY64 EXCEPTION: stage2 fail-stop", 0x0D, 0x0A, 0
idt64_msg_vector:    db "  vector=", 0
idt64_msg_error:     db " error=", 0
idt64_msg_rip:       db " rip=", 0
idt64_msg_cr2:       db " cr2=", 0
idt64_msg_cr3:       db " cr3=", 0
idt64_msg_crlf:      db 0x0D, 0x0A, 0
idt64_msg_selftest:  db "FATAL: stage2 IDT64 INT3 self-test did not return cleanly", 0x0D, 0x0A, 0
idt64_msg_not_ready: db "FATAL: stage2 IDT64 installed before construction", 0x0D, 0x0A, 0

; The stage2 aggregate source resumes assembling real-mode modules after each
; included component.  Keep that convention for callers that include us near
; the other IDT files.
[BITS 16]

%endif ; IDT64_ASM
