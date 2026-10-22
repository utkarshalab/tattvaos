; VP8 quant-factor construction and macroblock dequantization.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern webp_vp8_iwht4x4

section .text

; eax=signed qindex -> eax clamped to 0..127.
vp8_clamp_q:
    test eax,eax
    jns .q_high
    xor eax,eax
    ret
.q_high:
    cmp eax,127
    jbe .q_done
    mov eax,127
.q_done:
    ret

; WebPVP8Config*,segment_id,WebPVP8QuantFactors* -> 0/-EINVAL.
global webp_vp8_quant_factors
webp_vp8_quant_factors:
    PROLOGUE_SAVE rbx,r12,r13
    mov rbx,rdi
    mov r12d,esi
    mov r13,rdx
    test rbx,rbx
    jz .factors_bad
    test r13,r13
    jz .factors_bad
    cmp r12d,3
    ja .factors_bad
    mov edx,[rbx+WebPVP8Config.base_qindex]
    cmp dword [rbx+WebPVP8Config.segmentation],0
    je .base_ready
    mov eax,[rbx+WebPVP8Config.segment_quant+r12*4]
    cmp dword [rbx+WebPVP8Config.segment_absolute],0
    jne .absolute_q
    add edx,eax
    jmp .base_ready
.absolute_q:
    mov edx,eax
.base_ready:
    mov r12d,edx
    mov eax,r12d
    add eax,[rbx+WebPVP8Config.quant_deltas]
    call vp8_clamp_q
    lea rcx,[rel vp8_dc_qlookup]
    mov ax,[rcx+rax*2]
    mov [r13+WebPVP8QuantFactors.y1_dc],ax
    mov eax,r12d
    call vp8_clamp_q
    lea rcx,[rel vp8_ac_qlookup]
    mov ax,[rcx+rax*2]
    mov [r13+WebPVP8QuantFactors.y1_ac],ax
    mov eax,r12d
    add eax,[rbx+WebPVP8Config.quant_deltas+12]
    call vp8_clamp_q
    lea rcx,[rel vp8_dc_qlookup]
    movzx edx,word [rcx+rax*2]
    cmp edx,132
    jbe .uv_dc_ready
    mov edx,132
.uv_dc_ready:
    mov [r13+WebPVP8QuantFactors.uv_dc],dx
    mov eax,r12d
    add eax,[rbx+WebPVP8Config.quant_deltas+16]
    call vp8_clamp_q
    lea rcx,[rel vp8_ac_qlookup]
    mov ax,[rcx+rax*2]
    mov [r13+WebPVP8QuantFactors.uv_ac],ax
    mov eax,r12d
    add eax,[rbx+WebPVP8Config.quant_deltas+4]
    call vp8_clamp_q
    lea rcx,[rel vp8_dc_qlookup]
    movzx edx,word [rcx+rax*2]
    shl edx,1
    mov [r13+WebPVP8QuantFactors.y2_dc],dx
    mov eax,r12d
    add eax,[rbx+WebPVP8Config.quant_deltas+8]
    call vp8_clamp_q
    lea rcx,[rel vp8_ac_qlookup]
    movzx eax,word [rcx+rax*2]
    imul eax,155
    xor edx,edx
    mov ecx,100
    div ecx
    cmp eax,8
    jae .y2_ac_ready
    mov eax,8
.y2_ac_ready:
    mov [r13+WebPVP8QuantFactors.y2_ac],ax
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13
.factors_bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13

; source[16],destination[16],dc_factor,ac_factor -> 0/-EINVAL.
global webp_vp8_dequant_block
webp_vp8_dequant_block:
    test rdi,rdi
    jz .block_bad
    test rsi,rsi
    jz .block_bad
    movsx eax,word [rdi]
    imul eax,edx
    mov [rsi],ax
    mov r8d,1
.block_ac:
    movsx eax,word [rdi+r8*2]
    imul eax,ecx
    mov [rsi+r8*2],ax
    inc r8d
    cmp r8d,16
    jb .block_ac
    xor eax,eax
    ret
.block_bad:
    mov rax,-EINVAL
    ret

; coeffs[25][16],WebPVP8QuantFactors*,y_mode -> 0/-EINVAL.
global webp_vp8_dequant_macroblock
webp_vp8_dequant_macroblock:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,64
    mov rbx,rdi
    mov r12,rsi
    mov r13d,edx
    test rbx,rbx
    jz .macro_bad
    test r12,r12
    jz .macro_bad
    cmp r13d,VP8_Y_MODE_B_PRED
    ja .macro_bad
    cmp r13d,VP8_Y_MODE_B_PRED
    je .macro_y1_all
    lea rdi,[rbx+24*32]
    lea rsi,[rsp]
    movzx edx,word [r12+WebPVP8QuantFactors.y2_dc]
    movzx ecx,word [r12+WebPVP8QuantFactors.y2_ac]
    call webp_vp8_dequant_block
    test eax,eax
    js .macro_bad
    lea rdi,[rsp]
    lea rsi,[rsp+32]
    call webp_vp8_iwht4x4
    test eax,eax
    js .macro_bad
    xor r14d,r14d
.inject_y2:
    mov ax,[rsp+32+r14*2]
    mov edx,r14d
    shl edx,5
    mov [rbx+rdx],ax
    inc r14d
    cmp r14d,16
    jb .inject_y2
    xor r14d,r14d
.macro_y1_ac:
    mov r10,r14
    shl r10,5
    add r10,rbx
    mov r15d,1
.y1_ac_loop:
    movsx eax,word [r10+r15*2]
    movzx ecx,word [r12+WebPVP8QuantFactors.y1_ac]
    imul eax,ecx
    mov [r10+r15*2],ax
    inc r15d
    cmp r15d,16
    jb .y1_ac_loop
    inc r14d
    cmp r14d,16
    jb .macro_y1_ac
    jmp .macro_uv
.macro_y1_all:
    xor r14d,r14d
.y1_block:
    mov rdi,r14
    shl rdi,5
    add rdi,rbx
    mov rsi,rdi
    movzx edx,word [r12+WebPVP8QuantFactors.y1_dc]
    movzx ecx,word [r12+WebPVP8QuantFactors.y1_ac]
    call webp_vp8_dequant_block
    test eax,eax
    js .macro_bad
    inc r14d
    cmp r14d,16
    jb .y1_block
.macro_uv:
    mov r14d,16
.uv_block:
    mov rdi,r14
    shl rdi,5
    add rdi,rbx
    mov rsi,rdi
    movzx edx,word [r12+WebPVP8QuantFactors.uv_dc]
    movzx ecx,word [r12+WebPVP8QuantFactors.uv_ac]
    call webp_vp8_dequant_block
    test eax,eax
    js .macro_bad
    inc r14d
    cmp r14d,24
    jb .uv_block
    xor eax,eax
    add rsp,64
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.macro_bad:
    mov rax,-EINVAL
    add rsp,64
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

section .rodata
; RFC 6386 section 14.1, 128 signed-integer quantizer entries each.
vp8_dc_qlookup:
    dw 4,5,6,7,8,9,10,10,11,12,13,14,15,16,17,17
    dw 18,19,20,20,21,21,22,22,23,23,24,25,25,26,27,28
    dw 29,30,31,32,33,34,35,36,37,37,38,39,40,41,42,43
    dw 44,45,46,46,47,48,49,50,51,52,53,54,55,56,57,58
    dw 59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74
    dw 75,76,76,77,78,79,80,81,82,83,84,85,86,87,88,89
    dw 91,93,95,96,98,100,101,102,104,106,108,110,112,114,116,118
    dw 122,124,126,128,130,132,134,136,138,140,143,145,148,151,154,157

vp8_ac_qlookup:
    dw 4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    dw 20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35
    dw 36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51
    dw 52,53,54,55,56,57,58,60,62,64,66,68,70,72,74,76
    dw 78,80,82,84,86,88,90,92,94,96,98,100,102,104,106,108
    dw 110,112,114,116,119,122,125,128,131,134,137,140,143,146,149,152
    dw 155,158,161,164,167,170,173,177,181,185,189,193,197,201,205,209
    dw 213,217,221,225,229,234,239,245,249,254,259,264,269,274,279,284
