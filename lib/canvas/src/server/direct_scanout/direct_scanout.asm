; ============================================================================
; Direct Scanout — Zero-Copy Fullscreen Path
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define ScanoutState_active  0
%define ScanoutState.active 0

section .text

; ---------------------------------------------------------------------------
; direct_scanout_init
; ---------------------------------------------------------------------------
global direct_scanout_init
direct_scanout_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; direct_scanout_check
;   Check if surface qualifies for direct scanout
;   IN:  rdi = server*, rsi = surface*, rdx = output*
;   OUT: rax = 1 if eligible, 0 if not
; ---------------------------------------------------------------------------
global direct_scanout_check
direct_scanout_check:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Check 1: Surface has buffer attached
    mov rax, [r12 + Surface.current + SurfaceState.buffer]
    test rax, rax
    jz .fail

    ; Check 2: Surface is fullscreen (covers entire output)
    ; TODO: Check surface geometry vs output

    ; Check 3: Surface is opaque (no alpha)
    mov rax, [r12 + Surface.current + SurfaceState.opaque]
    test rax, rax
    jz .fail

    ; Check 4: No transform (identity)
    mov eax, [r12 + Surface.current + SurfaceState.transform]
    test eax, eax
    jnz .fail

    ; Check 5: Scale is 1.0
    mov rax, [r12 + Surface.current + SurfaceState.scale]
    cmp rax, FIX_ONE
    jne .fail

    ; Check 6: Buffer format supported by scanout
    ; TODO: Check buffer format

    ; Check 7: No other surfaces above in z-order
    ; TODO: Check z-order

    ; Check 8: Buffer is DMA-able and stride matches
    ; TODO

    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.fail:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; direct_scanout_enable
;   Enable direct scanout for surface
;   IN:  rdi = server*, rsi = surface*, rdx = output*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global direct_scanout_enable
direct_scanout_enable:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get buffer
    mov rax, [r12 + Surface.current + SurfaceState.buffer]
    test rax, rax
    jz .fail

    ; Program display controller for direct scanout
    ; TODO: Call backend flip with surface buffer

    ; Mark surface as scanout
    mov byte [r12 + ScanoutState.active], 1

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.fail:
    mov rax, -(EBUF_FORMAT)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; direct_scanout_disable
;   Disable direct scanout (fall back to composition)
; ---------------------------------------------------------------------------
global direct_scanout_disable
direct_scanout_disable:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov byte [rbx + ScanoutState.active], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; direct_scanout_is_active
;   Check if direct scanout is active
; ---------------------------------------------------------------------------
global direct_scanout_is_active
direct_scanout_is_active:
    PROLOGUE
    ASSERT_PTR rdi
    movzx rax, byte [rdi + ScanoutState.active]
    leave
    ret

section .data


global direct_scanout_version
direct_scanout_version: dq 0x010000
