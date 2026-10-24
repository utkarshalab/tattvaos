; ============================================================================
; Blend Operations — Porter-Duff Compositing, Alpha Blending
; ============================================================================

%include "ugfx.inc"

extern memcopy

section .text

; ---------------------------------------------------------------------------
; blend_dispatch
;   Dispatch to appropriate blend function based on format/flags
;   IN:  rdi = dest, rsi = src, rdx = count, rcx = flags
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global blend_dispatch
blend_dispatch:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    
    ; Check for premultiplied alpha
    test r14d, 1
    jnz .premul
    
    ; Non-premultiplied - use OVER
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call blend_over
    jmp .done
    
.premul:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call blend_over_premul
    
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; blend_over
;   Porter-Duff OVER (non-premultiplied)
;   dst = src + dst * (1 - src_alpha)
;   IN:  rdi = dest (BGRA), rsi = src (BGRA), rdx = count
; ---------------------------------------------------------------------------
global blend_over
blend_over:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    
.loop:
    ; Load source pixel (BGRA)
    mov eax, [r12]
    mov r8b, al           ; B
    shr eax, 8
    mov r9b, al           ; G
    shr eax, 8
    mov r10b, al          ; R
    shr eax, 8
    mov r11b, al          ; A (0-255)
    
    test r11b, r11b
    jz .skip_alpha
    cmp r11b, 255
    je .full_alpha
    
    ; General case: src_alpha in r11b (0-255)
    ; dst = src + dst * (255 - src_alpha) / 255
    movzx ecx, byte [rbx]       ; dst B
    movzx edx, byte [rbx + 1]   ; dst G
    movzx r8d, byte [rbx + 2]   ; dst R
    movzx r9d, byte [rbx + 3]   ; dst A
    
    mov r10d, 255
    sub r10d, r11d              ; 255 - src_alpha
    
    imul ecx, r10d
    shr ecx, 8
    add ecx, [rsi]              ; add src B
    mov [rdi], cl
    
    imul edx, r10d
    shr edx, 8
    add edx, [rsi + 1]
    mov [rdi + 1], dl
    
    imul r8d, r10d
    shr r8d, 8
    add r8d, [rsi + 2]
    mov [rdi + 2], r8b
    
    ; Alpha: src_A + dst_A * (255 - src_A) / 255
    imul r9d, r10d
    shr r9d, 8
    add r9d, r11d
    mov [rdi + 3], r9b
    
    jmp .next_pixel
    
.full_alpha:
    ; Just copy source
    mov eax, [r12]
    mov [rdi], eax
    jmp .next_pixel
    
.skip_alpha:
    ; Source fully transparent - skip
    jmp .next_pixel
    
.next_pixel:
    add rsi, 4
    add rdi, 4
    dec r13
    jnz .loop
    
.done:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; blend_over_premul
;   Porter-Duff OVER (premultiplied alpha)
;   dst = src + dst * (1 - src_alpha)
;   IN:  rdi = dest (BGRA premul), rsi = src (BGRA premul), rdx = count
; ---------------------------------------------------------------------------
global blend_over_premul
blend_over_premul:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    
.loop:
    ; Load source (premultiplied BGRA)
    mov eax, [r12]
    mov r8b, al
    shr eax, 8
    mov r9b, al
    shr eax, 8
    mov r10b, al
    shr eax, 8
    mov r11b, al
    
    test r11b, r11b
    jz .next_pixel
    cmp r11b, 255
    je .full_alpha
    
    movzx ecx, byte [rbx]
    movzx edx, byte [rbx + 1]
    movzx r8d, byte [rbx + 2]
    movzx r9d, byte [rbx + 3]
    
    mov r10d, 255
    sub r10d, r11d
    
    ; For premultiplied: dst = src + dst * (1 - src_alpha)
    ; src is already multiplied by its alpha
    imul ecx, r10d
    shr ecx, 8
    add ecx, [rsi]
    mov [rdi], cl
    
    imul edx, r10d
    shr edx, 8
    add edx, [rsi + 1]
    mov [rdi + 1], dl
    
    imul r8d, r10d
    shr r8d, 8
    add r8d, [rsi + 2]
    mov [rdi + 2], r8b
    
    imul r9d, r10d
    shr r9d, 8
    add r9d, r11d
    mov [rdi + 3], r9b
    
    jmp .next_pixel
    
.full_alpha:
    mov eax, [r12]
    mov [rdi], eax
    jmp .next_pixel
    
.next_pixel:
    add rsi, 4
    add rdi, 4
    dec r13
    jnz .loop
    
.done:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; blend_clear
;   Clear destination
; ---------------------------------------------------------------------------
global blend_clear
blend_clear:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rdx
    ASSERT_PTR rbx
    test r12, r12
    jz .done
    xor eax, eax
    rep stosd
.done:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; blend_src
;   Copy source (no blending)
; ---------------------------------------------------------------------------
global blend_src
blend_src:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    mov rdi, rbx
    mov rsi, r12
    call memcopy
.done:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; blend_dst
;   Keep destination (no-op)
; ---------------------------------------------------------------------------
global blend_dst
blend_dst:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; blend_src_over
;   Alias for blend_over
; ---------------------------------------------------------------------------
global blend_src_over
blend_src_over:
    jmp blend_over

; ---------------------------------------------------------------------------
; blend_scalar
;   Scalar fallback for SIMD blend functions
;   IN:  rdi = dest (BGRA), rsi = src (BGRA), rdx = count, rcx = flags
; ---------------------------------------------------------------------------
global blend_scalar
blend_scalar:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    
.loop:
    ; Load source pixel (BGRA)
    mov eax, [r12]
    mov r8b, al           ; B
    shr eax, 8
    mov r9b, al           ; G
    shr eax, 8
    mov r10b, al          ; R
    shr eax, 8
    mov r11b, al          ; A (0-255)
    
    test r11b, r11b
    jz .skip_alpha
    cmp r11b, 255
    je .full_alpha
    
    ; General case
    movzx ecx, byte [rbx]       ; dst B
    movzx edx, byte [rbx + 1]   ; dst G
    movzx r8d, byte [rbx + 2]   ; dst R
    movzx r9d, byte [rbx + 3]   ; dst A
    
    mov r10d, 255
    sub r10d, r11d              ; 255 - src_alpha
    
    imul ecx, r10d
    shr ecx, 8
    add ecx, [rsi]
    mov [rdi], cl
    
    imul edx, r10d
    shr edx, 8
    add edx, [rsi + 1]
    mov [rdi + 1], dl
    
    imul r8d, r10d
    shr r8d, 8
    add r8d, [rsi + 2]
    mov [rdi + 2], r8b
    
    imul r9d, r10d
    shr r9d, 8
    add r9d, r11d
    mov [rdi + 3], r9b
    
    jmp .next_pixel
    
.full_alpha:
    ; Just copy source
    mov eax, [r12]
    mov [rdi], eax
    jmp .next_pixel
    
.skip_alpha:
    ; Source fully transparent - skip
    jmp .next_pixel
    
.next_pixel:
    add rsi, 4
    add rdi, 4
    dec r13
    jnz .loop
    
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; blend_dst_over
;   dst = dst + src * (1 - dst_alpha)
; ---------------------------------------------------------------------------
global blend_dst_over
blend_dst_over:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    
.loop:
    mov eax, [r12]
    mov r8b, al
    shr eax, 8
    mov r9b, al
    shr eax, 8
    mov r10b, al
    shr eax, 8
    mov r11b, al
    
    mov eax, [rbx]
    mov r12b, al
    shr eax, 8
    mov r13b, al
    shr eax, 8
    mov r14b, al
    shr eax, 8
    
    mov r15d, 255
    sub r15d, r14d
    
    imul r8d, r15d
    shr r8d, 8
    add r8d, r12d
    mov [rdi], r8b
    
    imul r9d, r15d
    shr r9d, 8
    add r9d, r13d
    mov [rdi + 1], r9b
    
    imul r10d, r15d
    shr r10d, 8
    add r10d, r14d
    mov [rdi + 2], r10b
    
    imul r11d, r15d
    shr r11d, 8
    add r11d, r15d
    mov [rdi + 3], r11b
    
    add rsi, 4
    add rdi, 4
    dec r13
    jnz .loop
    
.done:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; blend_src_in
;   dst = src * dst_alpha
; ---------------------------------------------------------------------------
global blend_src_in
blend_src_in:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    
.loop:
    mov eax, [r12]
    mov r8b, al
    shr eax, 8
    mov r9b, al
    shr eax, 8
    mov r10b, al
    shr eax, 8
    mov r11b, al
    
    mov eax, [rbx]
    shr eax, 24
    movzx ecx, al
    
    test ecx, ecx
    jz .zero
    cmp ecx, 255
    je .full
    
    imul r8d, ecx
    shr r8d, 8
    imul r9d, ecx
    shr r9d, 8
    imul r10d, ecx
    shr r10d, 8
    imul r11d, ecx
    shr r11d, 8
    jmp .store
    
.full:
    jmp .store
    
.zero:
    xor r8d, r8d
    xor r9d, r9d
    xor r10d, r10d
    xor r11d, r11d
    
.store:
    mov [rdi], r8b
    mov [rdi + 1], r9b
    mov [rdi + 2], r10b
    mov [rdi + 3], r11b
    
    add rsi, 4
    add rdi, 4
    dec r13
    jnz .loop
    
.done:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; blend_dst_in
;   dst = dst * src_alpha
; ---------------------------------------------------------------------------
global blend_dst_in
blend_dst_in:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    
.loop:
    mov eax, [r12]
    shr eax, 24
    movzx ecx, al
    
    test ecx, ecx
    jz .zero
    cmp ecx, 255
    je .full
    
    mov eax, [rbx]
    mov r8b, al
    shr eax, 8
    mov r9b, al
    shr eax, 8
    mov r10b, al
    shr eax, 8
    mov r11b, al
    
    imul r8d, ecx
    shr r8d, 8
    imul r9d, ecx
    shr r9d, 8
    imul r10d, ecx
    shr r10d, 8
    imul r11d, ecx
    shr r11d, 8
    jmp .store
    
.full:
    jmp .next_pixel
.zero:
    xor r8d, r8d
    xor r9d, r9d
    xor r10d, r10d
    xor r11d, r11d
.store:
    mov [rdi], r8b
    mov [rdi + 1], r9b
    mov [rdi + 2], r10b
    mov [rdi + 3], r11b
.next_pixel:
    add rsi, 4
    add rdi, 4
    dec r13
    jnz .loop
.done:
    xor rax, rax
    leave
    ret

section .data
global blend_version
blend_version: dq 0x010000
