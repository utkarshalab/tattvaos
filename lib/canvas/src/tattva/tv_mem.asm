; ============================================================================
; Tattva Memory Service Binding — tv_mem.asm
; Thin syscall wrappers for memory region management
; ============================================================================

%define TATTVA_BINDING_IMPL 1
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; tv_mem_alloc
;   Allocate a memory region
;   IN:  rdi = size (bytes, page-aligned)
;        rsi = flags (MEM_DMA, MEM_EXEC, MEM_UNCACHED, MEM_WC, MEM_SHARED, MEM_HUGE, MEM_1GB, MEM_LOCKED)
;   OUT: rax = virtual address (page-aligned) OR negative error
;        rdx = physical address (if MEM_DMA)
;        r8  = region handle (for free/resize)
; ---------------------------------------------------------------------------
global tv_mem_alloc
tv_mem_alloc:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi            ; save size
    mov r12, rsi            ; save flags
    mov rax, SYS_MEM_ALLOC
    syscall
    ; rax = vaddr or error, rdx = paddr, r8 = handle
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; tv_mem_free
;   Free a memory region
;   IN:  rdi = region handle
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global tv_mem_free
tv_mem_free:
    PROLOGUE
    mov rax, SYS_MEM_FREE
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_mem_resize
;   Resize a memory region (may move)
;   IN:  rdi = region handle
;        rsi = new_size (page-aligned)
;   OUT: rax = new virtual address, rdx = new physical (if DMA), negative error
; ---------------------------------------------------------------------------
global tv_mem_resize
tv_mem_resize:
    PROLOGUE
    mov rax, SYS_MEM_RESIZE
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_mem_map_phys
;   Map physical pages into an existing region
;   IN:  rdi = region handle
;        rsi = physical address (page-aligned)
;        rdx = page count
;        rcx = offset in region (bytes, page-aligned)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global tv_mem_map_phys
tv_mem_map_phys:
    PROLOGUE_SAVE rbx
    mov rax, SYS_MEM_MAP_PHYS
    syscall
    EPILOGUE_RESTORE rbx

; ---------------------------------------------------------------------------
; tv_mem_info
;   Get region information
;   IN:  rdi = region handle
;   OUT: rax = virtual address
;        rdx = physical address (0 if not DMA)
;        r8  = size
;        r9  = flags
; ---------------------------------------------------------------------------
global tv_mem_info
tv_mem_info:
    PROLOGUE
    mov rax, SYS_MEM_INFO
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_mem_protect
;   Change region protection
;   IN:  rdi = region handle
;        rsi = new flags (MEM_EXEC, MEM_UNCACHED, MEM_WC, etc.)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global tv_mem_protect
tv_mem_protect:
    PROLOGUE
    mov rax, SYS_MEM_PROTECT
    syscall
    EPILOGUE

section .data

; Memory service version for contract checking
global tv_mem_version
tv_mem_version: dq 0x010000

section .note.tattva_contract
    db "TATTVA_MEM_CONTRACT", 0
