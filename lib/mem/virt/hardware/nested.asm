; =============================================================================
; Utkarsha OS — lib/mem/virt/nested.asm
; =============================================================================
; Nested Page Table Virtualization — Nested PML4 Page Structures (Milestone 22.6).
; Supports recursive PML4 mappings to host nested hypervisors and implements
; recursive L1 EPT directory walks for guest-physical address translations.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_NESTED_ASM
%define LIB_MEM_VIRT_NESTED_ASM

[BITS 64]

; Intel EPT Flags (matching ept.asm)
EPT_READ        equ (1 << 0)        ; Bit 0: Read access
EPT_WRITE       equ (1 << 1)        ; Bit 1: Write access
EPT_EXEC        equ (1 << 2)        ; Bit 2: Execute access
EPT_MT_WB       equ (6 << 3)        ; Bits 5:3: Memory Type (Write-Back)

section .text

; External EPT and allocator symbols

; -----------------------------------------------------------------------------
; is_valid_phys_addr — Validates system RAM boundary alignment and permissions
; Input:
;   RDI = physical address to validate
; Output:
;   RAX = 1 if valid, 0 if invalid (reserved or kernel-protected region)
; -----------------------------------------------------------------------------
is_valid_phys_addr:
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    ; 1. Must be 4KB page aligned
    test rdi, 4095
    jnz .invalid

    ; 2. Must not overlap with host kernel memory [0x100000, kernel_end]
    cmp rdi, 0x100000
    jb .invalid                     ; PMM permanently reserves the low 1 MiB

    mov rax, kernel_bss_end
    cmp rdi, rax
    jb .invalid

.check_high:
    ; A sparse max_phys_addr includes holes.  Require canonical usable E820 RAM
    ; with an installed identity mapping before any host dereference.
    mov rsi, 1
    call phys_range_is_online_usable
    jmp .done

.invalid:
    xor rax, rax
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
; nested_ept_init — Allocates and zeroes root Shadow EPT PML4 table base (HPA)
; Output:
;   RAX = physical address of the Shadow EPT PML4 base (HPA), or 0 on failure
; -----------------------------------------------------------------------------
global nested_ept_init
nested_ept_init:
    call phys_alloc_page
    test rax, rax
    jz .fail

    ; Zero out the 4KB page frame
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax
.fail:
    ret

; -----------------------------------------------------------------------------
; nested_ept_map_self — Establishes recursive self-referential mapping in PML4
; Input:
;   RDI = physical address of Shadow EPT PML4 table base (HPA)
;   RSI = EPT mapping flags (e.g. EPT_READ | EPT_WRITE | EPT_EXEC)
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global nested_ept_map_self
nested_ept_map_self:
    ; A recursive table link accepts permissions only.  Address bits in the
    ; caller's flag word must never redirect the already validated root.
    mov rax, rsi
    and rax, (EPT_READ | EPT_WRITE | EPT_EXEC)
    cmp rax, rsi
    jne .fail
    test rax, rax
    jz .fail

    ; Validate PML4 alignment/boundaries
    push rdi
    push rsi
    call is_valid_phys_addr
    pop rsi
    pop rdi
    test rax, rax
    jz .fail

    ; Establish self-referential PML4 pointer at index 511
    mov r8, rdi
    or r8, rsi                      ; Link flags
    mov [rdi + 511 * 8], r8

    mov rax, 1
    ret
.fail:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; nested_ept_walk_and_sync — Walk L1 EPT and translate L2 GPA_2 -> target HPA
; Input:
;   RDI = physical address of Shadow EPT PML4 base (HPA)
;   RSI = physical address of L1 EPT PML4 base (GPA_1)
;   RDX = Guest Physical Address (GPA_2) of L2 guest causing violation
;   RCX = physical address of L0 EPT PML4 base (HPA) (to translate L1 GPAs -> HPAs)
; Output:
;   RAX = 1 on successful resolution & mapping, 0 on failure
; -----------------------------------------------------------------------------
global nested_ept_walk_and_sync
nested_ept_walk_and_sync:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = Shadow EPT PML4 HPA
    mov r13, rsi                    ; R13 = L1 EPT PML4 GPA_1
    mov r14, rdx                    ; R14 = GPA_2
    mov r15, rcx                    ; R15 = L0 EPT PML4 HPA

    ; Validate host EPT structures are within safe bounds
    mov rdi, r12
    call is_valid_phys_addr
    test rax, rax
    jz .fail

    mov rdi, r15
    call is_valid_phys_addr
    test rax, rax
    jz .fail

    ; 1. Translate L1 Guest PML4 GPA to Host Physical Address (HPA)
    mov rdi, r15                    ; L0 EPT
    mov rsi, r13                    ; L1 PML4 GPA
    call ept_translate
    test rax, rax
    jz .fail

    mov r8, rax                     ; preserve translated HPA across validator
    mov rdi, r8
    call is_valid_phys_addr
    test rax, rax
    jz .fail

    ; EPT permissions are cumulative at every level.  The shadow leaf may not
    ; grant any access that an ancestor in the L1 EPT denied.
    mov r13, (EPT_READ | EPT_WRITE | EPT_EXEC)

    ; 2. Walk L1 PML4 (Level 4)
    mov rax, r14
    shr rax, 39
    and rax, 0x1FF                  ; PML4 index
    mov r9, [r8 + rax * 8]          ; R9 = PML4 entry
    test r9, 7                      ; Present check
    jz .fail
    mov rax, r9
    and rax, 7
    and r13, rax
    jz .fail

    and r9, [rel nested_page_addr_mask_4k] ; R9 = child PDPT GPA

    ; Translate PDPT GPA to HPA
    mov rdi, r15
    mov rsi, r9
    call ept_translate
    test rax, rax
    jz .fail

    mov r8, rax                     ; preserve translated HPA across validator
    mov rdi, r8
    call is_valid_phys_addr
    test rax, rax
    jz .fail

    ; 3. Walk L1 PDPT (Level 3)
    mov rax, r14
    shr rax, 30
    and rax, 0x1FF                  ; PDPT index
    mov r9, [r8 + rax * 8]
    test r9, 7
    jz .fail
    mov rax, r9
    and rax, 7
    and r13, rax
    jz .fail

    test r9, (1 << 7)               ; Huge pages (1GB) unsupported in EPT walk
    jnz .fail

    and r9, [rel nested_page_addr_mask_4k] ; R9 = child PD GPA

    ; Translate PD GPA to HPA
    mov rdi, r15
    mov rsi, r9
    call ept_translate
    test rax, rax
    jz .fail

    mov r8, rax                     ; preserve translated HPA across validator
    mov rdi, r8
    call is_valid_phys_addr
    test rax, rax
    jz .fail

    ; 4. Walk L1 PD (Level 2)
    mov rax, r14
    shr rax, 21
    and rax, 0x1FF                  ; PD index
    mov r9, [r8 + rax * 8]
    test r9, 7
    jz .fail
    mov rax, r9
    and rax, 7
    and r13, rax
    jz .fail

    test r9, (1 << 7)               ; Huge pages (2MB) unsupported in EPT walk
    jnz .fail

    and r9, [rel nested_page_addr_mask_4k] ; R9 = child PT GPA

    ; Translate PT GPA to HPA
    mov rdi, r15
    mov rsi, r9
    call ept_translate
    test rax, rax
    jz .fail

    mov r8, rax                     ; preserve translated HPA across validator
    mov rdi, r8
    call is_valid_phys_addr
    test rax, rax
    jz .fail

    ; 5. Walk L1 PT (Level 1 - Leaf entry)
    mov rax, r14
    shr rax, 12
    and rax, 0x1FF                  ; PT index
    mov r9, [r8 + rax * 8]          ; R9 = leaf entry
    test r9, 7
    jz .fail
    test r9, (1 << 7)               ; Reserved for a 4KB EPT leaf
    jnz .fail
    mov rax, r9
    and rax, 7
    and r13, rax
    jz .fail

    ; Preserve only valid 4KB leaf attributes across the final translation.
    mov rbx, r9
    and rbx, 0x378                  ; memory type, IPAT, accessed, dirty
    or rbx, r13                     ; effective cumulative R/W/X

    ; Translate target GPA_1 to host physical address
    mov rdi, r15
    mov rsi, r9
    and rsi, [rel nested_page_addr_mask_4k]
    call ept_translate
    test rax, rax
    jz .fail

    mov r8, rax                     ; preserve target HPA across validator
    mov rdi, r8
    call is_valid_phys_addr
    test rax, rax
    jz .fail
    mov rdx, r8                     ; RDX = target HPA
    mov rcx, rbx                    ; sanitized effective EPT mapping flags

    ; 6. Map target HPA to L2 GPA in Shadow EPT structure
    mov rdi, r12                    ; Shadow EPT PML4 base
    mov rsi, r14                    ; GPA_2
    call ept_map_page               ; maps GPA_2 -> HPA

    jmp .exit

.fail:
    xor rax, rax
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
align 8
nested_page_addr_mask_4k: dq 0x000FFFFFFFFFF000

%endif ; LIB_MEM_VIRT_NESTED_ASM
