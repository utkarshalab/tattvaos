; =============================================================================
; Utkarsha OS — boot/uefi/transition_tables.asm
; =============================================================================
; Firmware-independent construction and exact verification of the UEFI
; transition root.  The flat kernel remains linked at virtual 1 MiB, but its
; bytes may live in any firmware-owned contiguous physical allocation below
; 4 GiB.  Every 2 MiB region touched by that virtual mapping, its physical
; alias, or the transition stub is split into 4 KiB leaves.
;
; Arena:
;   page 0      PML4
;   page 1      PDPT
;   pages 2..5  PD0..PD3
;   pages 6..72 deterministic pool of 67 leaf page tables
;
; 67 is the exact worst case for a 64 MiB kernel:
;   33 virtual regions + 33 disjoint physical regions + 1 stub region.
; =============================================================================

%ifndef UEFI_TRANSITION_TABLES_ASM
%define UEFI_TRANSITION_TABLES_ASM

%include "config.asm"

[BITS 64]

UEFI_TRANSITION_ROOT_PAGES    equ 6
UEFI_TRANSITION_PT_PAGES      equ 67
UEFI_TRANSITION_TABLE_PAGES   equ UEFI_TRANSITION_ROOT_PAGES + UEFI_TRANSITION_PT_PAGES
UEFI_TRANSITION_TABLE_BYTES   equ UEFI_TRANSITION_TABLE_PAGES * 4096
UEFI_TRANSITION_PML4_OFF      equ 0x0000
UEFI_TRANSITION_PDPT_OFF      equ 0x1000
UEFI_TRANSITION_PD_OFF        equ 0x2000
UEFI_TRANSITION_PT_POOL_OFF   equ 0x6000

UEFI_TRANSITION_FLAG_NX       equ 1 << 0

UEFI_PTE_PRESENT              equ 1 << 0
UEFI_PTE_RW                   equ 1 << 1
UEFI_PTE_HUGE                 equ 1 << 7
UEFI_PTE_NX                   equ 1 << 63

UEFI_LOW_4G_LIMIT             equ 0x0000000100000000
UEFI_2M_BYTES                 equ 0x200000

section .text

; -----------------------------------------------------------------------------
; uefi_transition_validate_table_inputs
; Internal/native ABI shared by builder and verifier:
;   RDI = aligned table arena
;   RSI = aligned physical backing for the kernel
;   RDX = page-rounded kernel memory footprint
;   RCX = validated/page-aligned executable-prefix size
;   R8  = aligned transition-stub page
;   R9  = policy flags
; Inputs are preserved.  No memory is touched.
; -----------------------------------------------------------------------------
uefi_transition_validate_table_inputs:
    test rdi, rdi
    jz .invalid
    test rdi, 0xFFF
    jnz .invalid
    mov rax, rdi
    add rax, UEFI_TRANSITION_TABLE_BYTES
    jc .invalid
    mov r10, UEFI_LOW_4G_LIMIT
    cmp rax, r10
    ja .invalid

    test rsi, rsi
    jz .invalid
    test rsi, 0xFFF
    jnz .invalid
    test rdx, rdx
    jz .invalid
    test rdx, 0xFFF
    jnz .invalid
    cmp rdx, ULF_MAX_MEMORY_BYTES
    ja .invalid
    mov r11, rsi
    add r11, rdx                   ; physical kernel end
    jc .invalid
    cmp r11, r10
    ja .invalid

    test rcx, rcx
    jz .invalid
    test rcx, ULF_EXEC_ALIGN - 1
    jnz .invalid
    cmp rcx, ULF_MAX_EXEC_BYTES
    ja .invalid
    cmp rcx, rdx
    ja .invalid

    mov rax, KERNEL_LOAD
    add rax, rdx                   ; linked virtual kernel end
    jc .invalid
    cmp rax, r10
    ja .invalid

    test r8, 0xFFF
    jnz .invalid
    mov r10, r8
    add r10, 4096
    jc .invalid
    mov rax, UEFI_LOW_4G_LIMIT
    cmp r10, rax
    ja .invalid

    mov rax, r9
    and rax, ~UEFI_TRANSITION_FLAG_NX
    jnz .invalid

    ; A non-identity backing may not partially overlap the linked virtual
    ; window: that would make the direct-map alias and kernel mapping collide.
    cmp rsi, KERNEL_LOAD
    je .kernel_ranges_ready
    mov rax, KERNEL_LOAD
    add rax, rdx
    cmp rsi, rax
    jae .kernel_ranges_ready
    cmp r11, KERNEL_LOAD
    ja .invalid
.kernel_ranges_ready:

    ; The table arena must remain identity-addressable after CR3 changes and
    ; may not overlap the firmware-owned kernel backing.
    mov rax, rdi
    add rax, UEFI_TRANSITION_TABLE_BYTES
    cmp rdi, r11
    jae .arena_backing_disjoint
    cmp rsi, rax
    jb .invalid
.arena_backing_disjoint:
    mov r10, KERNEL_LOAD
    add r10, rdx
    cmp rdi, r10
    jae .arena_virtual_disjoint
    cmp rax, KERNEL_LOAD
    ja .invalid
.arena_virtual_disjoint:

    ; The PE-resident stub also needs an unshadowed identity address.
    mov rax, r8
    add rax, 4096
    cmp r8, r11
    jae .stub_backing_disjoint
    cmp rsi, rax
    jb .invalid
.stub_backing_disjoint:
    cmp r8, r10
    jae .stub_virtual_disjoint
    cmp rax, KERNEL_LOAD
    ja .invalid
.stub_virtual_disjoint:
    mov r10, rdi
    add r10, UEFI_TRANSITION_TABLE_BYTES
    cmp r8, r10
    jae .valid
    cmp rdi, rax
    jb .invalid

.valid:
    clc
    ret
.invalid:
    stc
    ret

; -----------------------------------------------------------------------------
; uefi_transition_region_needs_pt
; Inputs: RAX=2 MiB region base, RSI=physical backing, RDX=footprint,
;         R8=stub page. Output CF=1 when the region needs a leaf PT.
; Preserves all inputs.
; -----------------------------------------------------------------------------
uefi_transition_region_needs_pt:
    push r10
    push r11
    mov r10, rax
    add r10, UEFI_2M_BYTES

    mov r11, KERNEL_LOAD
    add r11, rdx
    cmp rax, r11
    jae .check_backing
    cmp r10, KERNEL_LOAD
    ja .yes

.check_backing:
    mov r11, rsi
    add r11, rdx
    cmp rax, r11
    jae .check_stub
    cmp r10, rsi
    ja .yes

.check_stub:
    mov r11, r8
    and r11, -UEFI_2M_BYTES
    cmp rax, r11
    je .yes
    pop r11
    pop r10
    clc
    ret
.yes:
    pop r11
    pop r10
    stc
    ret

; -----------------------------------------------------------------------------
; uefi_transition_expected_pte
; Inputs: RAX=virtual address, RSI=physical backing, RDX=footprint,
;         RCX=exec size, R8=stub page, R9=policy.
; Output: RAX=exact expected PTE. Other input registers are preserved.
; -----------------------------------------------------------------------------
uefi_transition_expected_pte:
    push r10
    push r11

    mov r10, rax                   ; candidate virtual address
    or rax, UEFI_PTE_PRESENT | UEFI_PTE_RW
    test r9, UEFI_TRANSITION_FLAG_NX
    jz .default_ready
    bts rax, 63
.default_ready:

    ; Remove the writable identity alias of a non-identity kernel backing.
    cmp rsi, KERNEL_LOAD
    je .check_kernel_virtual
    cmp r10, rsi
    jb .check_kernel_virtual
    mov r11, rsi
    add r11, rdx
    cmp r10, r11
    jae .check_kernel_virtual
    xor eax, eax

.check_kernel_virtual:
    cmp r10, KERNEL_LOAD
    jb .check_stub
    mov r11, KERNEL_LOAD
    add r11, rdx
    cmp r10, r11
    jae .check_stub

    mov rax, r10
    sub rax, KERNEL_LOAD
    add rax, rsi                   ; physical backing + linked offset
    or rax, UEFI_PTE_PRESENT | UEFI_PTE_RW
    test r9, UEFI_TRANSITION_FLAG_NX
    jz .kernel_permission
    bts rax, 63
.kernel_permission:
    mov r11, KERNEL_LOAD
    add r11, rcx
    cmp r10, r11
    jae .check_stub
    and rax, ~UEFI_PTE_RW
    btr rax, 63                    ; executable prefix is exact RO+X

.check_stub:
    cmp r10, r8
    jne .done
    mov rax, r10
    or rax, UEFI_PTE_PRESENT       ; exact identity RO+X
.done:
    pop r11
    pop r10
    ret

; -----------------------------------------------------------------------------
; uefi_transition_build_tables
; Inputs documented by uefi_transition_validate_table_inputs.
; CF=0/RAX=arena on success; CF=1/RAX=0 on failure.
; -----------------------------------------------------------------------------
global uefi_transition_build_tables
uefi_transition_build_tables:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    call uefi_transition_validate_table_inputs
    jc .invalid

    mov r12, rdi                   ; arena
    mov r13, rsi                   ; physical backing
    mov r14, rdx                   ; page-rounded footprint
    mov r15, rcx                   ; executable size
    mov rbp, r8                    ; stub page
    mov rbx, r9                    ; policy

    cld
    mov rdi, r12
    mov ecx, UEFI_TRANSITION_TABLE_BYTES / 8
    xor eax, eax
    rep stosq

    mov rax, r12
    add rax, UEFI_TRANSITION_PDPT_OFF
    or rax, UEFI_PTE_PRESENT | UEFI_PTE_RW
    mov [r12 + UEFI_TRANSITION_PML4_OFF], rax

    lea rdi, [r12 + UEFI_TRANSITION_PDPT_OFF]
    lea rsi, [r12 + UEFI_TRANSITION_PD_OFF]
    mov ecx, 4
.pdpt_loop:
    mov rax, rsi
    or rax, UEFI_PTE_PRESENT | UEFI_PTE_RW
    mov [rdi], rax
    add rsi, 4096
    add rdi, 8
    dec ecx
    jnz .pdpt_loop

    ; Default low-4-GiB identity map in 2 MiB leaves.
    lea rdi, [r12 + UEFI_TRANSITION_PD_OFF]
    xor esi, esi
    mov ecx, 2048
.pd_loop:
    mov rax, rsi
    or rax, UEFI_PTE_PRESENT | UEFI_PTE_RW | UEFI_PTE_HUGE
    test rbx, UEFI_TRANSITION_FLAG_NX
    jz .pd_store
    bts rax, 63
.pd_store:
    mov [rdi], rax
    add rsi, UEFI_2M_BYTES
    add rdi, 8
    dec ecx
    jnz .pd_loop

    xor r10d, r10d                 ; 2 MiB region number
    xor r11d, r11d                 ; next PT pool index
.region_loop:
    mov rax, r10
    shl rax, 21
    mov rsi, r13
    mov rdx, r14
    mov r8, rbp
    call uefi_transition_region_needs_pt
    jnc .next_region

    cmp r11, UEFI_TRANSITION_PT_PAGES
    jae .invalid
    mov rdi, r11
    shl rdi, 12
    add rdi, r12
    add rdi, UEFI_TRANSITION_PT_POOL_OFF

    mov rax, rdi
    or rax, UEFI_PTE_PRESENT | UEFI_PTE_RW
    lea rsi, [r12 + UEFI_TRANSITION_PD_OFF]
    mov [rsi + r10 * 8], rax

    mov rsi, r10
    shl rsi, 21                    ; first VA in this leaf table
    mov ecx, 512
.pte_loop:
    mov rax, rsi
    push rcx
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    mov r8, rbp
    mov r9, rbx
    call uefi_transition_expected_pte
    pop rcx
    mov [rdi], rax
    add rdi, 8
    add rsi, 4096                  ; overwritten below; retain VA separately
    ; expected_pte preserved R10/R11 but RSI is an input register by contract.
    ; Reconstruct the next VA from region and remaining-entry position.
    mov rax, 512
    sub rax, rcx
    inc rax
    shl rax, 12
    mov rsi, r10
    shl rsi, 21
    add rsi, rax
    dec ecx
    jnz .pte_loop

    inc r11
.next_region:
    inc r10
    cmp r10, 2048
    jb .region_loop

    mov rax, r12
    clc
    jmp .done
.invalid:
    xor eax, eax
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uefi_transition_verify_tables
; Same ABI as the builder. Every qword in the 73-page arena is checked.
; -----------------------------------------------------------------------------
global uefi_transition_verify_tables
uefi_transition_verify_tables:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    call uefi_transition_validate_table_inputs
    jc .invalid
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbp, r8
    mov rbx, r9
    cld

    mov rax, r12
    add rax, UEFI_TRANSITION_PDPT_OFF
    or rax, UEFI_PTE_PRESENT | UEFI_PTE_RW
    cmp [r12 + UEFI_TRANSITION_PML4_OFF], rax
    jne .invalid
    lea rdi, [r12 + UEFI_TRANSITION_PML4_OFF + 8]
    mov ecx, 511
    call .verify_zero_qwords
    jc .invalid

    lea rdi, [r12 + UEFI_TRANSITION_PDPT_OFF]
    lea rsi, [r12 + UEFI_TRANSITION_PD_OFF]
    mov ecx, 4
.verify_pdpt_loop:
    mov rax, rsi
    or rax, UEFI_PTE_PRESENT | UEFI_PTE_RW
    cmp [rdi], rax
    jne .invalid
    add rsi, 4096
    add rdi, 8
    dec ecx
    jnz .verify_pdpt_loop
    mov ecx, 508
    call .verify_zero_qwords
    jc .invalid

    xor r10d, r10d                 ; region
    xor r11d, r11d                 ; PT pool index
.verify_region_loop:
    mov rax, r10
    shl rax, 21
    mov rsi, r13
    mov rdx, r14
    mov r8, rbp
    call uefi_transition_region_needs_pt
    jc .verify_split_region

    mov rax, r10
    shl rax, 21
    or rax, UEFI_PTE_PRESENT | UEFI_PTE_RW | UEFI_PTE_HUGE
    test rbx, UEFI_TRANSITION_FLAG_NX
    jz .verify_pd_entry
    bts rax, 63
.verify_pd_entry:
    lea rdi, [r12 + UEFI_TRANSITION_PD_OFF]
    cmp [rdi + r10 * 8], rax
    jne .invalid
    jmp .verify_next_region

.verify_split_region:
    cmp r11, UEFI_TRANSITION_PT_PAGES
    jae .invalid
    mov rdi, r11
    shl rdi, 12
    add rdi, r12
    add rdi, UEFI_TRANSITION_PT_POOL_OFF
    mov rax, rdi
    or rax, UEFI_PTE_PRESENT | UEFI_PTE_RW
    lea rsi, [r12 + UEFI_TRANSITION_PD_OFF]
    cmp [rsi + r10 * 8], rax
    jne .invalid

    mov rsi, r10
    shl rsi, 21
    mov ecx, 512
.verify_pte_loop:
    mov rax, rsi
    push rcx
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    mov r8, rbp
    mov r9, rbx
    call uefi_transition_expected_pte
    pop rcx
    cmp [rdi], rax
    jne .invalid
    add rdi, 8
    mov rax, 512
    sub rax, rcx
    inc rax
    shl rax, 12
    mov rsi, r10
    shl rsi, 21
    add rsi, rax
    dec ecx
    jnz .verify_pte_loop
    inc r11

.verify_next_region:
    inc r10
    cmp r10, 2048
    jb .verify_region_loop

    ; Unused PT pool pages must remain all-zero.
    mov rdi, r11
    shl rdi, 12
    add rdi, r12
    add rdi, UEFI_TRANSITION_PT_POOL_OFF
    mov rax, UEFI_TRANSITION_PT_PAGES
    sub rax, r11
    shl rax, 9                     ; pages * 512 qwords
    mov rcx, rax
    test rcx, rcx
    jz .success
    call .verify_zero_qwords
    jc .invalid

.success:
    mov rax, r12
    clc
    jmp .done

.verify_zero_qwords:
    xor eax, eax
.zero_loop:
    cmp [rdi], rax
    jne .zero_bad
    add rdi, 8
    dec ecx
    jnz .zero_loop
    clc
    ret
.zero_bad:
    stc
    ret

.invalid:
    xor eax, eax
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; UEFI_TRANSITION_TABLES_ASM
