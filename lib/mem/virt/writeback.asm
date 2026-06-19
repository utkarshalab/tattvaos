; =============================================================================
; Tattva OS — lib/mem/virt/writeback.asm
; =============================================================================
; Writeback Throttling Engine.
; Rate-limits dirty page writebacks when the dirty page count exceeds a
; configurable threshold to prevent I/O bus saturation and ensure stable
; inference latency.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_WRITEBACK_ASM
%define LIB_MEM_VIRT_WRITEBACK_ASM

[BITS 64]

section .text

; External references defined in page_cache.asm
extern sys_page_cache

; -----------------------------------------------------------------------------
; virt_writeback_throttle_check — dynamically throttles writeback if needed
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global virt_writeback_throttle_check
virt_writeback_throttle_check:
    push rbx
    push rcx
    push rdx

    ; 1. Count dirty pages in the Unified Page Cache
    xor rax, rax                    ; RAX = dirty count
    xor rcx, rcx                    ; RCX = index loop

.loop:
    cmp rcx, PAGE_CACHE_MAX_ENTRIES
    jae .loop_done

    mov rbx, rcx
    imul rbx, page_cache_entry_t_size
    lea rbx, [sys_page_cache + rbx]

    ; Check if active and dirty
    mov rdx, [rbx + page_cache_entry_t.flags]
    test rdx, 1                     ; active?
    jz .next
    test rdx, 2                     ; dirty?
    jz .next
    inc rax                         ; both active and dirty, increment count

.next:
    inc rcx
    jmp .loop

.loop_done:
    ; 2. Compare dirty count with limit
    cmp rax, [sys_writeback_dirty_limit]
    jbe .done                       ; if dirty count <= limit, do not throttle

    ; 3. Throttle! Increment telemetry
    inc qword [sys_writeback_throttled_pages]

    ; 4. Busy-loop delay to simulate writeback rate limiting
    mov rbx, [sys_writeback_throttle_delay]

.delay_loop:
    test rbx, rbx
    jz .done
    dec rbx
    jmp .delay_loop

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

section .data

align 8
global sys_writeback_throttle_delay
global sys_writeback_dirty_limit
global sys_writeback_throttled_pages

sys_writeback_throttle_delay:    dq 1000000
sys_writeback_dirty_limit:       dq 3
sys_writeback_throttled_pages:   dq 0

%endif ; LIB_MEM_VIRT_WRITEBACK_ASM
