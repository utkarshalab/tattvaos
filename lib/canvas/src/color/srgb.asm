; ============================================================================
; sRGB — the sRGB transfer functions, exact (IEC 61966-2-1)
; ============================================================================
; COL-01. srgb_eotf_f64 and srgb_oetf_f64 are the curves themselves, in
; doubles (umath_pow_f64): encoded to linear, x / 12.92 up to 0.04045 then
; ((x + 0.055) / 1.055)^2.4, and back, 12.92 x up to 0.0031308 then
; 1.055 x^(1/2.4) - 0.055. srgb_init fills, once, the tables built from
; them, each value rounded to nearest:
;   srgb_to_linear_lut  256 u16: a code's linear value, of 65535
;   linear_to_srgb_lut  4096 u16: linear i / 4095 encoded, of 65535
;   srgb_encode_lut     65536 u8: a 16-bit linear value's code, exactly
;                       round(255 x oetf(v / 65535)) (by each code's
;                       threshold, eotf((k - 0.5) / 255))

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern umath_pow_f64

section .bss
global srgb_to_linear_lut
global linear_to_srgb_lut
global srgb_encode_lut
srgb_to_linear_lut: resw 256
linear_to_srgb_lut: resw 4096
srgb_encode_lut:    resb 65536
srgb_ready:         resb 1

section .text

; ---------------------------------------------------------------------------
; srgb_eotf_f64 / srgb_oetf_f64
;   IN:  xmm0 = 0 to 1, encoded / linear
;   OUT: xmm0 = linear / encoded
; ---------------------------------------------------------------------------
global srgb_eotf_f64
srgb_eotf_f64:
    ucomisd xmm0, [rel c_eotf_knee]
    ja .curve
    divsd xmm0, [rel c_12_92]
    ret
.curve:
    sub rsp, 8
    addsd xmm0, [rel c_0_055]
    divsd xmm0, [rel c_1_055]
    movsd xmm1, [rel c_2_4]
    call umath_pow_f64
    add rsp, 8
    ret

global srgb_oetf_f64
srgb_oetf_f64:
    ucomisd xmm0, [rel c_oetf_knee]
    ja .curve
    mulsd xmm0, [rel c_12_92]
    ret
.curve:
    sub rsp, 8
    movsd xmm1, [rel c_inv_2_4]
    call umath_pow_f64
    mulsd xmm0, [rel c_1_055]
    subsd xmm0, [rel c_0_055]
    add rsp, 8
    ret

; ---------------------------------------------------------------------------
; srgb_init
;   The tables, the first time
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global srgb_init
srgb_init:
    cmp byte [rel srgb_ready], 0
    je .build
    xor eax, eax
    ret
.build:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 16                         ; the next code's threshold
    xor ebx, ebx
.to_linear:
    cvtsi2sd xmm0, ebx
    divsd xmm0, [rel c_255]
    call srgb_eotf_f64
    mulsd xmm0, [rel c_65535]
    cvtsd2si eax, xmm0
    lea r11, [rel srgb_to_linear_lut]
    mov [r11 + rbx * 2], ax
    inc ebx
    cmp ebx, 256
    jb .to_linear
    xor ebx, ebx
.to_srgb:
    cvtsi2sd xmm0, ebx
    divsd xmm0, [rel c_4095]
    call srgb_oetf_f64
    mulsd xmm0, [rel c_65535]
    cvtsd2si eax, xmm0
    call clamp_u16
    lea r11, [rel linear_to_srgb_lut]
    mov [r11 + rbx * 2], ax
    inc ebx
    cmp ebx, 4096
    jb .to_srgb
    xor ebx, ebx                        ; v
    xor r12d, r12d                      ; its code
    mov edi, 1
    call threshold
    movsd [rsp], xmm0
.encode:
    cmp r12d, 255
    jae .store
    cvtsi2sd xmm0, ebx
    ucomisd xmm0, [rsp]
    jb .store
    inc r12d                            ; past the next code's threshold
    cmp r12d, 255
    jae .encode
    lea edi, [r12 + 1]
    call threshold
    movsd [rsp], xmm0
    jmp .encode
.store:
    lea r11, [rel srgb_encode_lut]
    mov [r11 + rbx], r12b
    inc ebx
    cmp ebx, 65536
    jb .encode
    mov byte [rel srgb_ready], 1
    xor eax, eax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12

; edi = a code 1 to 255 -> xmm0 = the 16-bit linear value where it begins,
; eotf((k - 0.5) / 255) x 65535
threshold:
    sub rsp, 8
    cvtsi2sd xmm0, edi
    subsd xmm0, [rel c_0_5]
    divsd xmm0, [rel c_255]
    call srgb_eotf_f64
    mulsd xmm0, [rel c_65535]
    add rsp, 8
    ret

; eax -> eax within 0 to 65535
clamp_u16:
    test eax, eax
    jns .low
    xor eax, eax
.low:
    cmp eax, 65535
    jbe .out
    mov eax, 65535
.out:
    ret

; ---------------------------------------------------------------------------
; srgb_to_linear_u8
;   IN:  rdi = a code's byte
;   OUT: eax = its linear value, of 65535
; ---------------------------------------------------------------------------
global srgb_to_linear_u8
srgb_to_linear_u8:
    push rdi
    call srgb_init
    pop rdi
    movzx eax, byte [rdi]
    lea r11, [rel srgb_to_linear_lut]
    movzx eax, word [r11 + rax * 2]
    ret

; ---------------------------------------------------------------------------
; srgb_from_linear_u16
;   IN:  edi = a linear value, of 65535
;   OUT: eax = its code
; ---------------------------------------------------------------------------
global srgb_from_linear_u16
srgb_from_linear_u16:
    push rdi
    call srgb_init
    pop rdi
    mov eax, edi
    call clamp_u16
    lea r11, [rel srgb_encode_lut]
    movzx eax, byte [r11 + rax]
    ret

section .rodata
align 8
c_eotf_knee:    dq 0.04045
c_oetf_knee:    dq 0.0031308
c_12_92:        dq 12.92
c_0_055:        dq 0.055
c_1_055:        dq 1.055
c_2_4:          dq 2.4
c_inv_2_4:      dq 0.41666666666666666667
c_255:          dq 255.0
c_4095:         dq 4095.0
c_65535:        dq 65535.0
c_0_5:          dq 0.5

section .data
global srgb_version
srgb_version: dq 0x020000
