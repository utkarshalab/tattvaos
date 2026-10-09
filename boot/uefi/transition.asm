; =============================================================================
; Tattva OS — boot/uefi/transition.asm
; =============================================================================
; Loader-owned x86-64 execution environment for the UEFI -> kernel handoff.
; Firmware allocates the page tables, GDT/IDT storage, and transition stack;
; the final stub lives alone on an aligned PE .text page already owned by the
; loaded EFI image.  No firmware CR3, descriptor table, stack, SIMD state, or
; segment-selector assumption crosses into the kernel.
; =============================================================================

%ifndef UEFI_TRANSITION_ASM
%define UEFI_TRANSITION_ASM

%include "protocol.asm"
%include "transition_tables.asm"

[BITS 64]
default rel

UEFI_TRANSITION_STATE_PAGES     equ 7
UEFI_TRANSITION_STATE_BYTES     equ UEFI_TRANSITION_STATE_PAGES * 4096
UEFI_TRANSITION_GDT_OFF         equ 0x0000
UEFI_TRANSITION_IDT_OFF         equ 0x1000
UEFI_TRANSITION_CONTEXT_OFF     equ 0x2000
UEFI_TRANSITION_GDTR_OFF        equ UEFI_TRANSITION_CONTEXT_OFF
UEFI_TRANSITION_IDTR_OFF        equ UEFI_TRANSITION_CONTEXT_OFF + 16
UEFI_TRANSITION_BOOT_INFO_OFF   equ UEFI_TRANSITION_CONTEXT_OFF + 64
; BootInfo ABI v2 occupies context+64 .. context+176.  Keep the canonical
; memory map disjoint and retain a guard before the transition stack.
UEFI_TRANSITION_E820_OFF        equ UEFI_TRANSITION_CONTEXT_OFF + 192
UEFI_TRANSITION_STACK_OFF       equ 0x3000
UEFI_TRANSITION_STACK_TOP_OFF   equ 0x7000
UEFI_TRANSITION_GDT_LIMIT       equ 4095
UEFI_TRANSITION_IDT_LIMIT       equ 4095

UEFI_FEATURE_LONG_MODE          equ 1 << 0
UEFI_FEATURE_NX                 equ 1 << 1
UEFI_FEATURE_SSE                equ 1 << 2
UEFI_FEATURE_SSE2               equ 1 << 3
UEFI_FEATURE_AVX                equ 1 << 4
UEFI_FEATURE_AVX2               equ 1 << 5

UEFI_GDT_CODE64                 equ 0x00AF9B000000FFFF
UEFI_GDT_DATA64                 equ 0x00CF93000000FFFF

section .data
align 8
uefi_transition_tables:        dq 0
uefi_transition_state:         dq 0
uefi_ap_trampoline_page:       dq 0
uefi_transition_stub_page_addr:dq 0
uefi_transition_features:      dd 0
uefi_transition_firmware_cs:   dw 0
uefi_transition_ready:         db 0
                                db 0

section .text

; -----------------------------------------------------------------------------
; uefi_transition_detect_cpu
; CF=0, EAX=BootInfo feature mask when the kernel's mandatory CPU contract is
; usable.  CF=1 otherwise.  NX is optional; SSE/SSE2/SSE3/XSAVE/AVX/FMA/AVX2
; and XCR0 state components 0..2 are mandatory.
; -----------------------------------------------------------------------------
uefi_transition_detect_cpu:
    push rbx

    mov rax, cr0
    test rax, 1 << 0               ; PE
    jz .unsupported
    bt rax, 31                     ; PG
    jnc .unsupported

    mov rax, cr4
    test rax, 1 << 5               ; PAE
    jz .unsupported
    test rax, 1 << 12              ; LA57 cannot be toggled while PG=1
    jnz .unsupported

    mov ecx, 0xC0000080            ; EFER
    rdmsr
    mov r9d, eax
    and r9d, (1 << 8) | (1 << 10)  ; LME + LMA
    cmp r9d, (1 << 8) | (1 << 10)
    jne .unsupported

    xor eax, eax
    cpuid
    mov r10d, eax
    cmp r10d, 0x0D
    jb .unsupported

    mov eax, 1
    cpuid
    mov eax, edx
    and eax, (1 << 25) | (1 << 26) ; SSE + SSE2
    cmp eax, (1 << 25) | (1 << 26)
    jne .unsupported
    test ecx, 1 << 0               ; SSE3
    jz .unsupported
    test ecx, 1 << 12              ; FMA3
    jz .unsupported
    test ecx, 1 << 26              ; XSAVE
    jz .unsupported
    test ecx, 1 << 28              ; AVX
    jz .unsupported

    mov eax, 7
    xor ecx, ecx
    cpuid
    test ebx, 1 << 5               ; AVX2
    jz .unsupported

    mov eax, 0x0D
    xor ecx, ecx
    cpuid
    and eax, 0x07                  ; x87 + SSE + AVX state components
    cmp eax, 0x07
    jne .unsupported

    mov r11d, UEFI_FEATURE_LONG_MODE | UEFI_FEATURE_SSE | \
                UEFI_FEATURE_SSE2 | UEFI_FEATURE_AVX | UEFI_FEATURE_AVX2

    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .features_ready
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29              ; long mode must still be enumerated
    jz .unsupported
    test edx, 1 << 20
    jz .features_ready
    or r11d, UEFI_FEATURE_NX

.features_ready:
    mov eax, r11d
    pop rbx
    clc
    ret
.unsupported:
    xor eax, eax
    pop rbx
    stc
    ret

; -----------------------------------------------------------------------------
; uefi_transition_verify_ready
; Revalidates all immutable transition metadata.  It is called after prepare
; and again immediately before ExitBootServices.
; -----------------------------------------------------------------------------
uefi_transition_verify_ready:
    push rbx
    push rbp
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov r12, [rel uefi_transition_tables]
    test r12, r12
    jz .invalid
    test r12, 0xFFF
    jnz .invalid
    mov rax, r12
    add rax, UEFI_TRANSITION_TABLE_BYTES
    jc .invalid
    mov r15, UEFI_LOW_4G_LIMIT
    cmp rax, r15
    ja .invalid
    mov r9, rax                    ; table arena end

    mov r13, [rel uefi_transition_state]
    test r13, r13
    jz .invalid
    test r13, 0xFFF
    jnz .invalid
    mov rax, r13
    add rax, UEFI_TRANSITION_STATE_BYTES
    jc .invalid
    cmp rax, r15
    ja .invalid
    mov r10, rax                   ; transition-state end

    mov r14, [rel uefi_transition_stub_page_addr]
    test r14, 0xFFF
    jnz .invalid
    mov rax, r14
    add rax, 4096
    jc .invalid
    cmp rax, r15
    ja .invalid
    mov r11, rax                   ; transition-stub end

    mov rbp, [rel uefi_ap_trampoline_page]
    cmp rbp, 0x10000
    jb .invalid
    test rbp, 0xFFF
    jnz .invalid
    mov rax, rbp
    add rax, BOOT_AP_TRAMPOLINE_BYTES
    jc .invalid
    cmp rax, 0xA0000
    ja .invalid

    cmp r13, r9
    jae .state_table_disjoint
    cmp r12, r10
    jb .invalid
.state_table_disjoint:
    cmp r13, r11
    jae .state_stub_disjoint
    cmp r14, r10
    jb .invalid
.state_stub_disjoint:
    cmp rbp, r9
    jae .trampoline_table_disjoint
    mov rax, rbp
    add rax, BOOT_AP_TRAMPOLINE_BYTES
    cmp r12, rax
    jb .invalid
.trampoline_table_disjoint:
    cmp rbp, r10
    jae .trampoline_state_disjoint
    mov rax, rbp
    add rax, BOOT_AP_TRAMPOLINE_BYTES
    cmp r13, rax
    jb .invalid
.trampoline_state_disjoint:
    cmp rbp, r11
    jae .trampoline_stub_disjoint
    mov rax, rbp
    add rax, BOOT_AP_TRAMPOLINE_BYTES
    cmp r14, rax
    jb .invalid
.trampoline_stub_disjoint:

    lea rax, [rel uefi_transition_stub_page]
    cmp rax, r14
    jne .invalid
    lea rax, [rel uefi_transition_stub_end]
    cmp rax, r14
    jbe .invalid
    mov rdx, r14
    add rdx, 4096
    cmp rax, rdx
    ja .invalid

    mov eax, [rel uefi_transition_features]
    mov r11d, eax
    and eax, UEFI_FEATURE_LONG_MODE | UEFI_FEATURE_SSE | \
             UEFI_FEATURE_SSE2 | UEFI_FEATURE_AVX | UEFI_FEATURE_AVX2
    cmp eax, UEFI_FEATURE_LONG_MODE | UEFI_FEATURE_SSE | \
             UEFI_FEATURE_SSE2 | UEFI_FEATURE_AVX | UEFI_FEATURE_AVX2
    jne .invalid
    mov eax, r11d
    and eax, ~(UEFI_FEATURE_LONG_MODE | UEFI_FEATURE_NX | UEFI_FEATURE_SSE | \
               UEFI_FEATURE_SSE2 | UEFI_FEATURE_AVX | UEFI_FEATURE_AVX2)
    jnz .invalid

    mov rdi, r12
    mov rsi, [rel uefi_kernel_addr]
    mov rdx, [rel uefi_kernel_pages]
    test rdx, rdx
    jz .invalid
    cmp rdx, ULF_MAX_MEMORY_BYTES / 4096
    ja .invalid
    shl rdx, 12

    mov rax, rsi
    add rax, rdx
    jc .invalid
    cmp r13, rax
    jae .state_backing_disjoint
    cmp rsi, r10
    jb .invalid
.state_backing_disjoint:
    mov rax, rsi
    add rax, rdx
    cmp rbp, rax
    jae .trampoline_backing_disjoint
    mov rax, rbp
    add rax, BOOT_AP_TRAMPOLINE_BYTES
    cmp rsi, rax
    jb .invalid
.trampoline_backing_disjoint:
    mov rax, KERNEL_LOAD
    add rax, rdx
    jc .invalid
    cmp r13, rax
    jae .state_virtual_disjoint
    cmp r10, KERNEL_LOAD
    ja .invalid
.state_virtual_disjoint:

    mov rax, [rel uefi_kernel_memory_size]
    test rax, rax
    jz .invalid
    cmp rax, ULF_MAX_MEMORY_BYTES
    ja .invalid
    mov r9, rax
    add r9, 4095
    jc .invalid
    shr r9, 12
    cmp r9, [rel uefi_kernel_pages]
    jne .invalid

    mov r9, [rel uefi_kernel_size]
    cmp r9, ULF_HEADER_SIZE
    jb .invalid
    cmp r9, rax
    ja .invalid

    mov rcx, [rel uefi_kernel_exec_size]
    cmp rcx, ULF_HEADER_SIZE
    jb .invalid
    cmp rcx, r9
    ja .invalid

    mov rax, [rel uefi_kernel_entry]
    mov r9, KERNEL_LOAD + ULF_HEADER_SIZE
    cmp rax, r9
    jb .invalid
    mov r9, KERNEL_LOAD
    add r9, rcx
    jc .invalid
    cmp rax, r9
    jae .invalid

    mov r8, r14
    xor r9d, r9d
    test r11d, UEFI_FEATURE_NX
    jz .verify_tables
    mov r9d, UEFI_TRANSITION_FLAG_NX
.verify_tables:
    call uefi_transition_verify_tables
    jc .invalid

    cmp qword [r13 + UEFI_TRANSITION_GDT_OFF + 0], 0
    jne .invalid
    mov rax, UEFI_GDT_CODE64
    cmp qword [r13 + UEFI_TRANSITION_GDT_OFF + 8], rax
    jne .invalid
    mov rax, UEFI_GDT_DATA64
    cmp qword [r13 + UEFI_TRANSITION_GDT_OFF + 16], rax
    jne .invalid

    movzx ebx, word [rel uefi_transition_firmware_cs]
    test ebx, 7
    jnz .invalid
    test ebx, ebx
    jz .invalid
    cmp ebx, 0xFF8
    ja .invalid
    cmp ebx, 0x10
    je .invalid
    cmp ebx, 0x08
    je .gdt_ready
    mov rax, UEFI_GDT_CODE64
    cmp qword [r13 + rbx], rax
    jne .invalid
.gdt_ready:

    cmp word [r13 + UEFI_TRANSITION_GDTR_OFF], UEFI_TRANSITION_GDT_LIMIT
    jne .invalid
    cmp qword [r13 + UEFI_TRANSITION_GDTR_OFF + 2], r13
    jne .invalid

    cmp word [r13 + UEFI_TRANSITION_IDTR_OFF], UEFI_TRANSITION_IDT_LIMIT
    jne .invalid
    mov rax, r13
    add rax, UEFI_TRANSITION_IDT_OFF
    cmp qword [r13 + UEFI_TRANSITION_IDTR_OFF + 2], rax
    jne .invalid

    lea r15, [rel uefi_transition_exception]
    lea rdi, [r13 + UEFI_TRANSITION_IDT_OFF]
    mov ecx, 256
.idt_loop:
    cmp word [rdi + 2], bx
    jne .invalid
    cmp byte [rdi + 4], 0
    jne .invalid
    cmp byte [rdi + 5], 0x8E
    jne .invalid
    cmp dword [rdi + 12], 0
    jne .invalid

    movzx eax, word [rdi]
    movzx edx, word [rdi + 6]
    shl rdx, 16
    or rax, rdx
    mov edx, [rdi + 8]
    shl rdx, 32
    or rax, rdx
    cmp rax, r15
    jne .invalid

    add rdi, 16
    dec ecx
    jnz .idt_loop

    clc
    jmp .done
.invalid:
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uefi_transition_prepare
; RCX = EFI_SYSTEM_TABLE.  Allocates/builds all transition-owned memory before
; the final GetMemoryMap window.  RAX = EFI_STATUS.
; -----------------------------------------------------------------------------
uefi_transition_prepare:
    push rbp
    mov rbp, rsp
    sub rsp, 128

    mov [rbp - 8], rcx
    mov [rbp - 40], rbx
    mov [rbp - 48], rsi
    mov [rbp - 56], rdi
    mov [rbp - 64], r12
    mov [rbp - 72], r13

    cmp byte [rel uefi_transition_ready], 0
    jne .load_error
    cmp qword [rel uefi_transition_tables], 0
    jne .load_error
    cmp qword [rel uefi_transition_state], 0
    jne .load_error
    cmp qword [rel uefi_ap_trampoline_page], 0
    jne .load_error

    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES]
    test rax, rax
    jz .unsupported
    mov [rbp - 16], rax

    call uefi_transition_detect_cpu
    jc .unsupported
    mov [rel uefi_transition_features], eax

    mov ax, cs
    test ax, 7                     ; require ring-0 GDT selector, never an LDT
    jnz .unsupported
    movzx eax, ax
    test eax, eax
    jz .unsupported
    cmp eax, 0xFF8
    ja .unsupported
    cmp eax, 0x10                  ; reserved for the kernel data descriptor
    je .unsupported
    mov [rel uefi_transition_firmware_cs], ax

    lea rax, [rel uefi_transition_stub_page]
    test rax, 0xFFF
    jnz .load_error
    mov rdx, rax
    add rdx, 4096
    jc .load_error
    mov r8, UEFI_LOW_4G_LIMIT
    cmp rdx, r8
    ja .load_error
    mov [rel uefi_transition_stub_page_addr], rax

    ; Reserve one firmware-owned SIPI page below the legacy VGA aperture.
    ; The kernel fills it only after ExitBootServices, then seals its exact
    ; 4 KiB PTE read-only/executable before issuing any Startup IPI.
    mov qword [rel uefi_ap_trampoline_page], 0x9FFFF
    mov ecx, EFI_ALLOCATE_MAX_ADDRESS
    mov edx, EFI_LOADER_DATA
    mov r8d, 1
    lea r9, [rel uefi_ap_trampoline_page]
    mov rax, [rbp - 16]
    mov rax, [rax + BS_ALLOCATE_PAGES]
    call rax
    test rax, rax
    jnz .allocation_failed_trampoline

    mov rax, [rel uefi_ap_trampoline_page]
    cmp rax, 0x10000
    jb .load_error_cleanup
    test rax, 0xFFF
    jnz .load_error_cleanup
    add rax, BOOT_AP_TRAMPOLINE_BYTES
    jc .load_error_cleanup
    cmp rax, 0xA0000
    ja .load_error_cleanup

    ; Acquire all page-table pages in one contiguous, low-4-GiB arena.
    mov eax, 0xFFFFFFFF
    mov [rel uefi_transition_tables], rax
    mov ecx, EFI_ALLOCATE_MAX_ADDRESS
    mov edx, EFI_LOADER_DATA
    mov r8d, UEFI_TRANSITION_TABLE_PAGES
    lea r9, [rel uefi_transition_tables]
    mov rax, [rbp - 16]
    mov rax, [rax + BS_ALLOCATE_PAGES]
    call rax
    test rax, rax
    jnz .allocation_failed_tables

    ; One GDT page, one IDT page, one context page, and a 16 KiB stack.
    mov eax, 0xFFFFFFFF
    mov [rel uefi_transition_state], rax
    mov ecx, EFI_ALLOCATE_MAX_ADDRESS
    mov edx, EFI_LOADER_DATA
    mov r8d, UEFI_TRANSITION_STATE_PAGES
    lea r9, [rel uefi_transition_state]
    mov rax, [rbp - 16]
    mov rax, [rax + BS_ALLOCATE_PAGES]
    call rax
    test rax, rax
    jnz .allocation_failed_state

    mov r12, [rel uefi_transition_tables]
    test r12, r12
    jz .load_error_cleanup
    test r12, 0xFFF
    jnz .load_error_cleanup
    mov rax, r12
    add rax, UEFI_TRANSITION_TABLE_BYTES
    jc .load_error_cleanup
    mov rdx, UEFI_LOW_4G_LIMIT
    cmp rax, rdx
    ja .load_error_cleanup

    mov r13, [rel uefi_transition_state]
    test r13, r13
    jz .load_error_cleanup
    test r13, 0xFFF
    jnz .load_error_cleanup
    mov rcx, r13
    add rcx, UEFI_TRANSITION_STATE_BYTES
    jc .load_error_cleanup
    cmp rcx, rdx
    ja .load_error_cleanup

    ; Firmware allocations must be disjoint.  Recheck that contract before
    ; writing either returned span.
    cmp r13, rax
    jae .owned_spans_disjoint
    cmp r12, rcx
    jb .load_error_cleanup
.owned_spans_disjoint:

    ; Validate the firmware-owned kernel backing and its page-rounded mapping.
    mov rbx, [rel uefi_kernel_addr]
    test rbx, rbx
    jz .load_error_cleanup
    test rbx, 0xFFF
    jnz .load_error_cleanup
    mov rsi, [rel uefi_kernel_pages]
    test rsi, rsi
    jz .load_error_cleanup
    cmp rsi, ULF_MAX_MEMORY_BYTES / 4096
    ja .load_error_cleanup
    shl rsi, 12
    mov rdi, [rel uefi_kernel_memory_size]
    test rdi, rdi
    jz .load_error_cleanup
    cmp rdi, rsi
    ja .load_error_cleanup
    cmp rsi, ULF_MAX_MEMORY_BYTES
    ja .load_error_cleanup
    mov rax, rbx
    add rax, rsi
    jc .load_error_cleanup
    cmp rax, rdx
    ja .load_error_cleanup

    cmp r12, rax
    jae .tables_kernel_disjoint
    mov rdi, r12
    add rdi, UEFI_TRANSITION_TABLE_BYTES
    cmp rbx, rdi
    jb .load_error_cleanup
.tables_kernel_disjoint:
    cmp r13, rax
    jae .state_kernel_disjoint
    mov rdi, r13
    add rdi, UEFI_TRANSITION_STATE_BYTES
    cmp rbx, rdi
    jb .load_error_cleanup
.state_kernel_disjoint:

    ; State is dereferenced through its identity address after CR3 changes, so
    ; the linked kernel virtual window may not shadow it.
    mov rax, KERNEL_LOAD
    add rax, rsi
    jc .load_error_cleanup
    cmp r13, rax
    jae .state_virtual_disjoint
    mov rdi, r13
    add rdi, UEFI_TRANSITION_STATE_BYTES
    cmp rdi, KERNEL_LOAD
    ja .load_error_cleanup
.state_virtual_disjoint:

    ; The transition-state allocation must also be disjoint from the PE page
    ; that remains executable across the CR3 switch.
    mov rax, [rel uefi_transition_stub_page_addr]
    mov rcx, rax
    add rcx, 4096
    mov rdi, r13
    add rdi, UEFI_TRANSITION_STATE_BYTES
    cmp r13, rcx
    jae .state_stub_disjoint
    cmp rax, rdi
    jb .load_error_cleanup
.state_stub_disjoint:

    ; Build and immediately verify the exact page-table policy.
    mov rdi, r12
    mov rsi, rbx
    mov rdx, [rel uefi_kernel_pages]
    shl rdx, 12
    mov rcx, [rel uefi_kernel_exec_size]
    mov r8, [rel uefi_transition_stub_page_addr]
    xor r9d, r9d
    test dword [rel uefi_transition_features], UEFI_FEATURE_NX
    jz .build_tables
    mov r9d, UEFI_TRANSITION_FLAG_NX
.build_tables:
    call uefi_transition_build_tables
    jc .load_error_cleanup

    ; Zero state, then install selectors 0x08/0x10 plus a code descriptor at
    ; the firmware's current CS selector.  That extra descriptor keeps NMIs
    ; deliverable throughout the IDT/GDT switch window.
    cld
    mov rdi, r13
    mov ecx, UEFI_TRANSITION_STATE_BYTES / 8
    xor eax, eax
    rep stosq

    mov rax, UEFI_GDT_CODE64
    mov [r13 + UEFI_TRANSITION_GDT_OFF + 8], rax
    mov rax, UEFI_GDT_DATA64
    mov [r13 + UEFI_TRANSITION_GDT_OFF + 16], rax
    movzx ebx, word [rel uefi_transition_firmware_cs]
    cmp ebx, 0x08
    je .gdt_built
    mov rax, UEFI_GDT_CODE64
    mov [r13 + rbx], rax
.gdt_built:

    mov word [r13 + UEFI_TRANSITION_GDTR_OFF], UEFI_TRANSITION_GDT_LIMIT
    mov [r13 + UEFI_TRANSITION_GDTR_OFF + 2], r13
    mov word [r13 + UEFI_TRANSITION_IDTR_OFF], UEFI_TRANSITION_IDT_LIMIT
    mov rax, r13
    add rax, UEFI_TRANSITION_IDT_OFF
    mov [r13 + UEFI_TRANSITION_IDTR_OFF + 2], rax

    ; All 256 vectors terminate in the same self-contained UART sink.  Before
    ; CS is reloaded, gates use the firmware selector copied into our GDT.
    lea r15, [rel uefi_transition_exception]
    lea rdi, [r13 + UEFI_TRANSITION_IDT_OFF]
    mov ecx, 256
.fill_idt:
    mov rax, r15
    mov [rdi], ax
    mov [rdi + 2], bx
    mov byte [rdi + 4], 0
    mov byte [rdi + 5], 0x8E
    shr rax, 16
    mov [rdi + 6], ax
    shr rax, 16
    mov [rdi + 8], eax
    mov dword [rdi + 12], 0
    add rdi, 16
    dec ecx
    jnz .fill_idt

    call uefi_transition_verify_ready
    jc .load_error_cleanup

    mov byte [rel uefi_transition_ready], 1
    xor eax, eax
    jmp .return

.allocation_failed_tables:
    mov qword [rel uefi_transition_tables], 0
    mov [rbp - 24], rax
    jmp .cleanup
.allocation_failed_trampoline:
    mov qword [rel uefi_ap_trampoline_page], 0
    mov [rbp - 24], rax
    jmp .cleanup
.allocation_failed_state:
    mov qword [rel uefi_transition_state], 0
    mov [rbp - 24], rax
    jmp .cleanup
.unsupported:
    mov rax, EFI_UNSUPPORTED
    jmp .fail_status
.load_error:
    mov rax, EFI_LOAD_ERROR
    jmp .fail_status
.load_error_cleanup:
    mov rax, EFI_LOAD_ERROR
.fail_status:
    mov [rbp - 24], rax
.cleanup:
    mov rcx, [rbp - 8]
    call uefi_transition_release
    mov rax, [rbp - 24]

.return:
    mov r13, [rbp - 72]
    mov r12, [rbp - 64]
    mov rdi, [rbp - 56]
    mov rsi, [rbp - 48]
    mov rbx, [rbp - 40]
    mov rsp, rbp
    pop rbp
    ret

; -----------------------------------------------------------------------------
; uefi_transition_release
; RCX = EFI_SYSTEM_TABLE.  Frees all transition allocations on a pre-EBS
; failure and returns the first FreePages status.
; -----------------------------------------------------------------------------
uefi_transition_release:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov qword [rbp - 8], 0
    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES]
    test rax, rax
    jz .release_unsupported
    mov [rbp - 16], rax

    mov rcx, [rel uefi_transition_state]
    test rcx, rcx
    jz .release_tables
    mov edx, UEFI_TRANSITION_STATE_PAGES
    mov rax, [rbp - 16]
    mov rax, [rax + BS_FREE_PAGES]
    call rax
    test rax, rax
    jz .clear_state
    mov [rbp - 8], rax
.clear_state:
    mov qword [rel uefi_transition_state], 0

.release_tables:
    mov rcx, [rel uefi_transition_tables]
    test rcx, rcx
    jz .release_trampoline
    mov edx, UEFI_TRANSITION_TABLE_PAGES
    mov rax, [rbp - 16]
    mov rax, [rax + BS_FREE_PAGES]
    call rax
    test rax, rax
    jz .clear_tables
    cmp qword [rbp - 8], 0
    jne .clear_tables
    mov [rbp - 8], rax
.clear_tables:
    mov qword [rel uefi_transition_tables], 0

.release_trampoline:
    mov rcx, [rel uefi_ap_trampoline_page]
    test rcx, rcx
    jz .release_done
    mov edx, 1
    mov rax, [rbp - 16]
    mov rax, [rax + BS_FREE_PAGES]
    call rax
    test rax, rax
    jz .clear_trampoline
    cmp qword [rbp - 8], 0
    jne .clear_trampoline
    mov [rbp - 8], rax
.clear_trampoline:
    mov qword [rel uefi_ap_trampoline_page], 0

.release_done:
    mov qword [rel uefi_transition_stub_page_addr], 0
    mov dword [rel uefi_transition_features], 0
    mov word [rel uefi_transition_firmware_cs], 0
    mov byte [rel uefi_transition_ready], 0
    mov rax, [rbp - 8]
    jmp .release_return
.release_unsupported:
    mov rax, EFI_UNSUPPORTED
.release_return:
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; Self-contained final transition page
; =============================================================================
; This page is part of the firmware-owned EFI image's code section.  The owned
; page tables map exactly this page RX, so no instruction fetched after CR3 is
; loaded depends on the rest of the PE image remaining executable.
align 4096, db 0x90
uefi_transition_stub_page:
uefi_transition_stub:
    cli
    cld

    ; Handoff register contract:
    ;   RAX=owned CR3, RBX=&GDTR, RCX=&IDTR, RDX=stack top
    ;   RSI=kernel entry, RDI=BootInfo, R8D=feature flags
    mov r12, rax
    mov r13, rbx
    mov r14, rcx
    mov r15, rsi
    mov r10, rdi
    mov r11d, r8d
    mov rsp, rdx
    and rsp, -16

    mov rbx, [r14 + 2]             ; IDT base for selector patching
    lidt [r14]                     ; gates initially use firmware CS
    lgdt [r13]                     ; same selector is valid in the owned GDT

    push qword 2                   ; deterministic RFLAGS: reserved bit only
    popfq
    xor eax, eax
    mov cr8, rax

    ; PCIDE cannot be cleared safely while the active CR3 carries a nonzero
    ; PCID.  First reload the firmware root with PCID zero.
    mov rax, cr4
    test rax, 1 << 17
    jz .pcid_clear
    mov rax, cr3
    and rax, -4096
    mov cr3, rax
.pcid_clear:

    ; Keep only the state the kernel entry contract requires.
    mov eax, (1 << 5) | (1 << 9) | (1 << 10) | (1 << 18)
    mov cr4, rax                    ; PAE, OSFXSR, OSXMMEXCPT, OSXSAVE

    xor ecx, ecx
    mov eax, 0x07                  ; x87 + SSE + AVX
    xor edx, edx
    xsetbv

    mov rax, cr0
    or rax, (1 << 0) | (1 << 1) | (1 << 5) | (1 << 16)
    bts rax, 31
    and rax, ~((1 << 2) | (1 << 3) | (1 << 18) | (1 << 29) | (1 << 30))
    mov cr0, rax

    mov ecx, 0xC0000080            ; normalize EFER, including NX policy
    rdmsr
    and eax, (1 << 8) | (1 << 10)  ; retain LME/LMA only
    test r11d, UEFI_FEATURE_NX
    jz .efer_ready
    or eax, 1 << 11
.efer_ready:
    xor edx, edx
    wrmsr

    xor eax, eax
    xor edx, edx
    mov ecx, 0xC0000100            ; FS_BASE
    wrmsr
    mov ecx, 0xC0000101            ; GS_BASE
    wrmsr
    mov ecx, 0xC0000102            ; KERNEL_GS_BASE
    wrmsr

    mov cr3, r12

    push qword 0x08
    lea rax, [rel .owned_cs]
    push rax
    retfq
.owned_cs:
    ; Both the old firmware selector and 0x08 are valid during this loop, so
    ; an NMI cannot observe a gate/GDT mismatch.
    mov rdi, rbx
    mov ecx, 256
.patch_idt_selectors:
    mov word [rdi + 2], 0x08
    add rdi, 16
    dec ecx
    jnz .patch_idt_selectors

    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    call uefi_transition_uart_init

    mov rdi, r10                    ; System V kernel ABI: BootInfo in RDI
    jmp r15

; Any exception/NMI during the transition gets a firmware-independent UART
; diagnostic and a permanent halt.  It intentionally never returns, so vector
; error-code differences do not affect its stack contract.
uefi_transition_exception:
    cli
    cld
    call uefi_transition_uart_init
    lea rsi, [rel uefi_transition_exception_message]
.exception_print:
    lodsb
    test al, al
    jz .exception_halt
    mov bl, al
.exception_wait:
    mov dx, 0x3FD
    in al, dx
    test al, 0x20
    jz .exception_wait
    mov dx, 0x3F8
    mov al, bl
    out dx, al
    jmp .exception_print
.exception_halt:
    hlt
    jmp .exception_halt

uefi_transition_uart_init:
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8
    mov al, 1
    out dx, al
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 0x03
    out dx, al
    mov dx, 0x3FA
    mov al, 0xC7
    out dx, al
    mov dx, 0x3FC
    mov al, 0x0B
    out dx, al
    ret

uefi_transition_exception_message:
    db "UEFI TRANSITION EXCEPTION", 0x0D, 0x0A, 0
uefi_transition_stub_end:

times 4096 - ($ - uefi_transition_stub_page) db 0xCC

%endif ; UEFI_TRANSITION_ASM
