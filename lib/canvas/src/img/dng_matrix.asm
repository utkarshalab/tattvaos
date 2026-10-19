; DNG ColorMatrix1 conversion: XYZ(D50)->camera becomes camera->linear sRGB.
%include "inc/abi.inc"
%include "inc/macros.inc"

%define M0   0
%define M1   8
%define M2  16
%define M3  24
%define M4  32
%define M5  40
%define M6  48
%define M7  56
%define M8  64
%define C0  72
%define C1  80
%define C2  88
%define C3  96
%define C4 104
%define C5 112
%define C6 120
%define C7 128
%define C8 136
%define LOCAL_SIZE 144

%macro COFACTOR 5
    mov rax,[r15+%2]
    imul rax,[r15+%3]
    mov rcx,[r15+%4]
    imul rcx,[r15+%5]
    sub rax,rcx
    mov [r15+%1],rax
%endmacro

%macro INVERSE 2
    mov rax,[r15+%2]
    mov rdx,rax
    shl rax,32
    sar rdx,32
    idiv r14
    cmp rax,0x7fffffff
    jg %%bad
    cmp rax,-0x80000000
    jl %%bad
    mov [rbx+%1*4],eax
    jmp %%done
%%bad:
    jmp .bad
%%done:
%endmacro

%macro PRODUCT_ROW 4
    movsxd rax,dword [r15+M0+%2*24]
    imul rax,%3
    movsxd rcx,dword [r15+M0+%2*24+8]
    imul rcx,%4
    add rax,rcx
    movsxd rcx,dword [r15+M0+%2*24+16]
    imul rcx,%1
    add rax,rcx
%endmacro

section .text

; IN rdi = signed 16.16 ColorMatrix1[9]. Converts in place, returns 0/-1.
global dng_prepare_color_matrix
dng_prepare_color_matrix:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,LOCAL_SIZE
    mov rbx,rdi
    mov r15,rsp
    xor ecx,ecx
.copy_input:
    movsxd rax,dword [rbx+rcx*4]
    mov [r15+rcx*8],rax
    inc ecx
    cmp ecx,9
    jb .copy_input
    COFACTOR C0,M4,M8,M5,M7
    COFACTOR C1,M5,M6,M3,M8
    COFACTOR C2,M3,M7,M4,M6
    COFACTOR C3,M2,M7,M1,M8
    COFACTOR C4,M0,M8,M2,M6
    COFACTOR C5,M1,M6,M0,M7
    COFACTOR C6,M1,M5,M2,M4
    COFACTOR C7,M2,M3,M0,M5
    COFACTOR C8,M0,M4,M1,M3
    mov r14,[r15+M0]
    imul r14,[r15+C0]
    mov rax,[r15+M1]
    imul rax,[r15+C1]
    add r14,rax
    mov rax,[r15+M2]
    imul rax,[r15+C2]
    add r14,rax
    test r14,r14
    jz .bad
    ; Adjugate transpose divided by determinant, yielding camera->XYZ D50.
    INVERSE 0,C0
    INVERSE 1,C3
    INVERSE 2,C6
    INVERSE 3,C1
    INVERSE 4,C4
    INVERSE 5,C7
    INVERSE 6,C2
    INVERSE 7,C5
    INVERSE 8,C8
    ; Preserve the inverse as sign-extended qwords before overwriting output.
    xor ecx,ecx
.copy_inverse:
    movsxd rax,dword [rbx+rcx*4]
    mov [r15+rcx*8],rax
    inc ecx
    cmp ecx,9
    jb .copy_inverse
    ; K = linear-sRGB(D65) * Bradford(D50->D65), signed 16.16.
    xor r12d,r12d                    ; output row
.out_row:
    xor r13d,r13d                    ; output column
.out_col:
    mov eax,r12d
    imul eax,3
    lea rdx,[rel d50_xyz_to_srgb]
    movsxd r8,dword [rdx+rax*4]
    movsxd r9,dword [rdx+rax*4+4]
    movsxd r10,dword [rdx+rax*4+8]
    mov eax,r13d
    movsxd rax,dword [r15+rax*8]
    imul rax,r8
    lea ecx,[r13d+3]
    movsxd rcx,dword [r15+rcx*8]
    imul rcx,r9
    add rax,rcx
    lea ecx,[r13d+6]
    movsxd rcx,dword [r15+rcx*8]
    imul rcx,r10
    add rax,rcx
    sar rax,16
    cmp rax,0x7fffffff
    jg .bad
    cmp rax,-0x80000000
    jl .bad
    mov edx,r12d
    imul edx,3
    add edx,r13d
    mov [rbx+rdx*4],eax
    inc r13d
    cmp r13d,3
    jb .out_col
    inc r12d
    cmp r12d,3
    jb .out_row
    xor eax,eax
    add rsp,LOCAL_SIZE
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    mov rax,-1
    add rsp,LOCAL_SIZE
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .rodata
align 4
d50_xyz_to_srgb:
    dd 205380,-105963,-32153
    dd -64145,125576,2192
    dd 4715,-15007,92094

section .data
global dng_matrix_version
dng_matrix_version: dq 0x010000
