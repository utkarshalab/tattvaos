; =============================================================================
; Tattva OS — boot/survive/recover.asm
; =============================================================================
; Handles the transition from 64-bit long mode back to 16-bit real mode,
; reloads KERNEL.ULF, transitions back to 64-bit, restores the snapshot state,
; and resumes kernel execution (warm boot recovery).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (Long Mode) & real mode (16-bit)
; =============================================================================

%ifndef SURVIVE_RECOVER_ASM
%define SURVIVE_RECOVER_ASM

%include "config.asm"

[BITS 64]

; =============================================================================
; survive_recover — main recovery entry point (called in 64-bit mode)
; =============================================================================
survive_recover:
    cli                             ; disable interrupts

    ; Push 16-bit Compatibility CS (0x18) and the offset of compat_mode
    push word 0x18                  ; CS = SEL_CODE16
    lea rax, [compat_mode]
    push rax
    retf                            ; far return jumps to 16-bit protected mode

[BITS 16]
compat_mode:
    ; Load 16-bit data selector into data segment registers
    mov ax, 0x10                    ; SEL_DATA64 (writable data segment)
    mov ds, ax
    mov es, ax
    mov ss, ax

    ; Disable Paging (clear CR0.PG)
    mov eax, cr0
    and eax, ~0x80000000            ; clear PG (bit 31)
    mov cr0, eax

    ; Disable Long Mode (clear EFER.LME)
    mov ecx, 0xC0000080             ; EFER MSR
    rdmsr
    and eax, ~0x00000100            ; clear LME (bit 8)
    wrmsr

    ; Disable Protected Mode (clear CR0.PE)
    mov eax, cr0
    and eax, ~0x00000001            ; clear PE (bit 0)
    mov cr0, eax

    ; Far jump to enter 16-bit real mode and reload CS (0x0000)
    jmp 0x0000:real_mode_entry

real_mode_entry:
    ; We are now in 16-bit real mode!
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x8000                  ; temporary real-mode stack pointer

    ; Load real-mode IVT (limit 0x3FF, base 0)
    lidt [real_idt_descriptor]

    sti                             ; enable interrupts for BIOS disk calls

    ; Print message via UART (using 16-bit stage2 print routines)
    mov si, msg_reloading
    call uart_println

    ; Reload the image straight to 1MB. This uses the same streaming loader the
    ; normal boot path does, so recovery reloads the whole kernel rather than a
    ; 32KB prefix — the old raw fallback here read KERNEL_SECTORS into the
    ; bounce buffer and left the rest of a 9.3MB image unwritten.
    call kernel_stream_load
    test ax, ax
    jnz .load_success

    mov si, msg_recover_failed
    call uart_println

.load_success:
    cli                             ; disable interrupts before switching modes

    ; Re-enable Protected Mode
    mov eax, cr0
    or eax, 1                       ; set PE (bit 0)
    mov cr0, eax

    ; Load GDT
    lgdt [gdt_descriptor]

    ; Re-enable PAE
    mov eax, cr4
    or eax, 0x20                    ; set PAE (bit 5)
    mov cr4, eax

    ; Load PML4 page table pointer into CR3
    mov eax, 0x10000                ; PAGING_PML4
    mov cr3, eax

    ; Re-enable LME in EFER MSR
    mov ecx, 0xC0000080
    rdmsr
    or eax, 0x00000100              ; set LME (bit 8)
    wrmsr

    ; Re-enable Paging
    mov eax, cr0
    or eax, 0x80000000              ; set PG (bit 31)
    mov cr0, eax

    ; Far jump back to 64-bit mode using retf
    push word 0x08                  ; CS = SEL_CODE64 (0x08)
    push word longmode_recovery     ; IP = 16-bit offset of longmode_recovery
    retf

[BITS 64]
longmode_recovery:
    ; Reload data segment registers
    mov ax, 0x10                    ; SEL_DATA64
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; Setup temporary safe stack
    mov rsp, 0x9C000                ; STACK_LONG

    ; No copy step: kernel_stream_load wrote the image directly to KERNEL_LOAD
    ; through the flat-ES window while still in real mode.

    ; Restore CR3 (pristine PML4 address)
    mov rax, [SURVIVE_PAGE + 0x90]
    mov cr3, rax

    ; Restore CR0
    mov rax, [SURVIVE_PAGE + 0x80]
    mov cr0, rax

    ; Restore CR4
    mov rax, [SURVIVE_PAGE + 0x98]
    mov cr4, rax

    ; Restore GDTR and IDTR
    lgdt [SURVIVE_PAGE + 0xE0]
    lidt [SURVIVE_PAGE + 0xF0]

    ; Restore Stack contents
    cld                             ; Clear direction flag for forward copy
    mov rdi, [SURVIVE_PAGE + 0x38]   ; RDI = pristine RSP
    mov rsi, SURVIVE_PAGE + 0x100   ; RSI = stack backup
    mov rcx, 192                    ; 192 * 8 = 1536 bytes
    rep movsq

    ; Restore general-purpose registers (except RSP and RAX)
    mov rbx, [SURVIVE_PAGE + 0x08]
    mov rcx, [SURVIVE_PAGE + 0x10]
    mov rdx, [SURVIVE_PAGE + 0x18]
    mov rsi, [SURVIVE_PAGE + 0x20]
    mov rdi, [SURVIVE_PAGE + 0x28]
    mov rbp, [SURVIVE_PAGE + 0x30]
    mov r8,  [SURVIVE_PAGE + 0x40]
    mov r9,  [SURVIVE_PAGE + 0x48]
    mov r10, [SURVIVE_PAGE + 0x50]
    mov r11, [SURVIVE_PAGE + 0x58]
    mov r12, [SURVIVE_PAGE + 0x60]
    mov r13, [SURVIVE_PAGE + 0x68]
    mov r14, [SURVIVE_PAGE + 0x70]
    mov r15, [SURVIVE_PAGE + 0x78]

    ; Restore stack pointer
    mov rsp, [SURVIVE_PAGE + 0x38]

    ; Restore RFLAGS
    push qword [SURVIVE_PAGE + 0xD0]
    popfq

    ; Restore RAX (last register)
    mov rax, [SURVIVE_PAGE]

    ; Jump to the pristine RIP
    jmp [SURVIVE_PAGE + 0xD8]

[BITS 16]

align 2
real_idt_descriptor:
    dw 0x3FF                        ; limit (1024 bytes)
    dd 0x00000000                   ; base address (0x00000000)

; 16-bit strings
msg_reloading:          db "Recovery: reloading kernel...", 0
msg_recover_failed:     db "Recovery: FAILED to reload kernel! Rebooting...", 0

%endif ; SURVIVE_RECOVER_ASM
