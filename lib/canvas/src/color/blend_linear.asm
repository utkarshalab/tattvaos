; ============================================================================
; Blend Linear — Linear-Light Premultiplied Alpha Blend
; Used when any surface is linear/HDR: decode -> blend -> encode
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; blend_linear_row
;   IN: rdi=dst BGRA u8*, rsi=src BGRA u8*, rdx=width,
;       rcx=dst_is_linear, r8=src_is_linear
;   Uses srgb LUTs for conversion; alpha stays premultiplied in gamma domain
; ---------------------------------------------------------------------------
global blend_linear_row
blend_linear_row:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    extern srgb_to_linear_lut
    extern linear_to_srgb_lut
.loop:
    mov eax, [r12]      ; src BGRA
    mov edx, [rbx]      ; dst BGRA
    mov r8d, eax
    shr r8d, 24         ; src_a
    test r8d, r8d
    jz .next
    cmp r8d, 255
    je .opaque
    ; decode src rgb to linear
    movzx ecx, al
    movzx ecx, word [srgb_to_linear_lut + rcx * 2]
    mov r9d, ecx        ; src_b lin
    movzx ecx, ah
    shr eax, 16
    movzx ecx, word [srgb_to_linear_lut + rcx * 2]
    mov r10d, ecx       ; src_g lin
    movzx ecx, al
    movzx ecx, word [srgb_to_linear_lut + rcx * 2]
    mov r11d, ecx       ; src_r lin
    ; decode dst rgb to linear
    mov eax, edx
    movzx ecx, al
    movzx ecx, word [srgb_to_linear_lut + rcx * 2]
    ; dst_b lin in ecx; blend: out = src + dst*(255-a)/255
    mov edi, 255
    sub edi, r8d
    imul ecx, edi
    shr ecx, 8
    add r9d, ecx
    cmp r9d, 65535
    jbe .ok_b
    mov r9d, 65535
.ok_b:
    ; encode back via LUT index >>4
    mov ecx, r9d
    shr ecx, 4
    cmp ecx, 4095
    jbe .ok_bi
    mov ecx, 4095
.ok_bi:
    movzx ecx, word [linear_to_srgb_lut + rcx * 2]
    shr ecx, 8
    mov [rbx], cl
    ; green
    mov eax, edx
    shr eax, 8
    movzx ecx, al
    movzx ecx, word [srgb_to_linear_lut + rcx * 2]
    imul ecx, edi
    shr ecx, 8
    add r10d, ecx
    cmp r10d, 65535
    jbe .ok_g
    mov r10d, 65535
.ok_g:
    mov ecx, r10d
    shr ecx, 4
    cmp ecx, 4095
    jbe .ok_gi
    mov ecx, 4095
.ok_gi:
    movzx ecx, word [linear_to_srgb_lut + rcx * 2]
    shr ecx, 8
    mov [rbx + 1], cl
    ; red
    mov eax, edx
    shr eax, 16
    movzx ecx, al
    movzx ecx, word [srgb_to_linear_lut + rcx * 2]
    imul ecx, edi
    shr ecx, 8
    add r11d, ecx
    cmp r11d, 65535
    jbe .ok_r
    mov r11d, 65535
.ok_r:
    mov ecx, r11d
    shr ecx, 4
    cmp ecx, 4095
    jbe .ok_ri
    mov ecx, 4095
.ok_ri:
    movzx ecx, word [linear_to_srgb_lut + rcx * 2]
    shr ecx, 8
    mov [rbx + 2], cl
    ; alpha: src_over
    mov eax, edx
    shr eax, 24
    mov ecx, eax
    sub ecx, r8d
    imul ecx, edi
    shr ecx, 8
    add r8d, ecx
    cmp r8d, 255
    jbe .ok_a
    mov r8d, 255
.ok_a:
    mov [rbx + 3], r8b
    jmp .next
.opaque:
    mov [rbx], eax
.next:
    add rbx, 4
    add r12, 4
    dec r13
    jnz .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global blend_linear_version
blend_linear_version: dq 0x010000
