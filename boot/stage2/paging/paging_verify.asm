; =============================================================================
; Utkarsha OS — boot/stage2/paging/paging_verify.asm
; =============================================================================
; Verify page table correctness before enabling paging.
; Halts with error if any check fails.
; Call after paging_setup, before longmode_enter.
;
; Checks every active bootstrap entry before CR0.PG is set.  Exact comparisons
; deliberately reject USER, unexpected RW/PS bits, reserved high bits, and an
; executable page outside the two declared code windows.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef PAGING_VERIFY_ASM
%define PAGING_VERIFY_ASM

; =============================================================================
; paging_verify — check page tables before enabling paging
; Input:  page tables at PAGING_PML4
; Output: CF=0 all checks pass
;         CF=1 verification failed (caller should halt)
; Clobbers: none
; =============================================================================
[BITS 32]
paging_verify:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push esi

    ; Derive the expected NX high dword and validate the ULF executable bound
    ; again before using it as policy input.
    xor edx, edx
    call paging_nx_supported
    jc .nx_mask_ready
    mov edx, PTE_NX_BIT
.nx_mask_ready:
    cmp dword [KERNEL_LOAD + ULF_VERSION_OFF], ULF_VERSION
    jne .fail_policy
    mov esi, [KERNEL_LOAD + ULF_EXEC_SIZE_OFF]
    cmp esi, ULF_HEADER_SIZE
    jb .fail_policy
    test esi, ULF_EXEC_ALIGN - 1
    jnz .fail_policy
    cmp esi, ULF_MAX_EXEC_BYTES
    ja .fail_policy
    cmp esi, [KERNEL_LOAD + ULF_IMAGE_SIZE_OFF]
    ja .fail_policy
    add esi, KERNEL_LOAD            ; exclusive executable end
    jc .fail_policy

    ; PML4[0] is the only active root entry; every other slot must be zero.
    cmp dword [PAGING_PML4], PAGING_PDPT | PAGE_KERNEL
    jne .fail_root
    cmp dword [PAGING_PML4 + 4], 0
    jne .fail_root
    mov edi, PAGING_PML4 + 8
    mov ecx, 511
.pml4_zero_loop:
    cmp dword [edi], 0
    jne .fail_root
    cmp dword [edi + 4], 0
    jne .fail_root
    add edi, 8
    dec ecx
    jnz .pml4_zero_loop

    ; PDPT[0..3] point at four contiguous supervisor-only directories.
    mov edi, PAGING_PDPT
    mov ebx, PAGING_PD0
    mov ecx, 4
.pdpt_loop:
    mov eax, ebx
    or eax, PAGE_KERNEL
    cmp [edi], eax
    jne .fail_root
    cmp dword [edi + 4], 0
    jne .fail_root
    add ebx, 0x1000
    add edi, 8
    dec ecx
    jnz .pdpt_loop
    ; No hidden mappings are permitted in the remaining 508 PDPT slots.
    mov ecx, 508
.pdpt_zero_loop:
    cmp dword [edi], 0
    jne .fail_root
    cmp dword [edi + 4], 0
    jne .fail_root
    add edi, 8
    dec ecx
    jnz .pdpt_zero_loop

    ; The low 2MB must use PT0.  Accepting a huge mapping here would silently
    ; discard the 4KB executable/NX policy.
    cmp dword [PAGING_PD0], PAGING_PT0 | PAGE_KERNEL
    jne .fail_root
    cmp dword [PAGING_PD0 + 4], 0
    jne .fail_root

    ; Every remaining mapping from 2MB through 4GB is an exact, sequential,
    ; supervisor RW huge page and is NX whenever hardware supports NX.
    mov edi, PAGING_PD0 + 8
    mov ebx, 0x00200000
    mov ecx, 2047
.huge_loop:
    mov eax, ebx
    or eax, PAGE_KERNEL | PAGE_HUGE
    cmp [edi], eax
    jne .fail_huge
    cmp [edi + 4], edx
    jne .fail_huge
    add ebx, 0x00200000
    add edi, 8
    dec ecx
    jnz .huge_loop

    ; Verify all 512 low PTEs, including their exact execution policy.
    mov edi, PAGING_PT0
    xor ebx, ebx
    mov ecx, 512
.pt_loop:
    mov eax, ebx
    or eax, PAGE_KERNEL
    cmp ebx, KERNEL_LOAD
    jb .check_pt_low
    cmp ebx, esi
    jae .check_pt_low
    and eax, ~PAGE_RW               ; executable kernel pages must be RX
.check_pt_low:
    cmp [edi], eax
    jne .fail_pt

    mov eax, edx                    ; NX unless this page contains boot code
    cmp ebx, STAGE2_LOAD
    jb .check_kernel_exec
    cmp ebx, STAGE2_LOAD + STAGE2_SECTORS * 512
    jb .expect_exec
.check_kernel_exec:
    cmp ebx, KERNEL_LOAD
    jb .check_pt_high
    cmp ebx, esi
    jae .check_pt_high
.expect_exec:
    xor eax, eax
.check_pt_high:
    cmp [edi + 4], eax
    jne .fail_pt

    add ebx, 0x1000
    add edi, 8
    dec ecx
    jnz .pt_loop

    ; -------------------------------------------------------------------------
    ; All checks passed
    ; -------------------------------------------------------------------------
    mov esi, msg_paging_ok
    call uart_print_pm
    clc
    jmp .verify_done

.fail_root:
    mov esi, msg_fail_paging_root
    call uart_print_pm
    stc
    jmp .verify_done

.fail_huge:
    mov esi, msg_fail_paging_huge
    call uart_print_pm
    stc
    jmp .verify_done

.fail_pt:
    mov esi, msg_fail_paging_pt
    call uart_print_pm
    stc
    jmp .verify_done

.fail_policy:
    mov esi, msg_fail_paging_policy
    call uart_print_pm
    stc

.verify_done:
    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; =============================================================================
; Strings
; =============================================================================
msg_paging_ok:
    db "Paging verify: OK", 0x0D, 0x0A, 0
msg_fail_paging_root:
    db "Paging verify: FAIL root permissions/base", 0x0D, 0x0A, 0
msg_fail_paging_huge:
    db "Paging verify: FAIL huge-page permissions/base", 0x0D, 0x0A, 0
msg_fail_paging_pt:
    db "Paging verify: FAIL low-page permissions/base", 0x0D, 0x0A, 0
msg_fail_paging_policy:
    db "Paging verify: FAIL invalid ULF execution policy", 0x0D, 0x0A, 0

[BITS 16]

%endif ; PAGING_VERIFY_ASM
