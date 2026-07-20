; =============================================================================
; Tattva OS — lib/mem/virt/hardware/kasan.asm
; =============================================================================
; Kernel Address Sanitizer (KASAN) & Fault Injection Engine (Feature 24).
; Detects invalid memory access attempts by mapping and auditing shadow bytes.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_HARDWARE_KASAN_ASM
%define LIB_MEM_VIRT_HARDWARE_KASAN_ASM

[BITS 64]

KASAN_SHADOW_OFFSET     equ 0x600000000000
KASAN_MAPPED_START      equ 0x600002000000
KASAN_MAPPED_END        equ 0x600002000000 + (512 * 4096)

; -----------------------------------------------------------------------------
; Section .text
; -----------------------------------------------------------------------------
section .text



; -----------------------------------------------------------------------------
; kasan_init — maps the system's KASAN shadow memory region and zeroes it
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global kasan_init
kasan_init:
    push rbx
    push r12
    push r13

    mov r12, 512                    ; 512 pages (covers 16MB of user virtual space)
    mov r13, KASAN_MAPPED_START     ; R13 = shadow start virtual address

.map_loop:
    test r12, r12
    jz .success

    ; Allocate physical frame for the shadow page
    call phys_alloc_page            ; RAX = physical page address (identity mapped)
    test rax, rax
    jz .fail
    mov rbx, rax                    ; RBX = physical page address

    ; Zero out the shadow page to avoid false positive violations
    mov rdi, rbx
    mov rsi, 4096
    call memzero

    ; Map shadow virtual page to physical frame
    mov rdi, r13                    ; RDI = virtual address
    mov rsi, rbx                    ; RSI = physical address
    mov rdx, 0x03                   ; RDX = flags (PAGE_PRESENT | PAGE_WRITABLE)
    call virt_map
    test rax, rax
    jz .fail

    add r13, 4096                   ; Move to next virtual shadow page
    dec r12
    jmp .map_loop

.success:
    mov rax, 1
    jmp .exit

.fail:
    xor rax, rax

.exit:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; kasan_check_address — queries shadow byte corresponding to a target address
; Input:
;   RDI = target_address (address to check)
; Output:
;   None (triggers kernel_panic on invalid access / non-zero shadow byte)
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global kasan_check_address
kasan_check_address:
    ; Calculate shadow address: (target_address >> 3) + KASAN_SHADOW_OFFSET
    mov rax, rdi
    shr rax, 3
    mov rcx, KASAN_SHADOW_OFFSET
    add rax, rcx                    ; RAX = shadow byte address

    ; Bounds check: ensure shadow address is within mapped KASAN shadow region
    mov rcx, KASAN_MAPPED_START
    cmp rax, rcx
    jb .safe_exit
    mov rcx, KASAN_MAPPED_END
    cmp rax, rcx
    jae .safe_exit

    ; Query the shadow byte
    movzx rcx, byte [rax]
    test rcx, rcx
    jnz .violation

.safe_exit:
    ret

.violation:
    lea rdi, [msg_kasan_violation]
    xor rsi, rsi
    call kernel_panic
    ret

; -----------------------------------------------------------------------------
; kasan_poison_address — poisons/unpoisons shadow byte for a target address
; Input:
;   RDI = target_address
;   RSI = poison_value (0 = clean, non-zero = poisoned)
; Output:
;   RAX = 1 on success, 0 on failure (out-of-bounds shadow address)
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global kasan_poison_address
kasan_poison_address:
    ; Calculate shadow address
    mov rax, rdi
    shr rax, 3
    mov rcx, KASAN_SHADOW_OFFSET
    add rax, rcx                    ; RAX = shadow byte address

    ; Bounds check
    mov rcx, KASAN_MAPPED_START
    cmp rax, rcx
    jb .fail
    mov rcx, KASAN_MAPPED_END
    cmp rax, rcx
    jae .fail

    ; Stamp poison value
    mov [rax], sil                  ; SIL = low byte of RSI
    mov rax, 1
    ret

.fail:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; Section .data
; -----------------------------------------------------------------------------
section .data

msg_kasan_violation: db "!!! KERNEL PANIC: KASAN Address Sanitizer Memory Violation Detected !!!", 0x0D, 0x0A, 0

section .text

%endif ; LIB_MEM_VIRT_HARDWARE_KASAN_ASM
