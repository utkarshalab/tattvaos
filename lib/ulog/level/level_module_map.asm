; =============================================================================
; Tattva OS — lib/ulog/level/level_module_map.asm
; =============================================================================
; Per-module level overrides — "set unet to DEBUG, leave everything else at
; WARN," without a rebuild. glog's --vmodule / Log4j's logger hierarchy,
; flattened into one MOD_COUNT-sized array since module_ids.inc already gives
; every module a small dense integer to index by.
;
; A byte value of LVL_OFF+1 (i.e. 7, out of the 0..6 range) means "no
; override — defer to level_runtime.asm's global floor."
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_LEVEL_LEVEL_MODULE_MAP_ASM
%define LIB_ULOG_LEVEL_LEVEL_MODULE_MAP_ASM

[BITS 64]

%include "lib/ulog/level/level_defs.inc"
%include "lib/ulog/module_ids.inc"

%define LEVEL_NO_OVERRIDE   (LVL_OFF + 1)

section .text

; -----------------------------------------------------------------------------
; level_module_map_init — every module starts with no override
; -----------------------------------------------------------------------------
global level_module_map_init
level_module_map_init:
    push rdi
    push rcx
    push rax

    mov rdi, ulog_module_levels
    mov rcx, MOD_COUNT
    mov al, LEVEL_NO_OVERRIDE
    cld
    rep stosb

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; level_module_map_set — install an override for one module
; Input:  DI = module_id, SIL = level (or LEVEL_NO_OVERRIDE to clear it)
; -----------------------------------------------------------------------------
global level_module_map_set
level_module_map_set:
    movzx eax, di
    and eax, (MOD_COUNT - 1)
    mov [ulog_module_levels + rax], sil
    ret

; -----------------------------------------------------------------------------
; level_module_map_get — the override for one module, or LEVEL_NO_OVERRIDE
; Input:  DI = module_id
; Output: AL = level
; -----------------------------------------------------------------------------
global level_module_map_get
level_module_map_get:
    movzx eax, di
    and eax, (MOD_COUNT - 1)
    movzx eax, byte [ulog_module_levels + rax]
    ret

section .bss
alignb 1
global ulog_module_levels
ulog_module_levels: resb MOD_COUNT

%endif ; LIB_ULOG_LEVEL_LEVEL_MODULE_MAP_ASM
