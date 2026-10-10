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

REC_MSR_EFER        equ 0xC0000080
REC_EFER_LME        equ (1 << 8)
REC_EFER_NXE        equ (1 << 11)
REC_CR0_PE          equ (1 << 0)
REC_CR0_MP          equ (1 << 1)
REC_CR0_EM          equ (1 << 2)
REC_CR0_TS          equ (1 << 3)
REC_CR0_NE          equ (1 << 5)
REC_CR0_WP          equ (1 << 16)
REC_CR0_PG          equ (1 << 31)
REC_CR4_PAE         equ (1 << 5)
REC_CR4_OSFXSR      equ (1 << 9)
REC_CR4_OSXMMEXCPT  equ (1 << 10)
REC_CR4_LA57        equ (1 << 12)
REC_CR4_PCIDE       equ (1 << 17)

; =============================================================================
; survive_recover — main recovery entry point (called in 64-bit mode)
; =============================================================================
survive_recover:
    cli                             ; disable interrupts

    ; Keep NMI from arriving while IDTR changes through 64-, 16-, real-, and
    ; 32-bit formats. The original CMOS selector/mask is restored once the
    ; emergency long-mode IDT is active again.
    in al, 0x70
    mov [rel longmode_cmos_index], al
    or al, 0x80
    out 0x70, al

    ; Quiesce the local APIC while firmware owns interrupt delivery. x2APIC
    ; cannot enter the reserved EN=0/EXTD=1 state, so disable both mode bits
    ; together and preserve the exact value for the controlled restore below.
    mov ecx, 0x1B
    rdmsr
    mov [rel recovery_apic_base_low], eax
    mov [rel recovery_apic_base_high], edx
    and eax, ~((1 << 11) | (1 << 10))
    wrmsr

    ; CR0.PG cannot be cleared while PCID is enabled.  Select PCID zero on the
    ; current root first, then disable PCIDE while the existing mapping still
    ; keeps this low-memory trampoline reachable.
    mov rax, cr4
    test rax, REC_CR4_PCIDE
    jz .pcid_disabled
    mov rax, cr3
    and rax, -4096
    mov cr3, rax
    mov rax, cr4
    and rax, ~REC_CR4_PCIDE
    mov cr4, rax
.pcid_disabled:

    ; The kernel installs a different GDT (its selector 0x18 is user data), so
    ; recovery must install the boot GDT before selecting its 16-bit code
    ; descriptor.  Long mode consumes a ten-byte GDTR operand.
    lgdt [rel gdt_descriptor64]

    ; RETFQ consumes two eight-byte slots.  A word selector plus bare RETF
    ; misaligns the frame and faults before compatibility mode is reached.
    push qword SEL_CODE16
    lea rax, [rel recovery_compat16]
    push rax
    retfq

[BITS 16]
recovery_compat16:
    ; We are in 16-bit compatibility mode with the boot GDT active.
    mov ax, SEL_DATA64
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, STACK_PROT

    ; IA-32e mode can only be left from a compatibility-mode code segment.
    mov eax, cr0
    and eax, ~REC_CR0_PG
    mov cr0, eax

    mov ecx, REC_MSR_EFER
    rdmsr
    and eax, ~REC_EFER_LME
    wrmsr

    mov eax, cr4
    and eax, ~(REC_CR4_PAE | REC_CR4_LA57 | REC_CR4_PCIDE)
    mov cr4, eax

    mov eax, cr0
    and eax, ~REC_CR0_PE
    mov cr0, eax

    ; Reload CS immediately after clearing PE.
    jmp 0x0000:recovery_real16

recovery_real16:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x8000                  ; temporary real-mode stack pointer

    ; Load real-mode IVT (limit 0x3FF, base 0)
    lidt [real_idt_descriptor]

    ; Restore the masks inherited from firmware at the original stage2 entry,
    ; then dismiss any stale in-service state before allowing BIOS IRQs.
    mov al, [boot_pic_master_mask]
    out 0x21, al
    mov al, [boot_pic_slave_mask]
    out 0xA1, al
    mov al, 0x20
    out 0xA0, al
    out 0x20, al

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
    cli
.load_halt:
    hlt
    jmp .load_halt

.load_success:
    cli                             ; disable interrupts before switching modes

    ; Load the six-byte real/protected-mode GDTR before setting PE.  The far
    ; jump must immediately follow CR0.PE; executing a transition sequence in
    ; a stale real-mode CS cache is not architecturally sound.
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, REC_CR0_PE
    mov cr0, eax
    jmp SEL_CODE32:recovery_pm32

[BITS 32]
; Rebuild the feature word from hardware rather than trusting low memory that
; the crashed kernel could have overwritten. This mirrors cpu_detect's usable
; feature policy and refreshes cpu_max_leaf for simd_enable.
recovery_detect_cpu_features:
    mov dword [FEATURES_DEST], 0

    xor eax, eax
    cpuid
    mov [cpu_max_leaf], eax
    mov edi, eax

    cmp edi, 1
    jb .extended
    mov eax, 1
    cpuid
    test edx, 1 << 25
    jz .no_sse
    or dword [FEATURES_DEST], CPU_FEAT_SSE
.no_sse:
    test edx, 1 << 26
    jz .no_sse2
    or dword [FEATURES_DEST], CPU_FEAT_SSE2
.no_sse2:
    mov eax, ecx
    and eax, (1 << 26) | (1 << 28)
    cmp eax, (1 << 26) | (1 << 28)
    jne .no_avx
    or dword [FEATURES_DEST], CPU_FEAT_AVX
.no_avx:

    cmp edi, 7
    jb .extended
    mov eax, 7
    xor ecx, ecx
    cpuid
    test dword [FEATURES_DEST], CPU_FEAT_AVX
    jz .extended
    test ebx, 1 << 5
    jz .extended
    or dword [FEATURES_DEST], CPU_FEAT_AVX2

.extended:
    mov eax, 0x80000000
    cpuid
    mov [cpu_max_ext_leaf], eax
    cmp eax, 0x80000001
    jb .failed
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29
    jz .failed
    or dword [FEATURES_DEST], CPU_FEAT_LM
    test edx, 1 << 20
    jz .required
    or dword [FEATURES_DEST], CPU_FEAT_NX

.required:
    mov eax, [FEATURES_DEST]
    and eax, CPU_FEAT_LM | CPU_FEAT_SSE | CPU_FEAT_SSE2
    cmp eax, CPU_FEAT_LM | CPU_FEAT_SSE | CPU_FEAT_SSE2
    jne .failed
    clc
    ret
.failed:
    stc
    ret

recovery_pm32:
    mov ax, SEL_DATA64
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, STACK_PROT
    cld

    call recovery_detect_cpu_features
    jc recovery_cpu_halt

    ; Reinstate the APIC mode active at recovery entry. Re-enter xAPIC first
    ; when restoring x2APIC; disabled -> reserved and direct x2APIC downgrade
    ; transitions are not valid architectural state changes.
    mov ecx, 0x1B
    mov eax, [recovery_apic_base_low]
    mov edx, [recovery_apic_base_high]
    test eax, 1 << 10
    jz .restore_apic_base
    and eax, ~(1 << 10)
    wrmsr
    mov eax, [recovery_apic_base_low]
    mov edx, [recovery_apic_base_high]
.restore_apic_base:
    wrmsr

    call gdt_verify
    jc recovery_gdt_halt

    ; Do not trust the page tables left behind by a crashed kernel.  Rebuild
    ; the boot identity map from constants, then verify its structural links
    ; before loading it into CR3.
    call idt_setup
    call paging_setup
    call paging_verify
    jc recovery_pm32_halt

    call simd_enable
    jc recovery_simd_halt

    mov eax, cr4
    or eax, REC_CR4_PAE | REC_CR4_OSFXSR | REC_CR4_OSXMMEXCPT
    mov cr4, eax

    mov eax, PAGING_PML4
    mov cr3, eax

    mov ecx, REC_MSR_EFER
    rdmsr
    or eax, REC_EFER_LME
    and eax, ~REC_EFER_NXE
    mov ebx, [FEATURES_DEST]
    test ebx, CPU_FEAT_NX
    jz .no_nx
    or eax, REC_EFER_NXE
.no_nx:
    wrmsr

    mov eax, cr0
    or eax, REC_CR0_PE | REC_CR0_PG | REC_CR0_WP | REC_CR0_NE | REC_CR0_MP
    and eax, ~(REC_CR0_EM | REC_CR0_TS)
    mov cr0, eax

    ; A far jump loads a 64-bit CS and serializes the paging transition.
    jmp SEL_CODE64:longmode_recovery

recovery_pm32_halt:
    mov esi, msg_recover_paging_failed
    jmp recovery_pm32_fatal
recovery_cpu_halt:
    mov esi, msg_recover_cpu_failed
    jmp recovery_pm32_fatal
recovery_gdt_halt:
    mov esi, msg_recover_gdt_failed
    jmp recovery_pm32_fatal
recovery_simd_halt:
    mov esi, msg_recover_simd_failed
recovery_pm32_fatal:
    call uart_print_pm
    cli
.halt:
    hlt
    jmp .halt

[BITS 64]
longmode_recovery:
    mov rsp, STACK_LONG

    ; Firmware mode restored a real-mode IVT. Install valid 16-byte gates
    ; before descriptor reloads, validation, or saved-state access.
    call idt64_init
    call idt64_selftest
    mov al, [rel longmode_cmos_index]
    out 0x70, al

    ; Reload data segment registers
    mov ax, 0x10                    ; SEL_DATA64
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    call longmode_verify_state
    jc recovery_transition_halt
    lea rsi, [rel msg_recover_transition_ok]
    call uart_print_64

    ; No copy step: kernel_stream_load wrote the image directly to KERNEL_LOAD
    ; through the flat-ES window while still in real mode.

    ; The streaming loader validates the metadata sector before loading, but
    ; it rereads that sector with the rest of the image.  Validate the bytes
    ; that actually landed at KERNEL_LOAD, including the complete additive
    ; checksum, before restoring any state that can transfer control to them.
    call recovery_validate_ulf
    test rax, rax
    jz recovery_validation_halt

    ; Recovery resumes the pristine pre-entry snapshot, which starts the
    ; kernel as a fresh boot.  Match the cold path by clearing every byte not
    ; present in the file, including allocation-page padding.  The validator
    ; has already bounded and authenticated both sizes.
    mov edi, KERNEL_LOAD
    mov eax, [KERNEL_LOAD + ULF_IMAGE_SIZE_OFF]
    add rdi, rax                    ; first byte absent from the file
    mov ecx, [KERNEL_LOAD + ULF_MEMORY_SIZE_OFF]
    add rcx, 4095
    and rcx, -4096                  ; page-rounded footprint length
    add rcx, KERNEL_LOAD
    sub rcx, rdi
    xor eax, eax
    cld
    rep stosb

    ; Recheck the immutable snapshot after disk I/O and both mode transitions.
    ; Panic log/crash-state regions are intentionally outside its CRC range.
    call survive_checksum_verify
    test rax, rax
    jz recovery_snapshot_halt

    ; The pristine snapshot was captured on the boot PML4.  Refuse to load an
    ; unexpected root even if a future caller stamps a self-consistent but
    ; semantically invalid snapshot.
    cmp qword [SURVIVE_PAGE + 0x90], PAGING_PML4
    jne recovery_snapshot_halt

    ; Restore CR3 (newly rebuilt pristine PML4 address)
    mov rax, [SURVIVE_PAGE + 0x90]
    mov cr3, rax

    ; Restore CR4
    mov rax, [SURVIVE_PAGE + 0x98]
    mov cr4, rax

    ; Restore CR0
    mov rax, [SURVIVE_PAGE + 0x80]
    mov cr0, rax

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

; =============================================================================
; recovery_validate_ulf — validate the exact image reloaded into KERNEL_LOAD.
; Output: RAX=1 on success; RAX=0 and RSI=diagnostic string on failure.
; =============================================================================
recovery_validate_ulf:
    cmp dword [KERNEL_LOAD + ULF_MAGIC_OFF], ULF_MAGIC
    jne .bad_magic

    mov ecx, [KERNEL_LOAD + ULF_IMAGE_SIZE_OFF]
    test ecx, 7
    jnz .bad_size
    cmp ecx, ULF_HEADER_SIZE
    jb .bad_size
    cmp ecx, ULF_MAX_IMAGE_BYTES
    ja .bad_size

    ; Add every qword modulo 2^64 while treating the checksum field as zero.
    mov rsi, KERNEL_LOAD
    mov ebx, ecx
    shr ebx, 3
    xor rax, rax
    xor edx, edx
.checksum_loop:
    cmp edx, ULF_CHECKSUM_OFF
    je .skip_checksum
    add rax, [rsi + rdx]
.skip_checksum:
    add edx, 8
    dec ebx
    jnz .checksum_loop
    cmp rax, [KERNEL_LOAD + ULF_CHECKSUM_OFF]
    jne .bad_checksum

    cmp dword [KERNEL_LOAD + ULF_VERSION_OFF], ULF_VERSION
    jne .bad_header
    mov edx, [KERNEL_LOAD + ULF_EXEC_SIZE_OFF]
    cmp edx, ULF_HEADER_SIZE
    jb .bad_header
    test edx, ULF_EXEC_ALIGN - 1
    jnz .bad_header
    cmp edx, ecx
    ja .bad_header
    cmp edx, ULF_MAX_EXEC_BYTES
    ja .bad_header

    mov rax, [KERNEL_LOAD + ULF_ENTRY_OFF]
    cmp rax, KERNEL_LOAD + ULF_HEADER_SIZE
    jb .bad_entry
    add rdx, KERNEL_LOAD
    cmp rax, rdx
    jae .bad_entry

    ; Validate the complete file+BSS footprint before recovery uses it to
    ; reproduce cold-boot zeroing.
    cmp dword [KERNEL_LOAD + ULF_MEMORY_SIZE_OFF + 4], 0
    jne .bad_header
    mov edx, [KERNEL_LOAD + ULF_MEMORY_SIZE_OFF]
    cmp edx, ecx
    jb .bad_header
    test edx, 7
    jnz .bad_header
    cmp edx, ULF_MAX_MEMORY_BYTES
    ja .bad_header
    add edx, KERNEL_LOAD
    jc .bad_header

    mov eax, 1
    ret

.bad_magic:
    lea rsi, [rel msg_recover_bad_magic]
    jmp .bad
.bad_size:
    lea rsi, [rel msg_recover_bad_size]
    jmp .bad
.bad_checksum:
    lea rsi, [rel msg_recover_bad_checksum]
    jmp .bad
.bad_header:
    lea rsi, [rel msg_recover_bad_header]
    jmp .bad
.bad_entry:
    lea rsi, [rel msg_recover_bad_entry]
.bad:
    xor eax, eax
    ret

recovery_validation_halt:
    call uart_print_64
    cli
.halt:
    hlt
    jmp .halt

recovery_snapshot_halt:
    lea rsi, [rel msg_recover_bad_snapshot]
    call uart_print_64
    cli
.halt:
    hlt
    jmp .halt

recovery_transition_halt:
    lea rsi, [rel msg_recover_transition_failed]
    call uart_print_64
    cli
.halt:
    hlt
    jmp .halt

[BITS 16]

align 2
real_idt_descriptor:
    dw 0x3FF                        ; limit (1024 bytes)
    dd 0x00000000                   ; base address (0x00000000)

; 16-bit strings
msg_reloading:          db "Recovery: reloading kernel...", 0
msg_recover_failed:     db "Recovery: FAILED to reload kernel; HALT", 0
msg_recover_paging_failed: db "Recovery: FAILED to rebuild page tables; HALT", 0x0D, 0x0A, 0
msg_recover_cpu_failed:    db "Recovery: CPU feature revalidation failed; HALT", 0x0D, 0x0A, 0
msg_recover_gdt_failed:    db "Recovery: GDT revalidation failed; HALT", 0x0D, 0x0A, 0
msg_recover_simd_failed:   db "Recovery: SIMD/XCR0 revalidation failed; HALT", 0x0D, 0x0A, 0
msg_recover_transition_ok: db "Recovery long-mode transition verify: OK", 0x0D, 0x0A, 0
msg_recover_transition_failed: db "Recovery long-mode transition verify: FAIL", 0x0D, 0x0A, 0
msg_recover_bad_magic:    db "Recovery: reloaded ULF has bad magic; HALT", 0x0D, 0x0A, 0
msg_recover_bad_size:     db "Recovery: reloaded ULF has bad size; HALT", 0x0D, 0x0A, 0
msg_recover_bad_checksum: db "Recovery: reloaded ULF checksum mismatch; HALT", 0x0D, 0x0A, 0
msg_recover_bad_header:   db "Recovery: reloaded ULF header unsupported; HALT", 0x0D, 0x0A, 0
msg_recover_bad_entry:    db "Recovery: reloaded ULF entry invalid; HALT", 0x0D, 0x0A, 0
msg_recover_bad_snapshot: db "Recovery: pristine snapshot invalid; HALT", 0x0D, 0x0A, 0

align 4
recovery_apic_base_low:  dd 0
recovery_apic_base_high: dd 0

%endif ; SURVIVE_RECOVER_ASM
