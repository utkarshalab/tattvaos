; =============================================================================
; Tattva OS — lib/mem/virt/prefault.asm
; =============================================================================
; Real-Time Memory Pre-faulting — Subfeature 37.2.
;
; Traverses a virtual address range in page-sized steps and performs a read
; or read-write memory touch. Force-triggers CPU page fault handlers at load
; time to allocate backing physical pages, ensuring zero page-fault latency
; during execution of critical AI inference code.
;
; API:
;   rt_prefault_range(vaddr, size, write_mode)  — Touch range to allocate pages.
;   rt_prefault_vma(vma_ptr, write_mode)        — Touch entire VMA range.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PREFAULT_ASM
%define LIB_MEM_VIRT_PREFAULT_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; vma_t offset constants
; ---------------------------------------------------------------------------
VMA_START_OFF           equ 0       ; dq: start address
VMA_END_OFF             equ 8       ; dq: end address

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; rt_prefault_range — Pre-fault page allocations in a virtual address range
; Input:
;   RDI = Base Virtual Address (page aligned)
;   RSI = Size in bytes
;   RDX = Write mode (1 = read-write touch, 0 = read-only touch)
; Output: RAX = 1
; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI, R8, R9
; ---------------------------------------------------------------------------
global rt_prefault_range
rt_prefault_range:
    test rdi, rdi
    jz   .exit
    test rsi, rsi
    jz   .exit

    mov  r8, rdi                    ; R8 = current virtual address pointer
    mov  r9, rdi
    add  r9, rsi                    ; R9 = end address of range

    ; Align start address down to page boundary
    and  r8, -4096

.touch_loop:
    cmp  r8, r9
    jae  .done

    test rdx, rdx
    jz   .read_only_touch

    ; Write mode touch: read and write back to trigger dirty/COW/ZFOD allocation
    movzx eax, byte [r8]
    mov  [r8], al
    jmp  .page_touched

.read_only_touch:
    ; Read-only touch: just read byte to map physical zero page or alloc
    movzx eax, byte [r8]

.page_touched:
    inc  qword [sys_rt_prefaulted_pages]
    add  r8, 4096                   ; next 4KB page
    jmp  .touch_loop

.done:
    mov  rax, 1
    ret

.exit:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; rt_prefault_vma — Touch all pages inside the given VMA structure
; Input:
;   RDI = Pointer to VMA structure
;   RSI = Write mode (1 = read-write touch, 0 = read-only touch)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI, R8, R9
; ---------------------------------------------------------------------------
global rt_prefault_vma
rt_prefault_vma:
    test rdi, rdi
    jz   .fail

    mov  r8, [rdi + VMA_START_OFF]
    mov  r9, [rdi + VMA_END_OFF]
    cmp  r8, r9
    jae  .fail

    mov  rdx, rsi                    ; RDX = write mode
    mov  rsi, r9
    sub  rsi, r8                    ; RSI = size in bytes
    mov  rdi, r8                    ; RDI = start address
    call rt_prefault_range
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_rt_prefaulted_pages
sys_rt_prefaulted_pages:    dq 0

section .text

%endif ; LIB_MEM_VIRT_PREFAULT_ASM
