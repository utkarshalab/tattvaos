; =============================================================================
; lib/io/dma/iommu.asm
; Intel VT-d / AMD-Vi IOMMU dynamic translation table helper.
;
; Implements context-entry indexing and multi-level I/O page table mapping
; to isolate PCIe device DMA operations from unauthorized physical pages.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_DMA_IOMMU_ASM
%define IO_DMA_IOMMU_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

global iommu_map_dma_range

; =============================================================================
; iommu_map_dma_range — Map a page translation in IOMMU context & page tables
; In : RDI = Root table physical base address
;      RSI = Bus (0-255)
;      RDX = Device (0-31)
;      RCX = Function (0-7)
;      R8  = Guest virtual/IOVA address (4KB aligned)
;      R9  = Backing physical address (4KB aligned)
; Out: RAX = 0 on success, or negative error code
; =============================================================================
IO_FUNC iommu_map_dma_range
    guard_null rdi
    guard_null r8
    guard_null r9

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13

    ; 1. Calculate Bus Entry Offset in Root Table (16 bytes per entry)
    mov     rax, rsi
    shl     rax, 4                  ; bus * 16
    add     rdi, rax                ; RDI = -> bus/root entry address

    ; Read root entry present bit (bit 0)
    mov     rbx, [rdi]
    test    rbx, 0x01
    jz      .err_no_context_table   ; Root entry not present / context table unmapped

    ; Extract context table physical base address (bits [63:12] are 4KB aligned page)
    mov     rax, rbx
    mov     r10, ~0xFFF
    and     rax, r10                ; RAX = context table physical base

    ; 2. Calculate Context Entry Offset (16 bytes per entry: dev/func combination)
    ;    Index = (dev << 3) | func
    shl     rdx, 3
    or      rdx, rcx                ; RDX = device/function index
    shl     rdx, 4                  ; index * 16
    add     rax, rdx                ; RAX = -> context entry address

    ; Read context entry present bit (bit 0)
    mov     rsi, [rax]
    test    rsi, 0x01
    jz      .err_no_page_table      ; Context entry not present / I/O page table unmapped

    ; Extract level-4 page directory physical base address (bits [63:12])
    and     rsi, r10                ; RSI = level-4 page directory base

    ; 3. Walk 4-level I/O Page Tables to map Guest IOVA (R8) to physical (R9)
    ;    Page table walks map bits [47:12] of IOVA
    mov     rbx, r8
    
    ; Level 4 index: bits [47:39]
    mov     rax, rbx
    shr     rax, 39
    and     rax, 0x1FF
    shl     rax, 3                  ; index * 8
    add     rax, rsi                ; RAX = -> PML4E address
    mov     rsi, [rax]
    test    rsi, 0x01
    jz      .err_mapping            ; Directory level unmapped
    and     rsi, r10                ; RSI = level-3 directory base

    ; Level 3 index: bits [38:30]
    mov     rax, rbx
    shr     rax, 30
    and     rax, 0x1FF
    shl     rax, 3
    add     rax, rsi
    mov     rsi, [rax]
    test    rsi, 0x01
    jz      .err_mapping
    and     rsi, r10                ; RSI = level-2 directory base

    ; Level 2 index: bits [29:21]
    mov     rax, rbx
    shr     rax, 21
    and     rax, 0x1FF
    shl     rax, 3
    add     rax, rsi
    mov     rsi, [rax]
    test    rsi, 0x01
    jz      .err_mapping
    and     rsi, r10                ; RSI = level-1 page table base

    ; Level 1 index: bits [20:12]
    mov     rax, rbx
    shr     rax, 12
    and     rax, 0x1FF
    shl     rax, 3                  ; RAX = page table entry offset
    add     rax, rsi                ; RAX = -> PTE address

    ; 4. Program Page Table Entry: physical address + Read/Write permissions + Present
    ;    Read permission (bit 0 = 1), Write permission (bit 1 = 1), Page Frame address (bits [63:12])
    mov     rcx, r9
    and     rcx, r10                ; Ensure 4KB aligned physical target
    or      rcx, 0x03               ; Present (bit 0) | Read/Write (bit 1)
    mov     [rax], rcx              ; Commit PTE write

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_no_context_table:
.err_no_page_table:
.err_mapping:
    mov     rax, IO_ERR_NOMEM       ; Unmapped memory structure fault

.done:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC iommu_map_dma_range

%endif ; IO_DMA_IOMMU_ASM
