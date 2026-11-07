; =============================================================================
; Utkarsha OS — lib/usb/core/hooks.asm — memory, delays and register access
; =============================================================================
; What the stack needs from outside, as replaceable hooks. Unset, register
; access goes straight to memory (the kernel's identity-mapped MMIO); the
; host tests point the hooks at a simulated controller.
;
; Every helper here keeps every register except RAX, so drivers can call
; them in the middle of their work.
;
;   usb_alloc(size, align)  zeroed memory, physical = virtual; 0 when none
;   usb_delay(µs)
;   usb_rd32(addr) usb_wr32(addr, v) usb_rd64(addr) usb_wr64(addr, v)
;     64-bit registers go as two 32-bit accesses, low half first (allowed
;     for every xHCI register)
; =============================================================================

%ifndef LIB_USB_CORE_HOOKS_ASM
%define LIB_USB_CORE_HOOKS_ASM

section .bss
alignb 8
global usb_alloc_fn
usb_alloc_fn:   resq 1          ; RDI = size, RSI = alignment → RAX
global usb_delay_fn
usb_delay_fn:   resq 1          ; RDI = microseconds
global usb_rd32_fn
usb_rd32_fn:    resq 1          ; RDI = address → EAX
global usb_wr32_fn
usb_wr32_fn:    resq 1          ; RDI = address, ESI = value

section .text

; call the hook in RAX with the caller-saved registers kept (RAX the result)
%macro USB_HOOK_CALL 1          ; padding: 8, or 0 when one more push came before
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    sub rsp, %1
    call rax
    add rsp, %1
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
%endmacro

; -----------------------------------------------------------------------------
; usb_alloc — RDI = size, RSI = alignment (a power of two) → RAX, zeroed
; -----------------------------------------------------------------------------
global usb_alloc
usb_alloc:
    mov rax, [rel usb_alloc_fn]
    test rax, rax
    jz .out
    USB_HOOK_CALL 8
    test rax, rax
    jz .out
    push rdi
    push rcx
    push rax
    mov rcx, rdi
    mov rdi, rax
    xor eax, eax
    rep stosb
    pop rax
    pop rcx
    pop rdi
.out:
    ret

; -----------------------------------------------------------------------------
; usb_delay — RDI = microseconds
; -----------------------------------------------------------------------------
global usb_delay
usb_delay:
    push rax
    mov rax, [rel usb_delay_fn]
    test rax, rax
    jz .out
    USB_HOOK_CALL 0
.out:
    pop rax
    ret

; -----------------------------------------------------------------------------
; usb_rd32 — RDI = address → EAX;  usb_wr32 — RDI = address, ESI = value
; -----------------------------------------------------------------------------
global usb_rd32
usb_rd32:
    mov rax, [rel usb_rd32_fn]
    test rax, rax
    jnz .hook
    mov eax, [rdi]
    ret
.hook:
    USB_HOOK_CALL 8
    ret

global usb_wr32
usb_wr32:
    push rax
    mov rax, [rel usb_wr32_fn]
    test rax, rax
    jnz .hook
    mov [rdi], esi
    pop rax
    ret
.hook:
    USB_HOOK_CALL 0
    pop rax
    ret

; usb_rd64 — RDI = address → RAX
global usb_rd64
usb_rd64:
    push rdx
    call usb_rd32
    mov edx, eax
    add rdi, 4
    call usb_rd32
    sub rdi, 4
    shl rax, 32
    or rax, rdx
    pop rdx
    ret

; usb_wr64 — RDI = address, RSI = value
global usb_wr64
usb_wr64:
    push rsi
    call usb_wr32                       ; low half (ESI)
    shr rsi, 32
    add rdi, 4
    call usb_wr32
    sub rdi, 4
    pop rsi
    ret

%endif ; LIB_USB_CORE_HOOKS_ASM
