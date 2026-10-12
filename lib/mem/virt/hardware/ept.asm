; =============================================================================
; Tattva OS — lib/mem/virt/ept.asm
; =============================================================================
; Hardware Page Table Virtualization — Extended Page Tables (EPT) (Milestone 22).
; Constructs and manages secondary level-4 guest page tables to map Guest
; Physical Addresses (GPA) to Host Physical Addresses (HPA) for virtualization.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_EPT_ASM
%define LIB_MEM_VIRT_EPT_ASM

[BITS 64]

; -----------------------------------------------------------------------------
; EPT Entry Flags & Constants
; -----------------------------------------------------------------------------
EPT_READ        equ (1 << 0)        ; Bit 0: Read access
EPT_WRITE       equ (1 << 1)        ; Bit 1: Write access
EPT_EXEC        equ (1 << 2)        ; Bit 2: Execute access (supervisor & user)
EPT_MT_WB       equ (6 << 3)        ; Bits 5:3: Memory Type (Write-Back)
EPT_IPAT        equ (1 << 6)        ; Bit 6: Ignore PAT memory type
EPT_ACCESSED    equ (1 << 8)        ; Bit 8: Accessed
EPT_DIRTY       equ (1 << 9)        ; Bit 9: Dirty
EPT_LEAF_FLAGS  equ 0x37F           ; Supported 4KB-leaf attributes (bit 7 excluded)

section .text

; External Physical Memory Allocator Symbols

; Validate a host page-table page before dereferencing it.  Keep all caller
; registers except RAX intact so the walk state survives the range validator.
ept_validate_table_page:
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    test rdi, 4095
    jnz .invalid
    cmp rdi, 0x100000
    jb .invalid
    mov rax, kernel_bss_end
    cmp rdi, rax
    jb .invalid

    mov rsi, 1
    call phys_range_is_online_usable
    jmp .done

.invalid:
    xor eax, eax
.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    ret

; -----------------------------------------------------------------------------
; ept_create_eptp — Builds the 64-bit Extended Page Table Pointer (EPTP)
; Input:
;   RDI = physical address of EPT PML4 table base (HPA, 4KB page aligned)
;   RSI = memory type (e.g. 6 = Write-Back WB)
;   RDX = page-walk length minus 1 (usually 3 for 4 levels)
;   RCX = enable accessed/dirty flags (1 = enabled, 0 = disabled)
; Output:
;   RAX = 64-bit EPTP value suitable for loading into the VMCS
; -----------------------------------------------------------------------------
global ept_create_eptp
ept_create_eptp:
    ; Mask off any offset bits in PML4 physical address to ensure alignment
    and rdi, [rel ept_page_addr_mask_4k] ; exact 52-bit PML4 base
    
    ; Integrate Memory Type (bits 2:0)
    and rsi, 7
    or rdi, rsi
    
    ; Integrate Page-Walk Length (bits 5:3)
    and rdx, 7
    shl rdx, 3
    or rdi, rdx
    
    ; Integrate Accessed/Dirty enable (bit 6)
    test rcx, rcx
    jz .done
    or rdi, (1 << 6)
    
.done:
    mov rax, rdi
    ret

; -----------------------------------------------------------------------------
; ept_map_page — Maps a Guest Physical Page (GPA) to a Host Physical Page (HPA)
; Input:
;   RDI = physical address of EPT PML4 base (HPA)
;   RSI = Guest Physical Address (GPA) (must be 4KB page-aligned)
;   RDX = Host Physical Address (HPA) (must be 4KB page-aligned)
;   RCX = mapping flags (e.g. EPT_READ | EPT_WRITE | EPT_MT_WB)
; Output:
;   RAX = 1 on success, 0 on failure (Out of Memory)
; -----------------------------------------------------------------------------
global ept_map_page
ept_map_page:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = EPT PML4 physical address
    mov r13, rsi                    ; R13 = GPA (aligned)
    mov r14, rdx                    ; R14 = HPA (aligned)
    mov r15, rcx                    ; R15 = mapping flags

    test r12, r12
    jz .fail
    test r12, 4095
    jnz .fail
    test r13, 4095
    jnz .fail
    test r14, 4095
    jnz .fail

    ; Reject address injection through either the HPA or caller flags.
    mov rax, r14
    and rax, [rel ept_page_addr_mask_4k]
    cmp rax, r14
    jne .fail
    mov rax, r15
    and rax, EPT_LEAF_FLAGS
    cmp rax, r15
    jne .fail
    test r15, (EPT_READ | EPT_WRITE | EPT_EXEC)
    jz .fail

    mov rdi, r12
    call ept_validate_table_page
    test rax, rax
    jz .fail

    ; 1. Walk PML4 (Level 4)
    mov rax, r13
    shr rax, 39
    and rax, 0x1FF                  ; RAX = PML4 index (bits 47:39)
    lea r8, [r12 + rax * 8]         ; R8 = PML4 entry address
    mov r9, [r8]                    ; R9 = PML4 entry value
    test r9, 7                      ; Check present (read/write/exec bits)
    jnz .pml4_valid

    ; Allocate EPT PDPT table
    push r8
    call phys_alloc_page
    pop r8
    test rax, rax
    jz .fail
    
    ; Zero out the allocated table
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax
    
    ; Link PDPT to PML4 entry
    mov r9, rax
    or r9, 7                        ; Link flags: EPT_READ | EPT_WRITE | EPT_EXEC
    mov [r8], r9

.pml4_valid:
    test r9, (1 << 7)               ; A PML4 entry cannot be a huge leaf
    jnz .fail
    and r9, [rel ept_page_addr_mask_4k] ; R9 = PDPT physical address
    mov rdi, r9
    call ept_validate_table_page
    test rax, rax
    jz .fail

    ; 2. Walk PDPT (Level 3)
    mov rax, r13
    shr rax, 30
    and rax, 0x1FF                  ; RAX = PDPT index (bits 38:30)
    lea r8, [r9 + rax * 8]          ; R8 = PDPT entry address
    mov r9, [r8]                    ; R9 = PDPT entry value
    test r9, 7                      ; Check present
    jnz .pdpt_valid

    ; Allocate EPT PD table
    push r8
    call phys_alloc_page
    pop r8
    test rax, rax
    jz .fail
    
    ; Zero out the allocated table
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax
    
    ; Link PD to PDPT entry
    mov r9, rax
    or r9, 7                        ; Link flags
    mov [r8], r9

.pdpt_valid:
    test r9, (1 << 7)               ; This mapper only builds 4KB leaves
    jnz .fail
    and r9, [rel ept_page_addr_mask_4k] ; R9 = PD physical address
    mov rdi, r9
    call ept_validate_table_page
    test rax, rax
    jz .fail

    ; 3. Walk PD (Level 2)
    mov rax, r13
    shr rax, 21
    and rax, 0x1FF                  ; RAX = PD index (bits 29:21)
    lea r8, [r9 + rax * 8]          ; R8 = PD entry address
    mov r9, [r8]                    ; R9 = PD entry value
    test r9, 7                      ; Check present
    jnz .pd_valid

    ; Allocate EPT PT table
    push r8
    call phys_alloc_page
    pop r8
    test rax, rax
    jz .fail
    
    ; Zero out the allocated table
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax
    
    ; Link PT to PD entry
    mov r9, rax
    or r9, 7                        ; Link flags
    mov [r8], r9

.pd_valid:
    test r9, (1 << 7)               ; This mapper only builds 4KB leaves
    jnz .fail
    and r9, [rel ept_page_addr_mask_4k] ; R9 = PT physical address
    mov rdi, r9
    call ept_validate_table_page
    test rax, rax
    jz .fail

    ; 4. Walk PT (Level 1)
    mov rax, r13
    shr rax, 12
    and rax, 0x1FF                  ; RAX = PT index (bits 20:12)
    lea r8, [r9 + rax * 8]          ; R8 = PT entry address (leaf EPT PTE)

    ; Write target Host Physical Address and mapping flags
    mov r9, r14
    and r9, [rel ept_page_addr_mask_4k] ; exact HPA without EPT attributes
    or r9, r15                      ; Add mapping flags
    mov [r8], r9

    mov rax, 1                      ; Return success (1)
    
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.fail:
    xor rax, rax                    ; Return failure (0)
    jmp .exit

; -----------------------------------------------------------------------------
; ept_unmap_page — Removes EPT page mapping for a Guest Physical Address
; Input:
;   RDI = physical address of EPT PML4 base
;   RSI = Guest Physical Address (GPA)
; Output:
;   RAX = 1 on success (cleared), 0 if not mapped
; -----------------------------------------------------------------------------
global ept_unmap_page
ept_unmap_page:
    test rdi, rdi
    jz .not_mapped
    test rsi, 4095
    jnz .not_mapped
    call ept_validate_table_page
    test rax, rax
    jz .not_mapped

    ; PML4 Walk
    mov rax, rsi
    shr rax, 39
    and rax, 0x1FF
    mov r8, [rdi + rax * 8]
    test r8, 7
    jz .not_mapped
    test r8, (1 << 7)
    jnz .not_mapped
    
    ; PDPT Walk
    and r8, [rel ept_page_addr_mask_4k]
    mov rdi, r8
    call ept_validate_table_page
    test rax, rax
    jz .not_mapped
    mov rax, rsi
    shr rax, 30
    and rax, 0x1FF
    mov r9, [r8 + rax * 8]
    test r9, 7
    jz .not_mapped
    test r9, (1 << 7)
    jnz .not_mapped
    
    ; PD Walk
    and r9, [rel ept_page_addr_mask_4k]
    mov rdi, r9
    call ept_validate_table_page
    test rax, rax
    jz .not_mapped
    mov rax, rsi
    shr rax, 21
    and rax, 0x1FF
    mov r8, [r9 + rax * 8]
    test r8, 7
    jz .not_mapped
    test r8, (1 << 7)
    jnz .not_mapped
    
    ; PT Walk
    and r8, [rel ept_page_addr_mask_4k]
    mov rdi, r8
    call ept_validate_table_page
    test rax, rax
    jz .not_mapped
    mov rax, rsi
    shr rax, 12
    and rax, 0x1FF
    lea rcx, [r8 + rax * 8]         ; RCX = leaf PTE address
    mov rax, [rcx]
    test rax, 7                     ; Check present
    jz .not_mapped
    
    ; Clear page table entry
    mov qword [rcx], 0
    mov rax, 1
    ret
    
.not_mapped:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; ept_translate — Software walk of EPT structures to translate GPA to HPA
; Input:
;   RDI = physical address of EPT PML4 base
;   RSI = Guest Physical Address (GPA)
; Output:
;   RAX = Host Physical Address (HPA), or 0 if not mapped
; -----------------------------------------------------------------------------
global ept_translate
ept_translate:
    test rdi, rdi
    jz .not_mapped
    call ept_validate_table_page
    test rax, rax
    jz .not_mapped

    ; PML4 Walk
    mov rax, rsi
    shr rax, 39
    and rax, 0x1FF
    mov r8, [rdi + rax * 8]
    test r8, 7
    jz .not_mapped
    test r8, (1 << 7)
    jnz .not_mapped
    
    ; PDPT Walk
    and r8, [rel ept_page_addr_mask_4k]
    mov rdi, r8
    call ept_validate_table_page
    test rax, rax
    jz .not_mapped
    mov rax, rsi
    shr rax, 30
    and rax, 0x1FF
    mov r9, [r8 + rax * 8]
    test r9, 7
    jz .not_mapped
    test r9, (1 << 7)
    jnz .not_mapped
    
    ; PD Walk
    and r9, [rel ept_page_addr_mask_4k]
    mov rdi, r9
    call ept_validate_table_page
    test rax, rax
    jz .not_mapped
    mov rax, rsi
    shr rax, 21
    and rax, 0x1FF
    mov r8, [r9 + rax * 8]
    test r8, 7
    jz .not_mapped
    test r8, (1 << 7)
    jnz .not_mapped
    
    ; PT Walk
    and r8, [rel ept_page_addr_mask_4k]
    mov rdi, r8
    call ept_validate_table_page
    test rax, rax
    jz .not_mapped
    mov rax, rsi
    shr rax, 12
    and rax, 0x1FF
    mov rcx, [r8 + rax * 8]         ; RCX = leaf PTE value
    test rcx, 7                     ; Check present
    jz .not_mapped
    
    ; Extract physical address base and add GPA offset
    mov rax, rcx
    mov r8, [rel ept_page_addr_mask_4k]
    and rax, r8                     ; RAX = HPA page base address
    mov r8, 0xFFF
    and rsi, r8                     ; RSI = page offset (bits 11:0)
    add rax, rsi                    ; RAX = full HPA translated address
    ret
    
.not_mapped:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; ept_free_level — Recursive helper to deallocate EPT table pages
; Input:
;   RDI = table physical address (HPA)
;   RSI = paging level (1 = PT, 2 = PD, 3 = PDPT, 4 = PML4)
; -----------------------------------------------------------------------------
ept_free_level:
    push rbx
    push r12
    push r13
    
    mov rbx, rdi                    ; RBX = table physical address
    mov r12, rsi                    ; R12 = paging level

    mov rdi, rbx
    call ept_validate_table_page
    test rax, rax
    jz .invalid
    
    ; If Level 1 (PT), do not traverse, free directly
    cmp r12, 1
    je .free_self
    
    ; Traverse entries (0 to 511)
    mov r13, 0                      ; R13 = entry index
.loop:
    cmp r13, 512
    jae .free_self
    
    mov rax, [rbx + r13 * 8]        ; RAX = EPT entry value
    test rax, 7                     ; Check present
    jz .next

    ; Huge leaves own mapped data, not another EPT table page.
    cmp r12, 4
    je .not_huge
    test rax, (1 << 7)
    jnz .next
.not_huge:

    and rax, [rel ept_page_addr_mask_4k] ; child table physical address
    cmp rax, rbx                    ; Reject the simplest corrupt cycle
    je .invalid

    mov rdi, rax
    call ept_validate_table_page
    test rax, rax
    jz .invalid

    ; Call recursively on child table
    mov rdi, [rbx + r13 * 8]
    and rdi, [rel ept_page_addr_mask_4k]
    mov rsi, r12
    dec rsi                         ; level - 1
    call ept_free_level
    
.next:
    inc r13
    jmp .loop
    
.free_self:
    mov rdi, rbx
    call phys_free_page
    
    pop r13
    pop r12
    pop rbx
    ret

.invalid:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ept_destroy — Deallocates EPT page table structures recursively
; Input:
;   RDI = physical address of EPT PML4 base
; -----------------------------------------------------------------------------
global ept_destroy
ept_destroy:
    test rdi, rdi
    jz .done
    mov rsi, 4                      ; Start traversal at PML4 (Level 4)
    call ept_free_level
.done:
    ret

section .rodata
align 8
ept_page_addr_mask_4k: dq 0x000FFFFFFFFFF000

%endif ; LIB_MEM_VIRT_EPT_ASM
