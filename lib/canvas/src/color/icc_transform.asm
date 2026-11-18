; ============================================================================
; ICC Transform — an embedded matrix/TRC profile's colours into sRGB
; ============================================================================
; COL-02. icc_transform_build reads an ICC profile (v2 or v4) of the
; matrix/TRC kind, RGB (rXYZ, gXYZ, bXYZ; rTRC, gTRC, bTRC) or grey (kTRC),
; XYZ connection space; any A2B tables beside them are not used (COL-03).
; Each channel's curve, curv (identity, a gamma, or a table interpolated)
; or para (functions 0 to 4), becomes 256 linear values; the colorants
; (D50) times XYZ_TO_SRGB, the inverse of the sRGB profile's own D50
; colorants, make one matrix from linear source to linear sRGB.
; icc_transform_pixbuf then turns each pixel's channels to linear, through
; the matrix, clamped, and into sRGB codes (srgb_encode_lut). A profile
; that maps every code to itself (the sRGB one, as a rule) is no transform.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern umath_pow_f64
extern srgb_init
extern srgb_encode_lut

%define ICC_RGB     1
%define ICC_GREY    2

struc IccTransform
    .kind:      resd 1
    .pad:       resd 1
    .m:         resq 9                  ; by rows: sRGB r, g, b of r, g, b
    .lut:       resq 3 * 256            ; linear, by channel r, g, b
endstruc

; icc_transform_build's locals: the colorants by rows (X, Y, Z of r, g, b
; columns); a curve's seven parameters
%define B_S         0
%define B_P         72
%define B_FRAME     (B_P + 56 + 8)

section .text

; ---------------------------------------------------------------------------
; icc_transform_build
;   IN:  rdi = arena*, rsi = an ICC profile, rdx = its length
;   OUT: rax = IccTransform*, 0 when there is nothing to do (sRGB, not a
;        matrix/TRC profile, malformed, out of memory)
; ---------------------------------------------------------------------------
global icc_transform_build
icc_transform_build:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, B_FRAME
    mov r14, rdi
    mov r12, rsi
    mov r13, rdx
    call srgb_init
    cmp r13, 132
    jb .none
    cmp dword [r12 + 20], 'XYZ '        ; the connection space
    jne .none
    mov eax, [r12 + 16]                 ; the colour space
    mov r15d, ICC_RGB
    cmp eax, 'RGB '
    je .space
    mov r15d, ICC_GREY
    cmp eax, 'GRAY'
    jne .none
.space:
    mov rdi, r14
    mov esi, IccTransform_size
    call arena_alloc
    test rax, rax
    jz .none
    mov rbx, rax
    mov [rbx + IccTransform.kind], r15d
    cmp r15d, ICC_GREY
    je .grey
    mov edi, 'rXYZ'
    lea rsi, [rsp + B_S]
    call read_xyz
    jnz .none
    mov edi, 'gXYZ'
    lea rsi, [rsp + B_S + 8]
    call read_xyz
    jnz .none
    mov edi, 'bXYZ'
    lea rsi, [rsp + B_S + 16]
    call read_xyz
    jnz .none
    mov edi, 'rTRC'
    lea rsi, [rbx + IccTransform.lut]
    call curve
    jnz .none
    mov edi, 'gTRC'
    lea rsi, [rbx + IccTransform.lut + 256 * 8]
    call curve
    jnz .none
    mov edi, 'bTRC'
    lea rsi, [rbx + IccTransform.lut + 512 * 8]
    call curve
    jnz .none
    ; m = XYZ_TO_SRGB x the colorants
    xor ecx, ecx                        ; row
.row:
    xor edx, edx                        ; column
.column:
    lea r8, [rel xyz_to_srgb]
    imul eax, ecx, 24
    add r8, rax                         ; its row
    lea r9, [rsp + B_S + rdx * 8]       ; the colorants' column
    movsd xmm0, [r8]
    mulsd xmm0, [r9]
    movsd xmm1, [r8 + 8]
    mulsd xmm1, [r9 + 24]
    addsd xmm0, xmm1
    movsd xmm1, [r8 + 16]
    mulsd xmm1, [r9 + 48]
    addsd xmm0, xmm1
    imul eax, ecx, 3
    add eax, edx
    movsd [rbx + IccTransform.m + rax * 8], xmm0
    inc edx
    cmp edx, 3
    jb .column
    inc ecx
    cmp ecx, 3
    jb .row
    ; nothing to do: the matrix the identity, each curve sRGB's
    xor ecx, ecx
.identity:
    movsd xmm0, [rbx + IccTransform.m + rcx * 8]
    lea r8, [rel identity]
    subsd xmm0, [r8 + rcx * 8]
    andpd xmm0, [rel abs_mask]
    ucomisd xmm0, [rel c_matrix_tolerance]
    ja .needed
    inc ecx
    cmp ecx, 9
    jb .identity
    mov ecx, 768
    jmp .codes
.grey:
    mov edi, 'kTRC'
    lea rsi, [rbx + IccTransform.lut]
    call curve
    jnz .none
    mov ecx, 256
.codes:                                 ; each code back to itself?
    xor edx, edx
.code:
    movsd xmm0, [rbx + IccTransform.lut + rdx * 8]
    call encode
    mov r8d, edx
    and r8d, 255
    cmp eax, r8d
    jne .needed
    inc edx
    cmp edx, ecx
    jb .code
    jmp .none
.needed:
    mov rax, rbx
    jmp .out
.none:
    xor eax, eax
.out:
    add rsp, B_FRAME
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; icc_transform_pixbuf
;   An image's pixels from the profile's colours into sRGB, alpha kept
;   IN:  rdi = IccTransform*, rsi = PixBuf* (BGRA8888, straight alpha)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global icc_transform_pixbuf
icc_transform_pixbuf:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d                      ; y
.row:
    cmp r13, [r12 + PixBuf.height]
    jae .done
    mov r14, r13
    imul r14, [r12 + PixBuf.stride]
    add r14, [r12 + PixBuf.data]
    xor r15d, r15d                      ; x
.pixel:
    cmp r15, [r12 + PixBuf.width]
    jae .next_row
    lea rdi, [r14 + r15 * 4]
    cmp dword [rbx + IccTransform.kind], ICC_GREY
    je .grey
    movzx eax, byte [rdi + 2]           ; linear r, g, b
    movsd xmm2, [rbx + IccTransform.lut + rax * 8]
    movzx eax, byte [rdi + 1]
    movsd xmm3, [rbx + IccTransform.lut + 256 * 8 + rax * 8]
    movzx eax, byte [rdi]
    movsd xmm4, [rbx + IccTransform.lut + 512 * 8 + rax * 8]
    xor ecx, ecx                        ; sRGB r, g, b: rows of m
.channel:
    imul eax, ecx, 24
    movsd xmm0, [rbx + IccTransform.m + rax]
    mulsd xmm0, xmm2
    movsd xmm1, [rbx + IccTransform.m + rax + 8]
    mulsd xmm1, xmm3
    addsd xmm0, xmm1
    movsd xmm1, [rbx + IccTransform.m + rax + 16]
    mulsd xmm1, xmm4
    addsd xmm0, xmm1
    call encode
    mov edx, 2                          ; r at 2, g 1, b 0
    sub edx, ecx
    mov [rdi + rdx], al
    inc ecx
    cmp ecx, 3
    jb .channel
    jmp .next
.grey:
    xor ecx, ecx
.grey_channel:
    movzx eax, byte [rdi + rcx]
    movsd xmm0, [rbx + IccTransform.lut + rax * 8]
    call encode
    mov [rdi + rcx], al
    inc ecx
    cmp ecx, 3
    jb .grey_channel
.next:
    inc r15
    jmp .pixel
.next_row:
    inc r13
    jmp .row
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; xmm0 = linear -> eax = its sRGB code (clamped to 0 to 1; NaN 0); rcx,
; rdx, rdi kept
encode:
    xorpd xmm1, xmm1
    maxsd xmm0, xmm1                    ; NaN: 0
    minsd xmm0, [rel c_one]
    mulsd xmm0, [rel c_65535]
    cvtsd2si eax, xmm0
    lea r8, [rel srgb_encode_lut]
    movzx eax, byte [r8 + rax]
    ret

; edi = a tag's signature; r12 = the profile, r13 its length -> rax = the
; tag's data (0 none or out of the profile), rdx = its size
find_tag:
    mov ecx, [r12 + 128]
    bswap ecx
    imul rax, rcx, 12
    add rax, 132
    cmp rax, r13
    ja .none
    xor r8d, r8d
.tag:
    cmp r8d, ecx
    jae .none
    lea r9, [r8 + r8 * 2]
    lea r9, [r12 + r9 * 4 + 132]
    cmp [r9], edi
    je .found
    inc r8d
    jmp .tag
.found:
    mov eax, [r9 + 4]
    bswap eax
    mov edx, [r9 + 8]
    bswap edx
    lea r10, [rax + rdx]
    cmp r10, r13
    ja .none
    add rax, r12
    ret
.none:
    xor eax, eax
    xor edx, edx
    ret

; rax = a big-endian s15Fixed16 -> xmm0
%macro S15 1
    mov eax, %1
    bswap eax
    cvtsi2sd xmm0, eax
    divsd xmm0, [rel c_65536]
%endmacro

; edi = an XYZ tag, rsi = a column of the colorants (rows 24 bytes apart)
; -> ZF set read
read_xyz:
    push rsi
    call find_tag
    pop rsi
    test rax, rax
    jz .no
    cmp edx, 20
    jb .no
    cmp dword [rax], 'XYZ '
    jne .no
    mov rdi, rax
    S15 [rdi + 8]
    movsd [rsi], xmm0
    S15 [rdi + 12]
    movsd [rsi + 24], xmm0
    S15 [rdi + 16]
    movsd [rsi + 48], xmm0
    cmp eax, eax
    ret
.no:
    test esp, esp
    ret

; edi = a TRC tag, rsi = 256 doubles: each code's linear value, 0 to 1
; -> ZF set read
curve:
    push rbx
    push r14
    push r15
    sub rsp, 64                         ; seven parameters, the input
    mov rbx, rsi
    call find_tag
    test rax, rax
    jz .no
    cmp edx, 12
    jb .no
    mov r14, rax
    mov r15d, edx
    cmp dword [r14], 'curv'
    je .curv
    cmp dword [r14], 'para'
    jne .no
    ; para: g, a, b, c, d, e, f as function 4 makes them
    movzx eax, word [r14 + 8]
    rol ax, 8
    cmp eax, 4
    ja .no
    lea rcx, [rel para_counts]
    movzx ecx, byte [rcx + rax]
    lea edx, [rcx * 4 + 12]
    cmp r15d, edx
    jb .no
    mov r8d, eax                        ; the function
    xor edx, edx                        ; all 0, a 1
.clear:
    mov qword [rsp + rdx * 8], 0
    inc edx
    cmp edx, 7
    jb .clear
    mov rax, [rel c_one]
    mov [rsp + 8], rax
    xor edx, edx
.param:
    cmp edx, ecx
    jae .params
    S15 [r14 + rdx * 4 + 12]
    movsd [rsp + rdx * 8], xmm0
    inc edx
    jmp .param
.params:
    cmp r8d, 3
    jae .evaluate
    cmp r8d, 0
    je .evaluate
    ; 1 and 2: from -b / a up the power (plus c for 2), below it 0 (or c)
    movsd xmm0, [rsp + 8]
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    je .no
    movsd xmm1, [rsp + 16]
    divsd xmm1, xmm0
    xorpd xmm0, xmm0
    subsd xmm0, xmm1
    movsd [rsp + 32], xmm0              ; d = -b / a
    xor eax, eax
    cmp r8d, 2
    jne .no_offset
    mov rax, [rsp + 24]                 ; e = f = c
.no_offset:
    mov [rsp + 40], rax
    mov [rsp + 48], rax
    mov qword [rsp + 24], 0             ; no linear part
.evaluate:
    xor r15d, r15d
.para_code:
    cvtsi2sd xmm0, r15d
    divsd xmm0, [rel c_255]
    movsd [rsp + 56], xmm0
    ucomisd xmm0, [rsp + 32]
    jae .power
    mulsd xmm0, [rsp + 24]              ; c x + f
    addsd xmm0, [rsp + 48]
    jmp .para_store
.power:                                 ; (a x + b)^g + e
    mulsd xmm0, [rsp + 8]
    addsd xmm0, [rsp + 16]
    xorpd xmm1, xmm1
    maxsd xmm0, xmm1
    movsd xmm1, [rsp]
    call umath_pow_f64
    addsd xmm0, [rsp + 40]
.para_store:
    call unit
    movsd [rbx + r15 * 8], xmm0
    inc r15d
    cmp r15d, 256
    jb .para_code
    jmp .yes
.curv:
    mov ecx, [r14 + 8]
    bswap ecx                           ; entries
    lea rax, [rcx * 2 + 12]
    cmp rax, r15
    ja .no
    xor r15d, r15d
    cmp ecx, 1
    ja .table
    je .gamma
.identity:
    cvtsi2sd xmm0, r15d
    divsd xmm0, [rel c_255]
    movsd [rbx + r15 * 8], xmm0
    inc r15d
    cmp r15d, 256
    jb .identity
    jmp .yes
.gamma:                                 ; u8Fixed8
    movzx eax, word [r14 + 12]
    rol ax, 8
    cvtsi2sd xmm0, eax
    divsd xmm0, [rel c_256]
    movsd [rsp], xmm0
.gamma_code:
    cvtsi2sd xmm0, r15d
    divsd xmm0, [rel c_255]
    movsd xmm1, [rsp]
    call umath_pow_f64
    call unit
    movsd [rbx + r15 * 8], xmm0
    inc r15d
    cmp r15d, 256
    jb .gamma_code
    jmp .yes
.table:                                 ; at i / 255 x (n - 1), interpolated
    mov [rsp], ecx
.table_code:
    mov ecx, [rsp]
    dec ecx
    cvtsi2sd xmm0, r15d
    cvtsi2sd xmm1, ecx
    mulsd xmm0, xmm1
    divsd xmm0, [rel c_255]
    cvttsd2si eax, xmm0                 ; the entry at or below
    cmp eax, ecx
    jb .inside
    mov eax, ecx
.inside:
    cvtsi2sd xmm1, eax
    subsd xmm0, xmm1                    ; how far to the next
    movzx edx, word [r14 + rax * 2 + 12]
    rol dx, 8
    cvtsi2sd xmm2, edx
    lea edx, [rax + 1]
    cmp edx, ecx
    jbe .next_entry
    mov edx, ecx
.next_entry:
    movzx edx, word [r14 + rdx * 2 + 12]
    rol dx, 8
    cvtsi2sd xmm3, edx
    subsd xmm3, xmm2
    mulsd xmm3, xmm0
    addsd xmm2, xmm3
    divsd xmm2, [rel c_65535]
    movapd xmm0, xmm2
    call unit
    movsd [rbx + r15 * 8], xmm0
    inc r15d
    cmp r15d, 256
    jb .table_code
.yes:
    xor eax, eax
    jmp .out
.no:
    or eax, 1
.out:
    lea rsp, [rsp + 64]                 ; ZF kept
    pop r15
    pop r14
    pop rbx
    ret

; xmm0 -> within 0 to 1
unit:
    xorpd xmm1, xmm1
    maxsd xmm0, xmm1
    minsd xmm0, [rel c_one]
    ret

section .rodata
align 16
abs_mask:       dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
; XYZ (D50) to linear sRGB: the inverse of the sRGB profile's colorants,
; r (0.43604125, 0.22248454, 0.01392019), g (0.38511291, 0.71690508,
; 0.09706724), b (0.14304584, 0.06061038, 0.71391257), as the reference
; colour management library makes them
xyz_to_srgb:
    dq 3.1341863642368204, -1.6172089589982754, -0.49069406400638405
    dq -0.9787485041906937, 1.9161300967735857, 0.033433399159995505
    dq 0.07196392780224674, -0.2289938734532031, 1.4057537328964436
identity:
    dq 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0
c_matrix_tolerance: dq 0.002
c_one:          dq 1.0
c_255:          dq 255.0
c_256:          dq 256.0
c_65535:        dq 65535.0
c_65536:        dq 65536.0
; para's parameters by function
para_counts:    db 1, 3, 4, 5, 7

section .data
global icc_transform_version
icc_transform_version: dq 0x010000
