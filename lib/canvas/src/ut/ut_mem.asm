; ============================================================================
; Utkarsha Memory Service Binding — ut_mem.asm
; Thin syscall wrappers for memory region management
; ============================================================================

%define UT_BINDING_IMPL 1
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

section .text

; ---------------------------------------------------------------------------
; ut_mem_alloc
;   Allocate a memory region
;   IN:  rdi = size (bytes, page-aligned)
;        rsi = flags (MEM_DMA, MEM_EXEC, MEM_UNCACHED, MEM_WC, MEM_SHARED, MEM_HUGE, MEM_1GB, MEM_LOCKED)
;   OUT: rax = virtual address (page-aligned) OR negative error
;        rdx = physical address (if MEM_DMA)
;        r8  = region handle (for free/resize)
; ---------------------------------------------------------------------------
global ut_mem_alloc
ut_mem_alloc:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi            ; save size
    mov r12, rsi            ; save flags
    mov rax, SYS_MEM_ALLOC
    syscall
    ; rax = vaddr or error, rdx = paddr, r8 = handle
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; ut_mem_free
;   Free a memory region
;   IN:  rdi = region handle
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global ut_mem_free
ut_mem_free:
    PROLOGUE
    mov rax, SYS_MEM_FREE
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_mem_resize
;   Resize a memory region (may move)
;   IN:  rdi = region handle
;        rsi = new_size (page-aligned)
;   OUT: rax = new virtual address, rdx = new physical (if DMA), negative error
; ---------------------------------------------------------------------------
global ut_mem_resize
ut_mem_resize:
    PROLOGUE
    mov rax, SYS_MEM_RESIZE
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_mem_map_phys
;   Map physical pages into an existing region
;   IN:  rdi = region handle
;        rsi = physical address (page-aligned)
;        rdx = page count
;        rcx = offset in region (bytes, page-aligned)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global ut_mem_map_phys
ut_mem_map_phys:
    PROLOGUE_SAVE rbx
    mov rax, SYS_MEM_MAP_PHYS
    syscall
    EPILOGUE_RESTORE rbx

; ---------------------------------------------------------------------------
; ut_mem_info
;   Get region information
;   IN:  rdi = region handle
;   OUT: rax = virtual address
;        rdx = physical address (0 if not DMA)
;        r8  = size
;        r9  = flags
; ---------------------------------------------------------------------------
global ut_mem_info
ut_mem_info:
    PROLOGUE
    mov rax, SYS_MEM_INFO
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_mem_protect
;   Change region protection
;   IN:  rdi = region handle
;        rsi = new flags (MEM_EXEC, MEM_UNCACHED, MEM_WC, etc.)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global ut_mem_protect
ut_mem_protect:
    PROLOGUE
    mov rax, SYS_MEM_PROTECT
    syscall
    EPILOGUE

section .data

; Memory service version for contract checking
global ut_mem_version
ut_mem_version: dq 0x010000

section .note.ut_contract
    db "UT_MEM_CONTRACT", 0
