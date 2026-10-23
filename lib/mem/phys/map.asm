; =============================================================================
; Utkarsha OS — lib/mem/phys/map.asm
; =============================================================================
; E820 memory map parser. Finds maximum physical RAM and total system pages.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_PHYS_MAP_ASM
%define LIB_MEM_PHYS_MAP_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; phys_parse_e820 — validates and clips the E820 map to the physical aperture
;                   that is actually dereferenceable by the current CR3.
; Input:
;   RDI = physical pointer to the E820 map base
;   RSI = number of entries in the E820 map
;   RDX = exclusive direct-map limit
; Output:
;   CF=0: RAX = maximum managed physical address (exclusive, page aligned)
;         RCX = managed usable physical page count
;         R8  = usable page count above the mapped limit (kept offline)
;   CF=1: malformed/overflowing map; outputs are zero
; Clobbers: R9, R10, R11
; -----------------------------------------------------------------------------
phys_parse_e820:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; immutable map base
    mov r13, rsi                    ; immutable descriptor count
    mov r14, rdx                    ; immutable mapped ceiling
    xor rax, rax                    ; maximum managed end
    xor rcx, rcx                    ; managed usable pages
    xor r8, r8                      ; usable pages kept offline
    xor r9, r9                      ; descriptor index
    xor rbp, rbp                    ; previous non-empty raw exclusive end

    test r14, r14
    jz .invalid

.loop:
    cmp r9, r13
    jae .done

    mov r15, r9
    imul r15, e820_entry_size
    add r15, r12

    mov r10, [r15 + e820_entry.base]
    mov r11, [r15 + e820_entry.length]
    test r11, r11
    jz .next

    ; Reject wrapped firmware extents before doing any alignment arithmetic.
    mov rbx, r10
    add rbx, r11
    jc .invalid

    ; Both boot producers promise a canonical, ascending map.  Enforce that
    ; contract in the consumer: overlapping descriptors make it ambiguous
    ; whether a later usable range is allowed to weaken a reservation.
    cmp r10, rbp
    jb .invalid
    mov rbp, rbx

    ; Validate every firmware extent before filtering by type.  A wrapped
    ; reserved descriptor is still a malformed map and may otherwise hide a
    ; later reservation behind an apparently valid partial parse.
    cmp dword [r15 + e820_entry.type], 1
    jne .next

    ; A page is usable only when the complete page is inside the descriptor.
    add r10, 4095
    jc .invalid
    and r10, -4096                  ; aligned usable start
    and rbx, -4096                  ; aligned usable end (exclusive)
    cmp rbx, r10
    jbe .next

    ; Account the portion above the current mapped aperture, but never publish
    ; it to allocators while physical addresses are still used as pointers.
    cmp rbx, r14
    jbe .managed_part
    mov r11, r10
    cmp r11, r14
    jae .offline_start_ready
    mov r11, r14
.offline_start_ready:
    cmp rbx, r11
    jbe .managed_part
    mov r15, rbx
    sub r15, r11
    shr r15, 12
    add r8, r15
    jc .invalid

.managed_part:
    cmp r10, r14
    jae .next
    mov r11, rbx
    cmp r11, r14
    jbe .managed_end_ready
    mov r11, r14
.managed_end_ready:
    cmp r11, r10
    jbe .next

    mov r15, r11
    sub r15, r10
    shr r15, 12
    add rcx, r15
    jc .invalid

    cmp r11, rax
    jbe .next
    mov rax, r11

.next:
    inc r9
    jmp .loop

.done:
    clc
    jmp .exit

.invalid:
    xor rax, rax
    xor rcx, rcx
    xor r8, r8
    stc

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; LIB_MEM_PHYS_MAP_ASM
