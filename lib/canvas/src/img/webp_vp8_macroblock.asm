; VP8 keyframe macroblock coefficient orchestration.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern webp_vp8_decode_block
extern webp_bool_get

section .text

; WebPBoolReader*,WebPVP8Modes* -> 0/-EINVAL.
global webp_vp8_decode_keyframe_base_modes
webp_vp8_decode_keyframe_base_modes:
    PROLOGUE_SAVE rbx,r12
    mov rbx,rdi
    mov r12,rsi
    test rbx,rbx
    jz .modes_bad
    test r12,r12
    jz .modes_bad
    mov rdi,rbx
    mov esi,145
    call webp_bool_get
    test eax,eax
    js .modes_bad
    test eax,eax
    jz .mode_bpred
    mov rdi,rbx
    mov esi,156
    call webp_bool_get
    test eax,eax
    js .modes_bad
    test eax,eax
    jnz .mode_h_tm
    mov rdi,rbx
    mov esi,163
    call webp_bool_get
    test eax,eax
    js .modes_bad
    mov [r12+WebPVP8Modes.y_mode],eax ; DC=0, V=1
    jmp .mode_uv
.mode_h_tm:
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test eax,eax
    js .modes_bad
    add eax,2                         ; H=2, TM=3
    mov [r12+WebPVP8Modes.y_mode],eax
    jmp .mode_uv
.mode_bpred:
    mov dword [r12+WebPVP8Modes.y_mode],VP8_Y_MODE_B_PRED
.mode_uv:
    mov rdi,rbx
    mov esi,142
    call webp_bool_get
    test eax,eax
    js .modes_bad
    test eax,eax
    jz .mode_uv_dc
    mov rdi,rbx
    mov esi,114
    call webp_bool_get
    test eax,eax
    js .modes_bad
    test eax,eax
    jz .mode_uv_v
    mov rdi,rbx
    mov esi,183
    call webp_bool_get
    test eax,eax
    js .modes_bad
    add eax,2                         ; H=2, TM=3
    mov [r12+WebPVP8Modes.uv_mode],eax
    jmp .modes_ok
.mode_uv_v:
    mov dword [r12+WebPVP8Modes.uv_mode],1
    jmp .modes_ok
.mode_uv_dc:
    mov dword [r12+WebPVP8Modes.uv_mode],0
.modes_ok:
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12
.modes_bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12

%macro BMODE_NODE 2
    mov rdi,rbx
    movzx esi,byte [r12+%1]
    call webp_bool_get
    test eax,eax
    js .bmode_bad
    jz %2
%endmacro

; WebPBoolReader*,probabilities[9] -> mode 0..9/-EINVAL.
global webp_vp8_decode_bmode
webp_vp8_decode_bmode:
    PROLOGUE_SAVE rbx,r12
    mov rbx,rdi
    mov r12,rsi
    test rbx,rbx
    jz .bmode_bad
    test r12,r12
    jz .bmode_bad
    BMODE_NODE 0,.bmode_dc
    BMODE_NODE 1,.bmode_tm
    BMODE_NODE 2,.bmode_ve
    BMODE_NODE 3,.bmode_com_left
    BMODE_NODE 6,.bmode_ld
    BMODE_NODE 7,.bmode_vl
    BMODE_NODE 8,.bmode_hd
    mov eax,VP8_BMODE_HU
    EPILOGUE_RESTORE rbx,r12
.bmode_hd:
    mov eax,VP8_BMODE_HD
    EPILOGUE_RESTORE rbx,r12
.bmode_vl:
    mov eax,VP8_BMODE_VL
    EPILOGUE_RESTORE rbx,r12
.bmode_ld:
    mov eax,VP8_BMODE_LD
    EPILOGUE_RESTORE rbx,r12
.bmode_com_left:
    BMODE_NODE 4,.bmode_he
    BMODE_NODE 5,.bmode_rd
    mov eax,VP8_BMODE_VR
    EPILOGUE_RESTORE rbx,r12
.bmode_rd:
    mov eax,VP8_BMODE_RD
    EPILOGUE_RESTORE rbx,r12
.bmode_he:
    mov eax,VP8_BMODE_HE
    EPILOGUE_RESTORE rbx,r12
.bmode_ve:
    mov eax,VP8_BMODE_VE
    EPILOGUE_RESTORE rbx,r12
.bmode_tm:
    mov eax,VP8_BMODE_TM
    EPILOGUE_RESTORE rbx,r12
.bmode_dc:
    mov eax,VP8_BMODE_DC
    EPILOGUE_RESTORE rbx,r12
.bmode_bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12

; WebPBoolReader*,above_modes[4],left_modes[4],output_modes[16] -> 0/-EINVAL.
global webp_vp8_decode_bpred_modes
webp_vp8_decode_bpred_modes:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    test rbx,rbx
    jz .bpred_bad
    test r12,r12
    jz .bpred_bad
    test r13,r13
    jz .bpred_bad
    test r14,r14
    jz .bpred_bad
    xor r15d,r15d
.bpred_next:
    mov eax,r15d
    and eax,3
    mov [rsp],eax                     ; column
    mov eax,r15d
    shr eax,2
    mov [rsp+4],eax                   ; row
    test eax,eax
    jz .bpred_external_above
    mov eax,r15d
    sub eax,4
    movzx r8d,byte [r14+rax]
    jmp .bpred_above_ready
.bpred_external_above:
    mov eax,[rsp]
    movzx r8d,byte [r12+rax]
.bpred_above_ready:
    cmp r8d,9
    ja .bpred_bad
    cmp dword [rsp],0
    je .bpred_external_left
    mov eax,r15d
    dec eax
    movzx r9d,byte [r14+rax]
    jmp .bpred_left_ready
.bpred_external_left:
    mov eax,[rsp+4]
    movzx r9d,byte [r13+rax]
.bpred_left_ready:
    cmp r9d,9
    ja .bpred_bad
    imul r8d,90
    imul r9d,9
    add r8d,r9d
    lea rsi,[rel vp8_kf_bmode_probs]
    add rsi,r8
    mov rdi,rbx
    call webp_vp8_decode_bmode
    test eax,eax
    js .bpred_bad
    mov [r14+r15],al
    inc r15d
    cmp r15d,16
    jb .bpred_next
    xor eax,eax
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.bpred_bad:
    mov rax,-EINVAL
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

; reader,config,skip_enabled,skip_probability,above[4],left[4],header*.
global webp_vp8_decode_mb_header
webp_vp8_decode_mb_header:
    mov rax,[rsp+8]
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    mov r12,rsi
    mov r13,r8
    mov r14,r9
    mov r15,rax
    mov [rsp],edx
    mov [rsp+4],ecx
    test rbx,rbx
    jz .mbh_bad
    test r12,r12
    jz .mbh_bad
    test r15,r15
    jz .mbh_bad
    mov rdi,r15
    xor eax,eax
    mov ecx,WebPVP8MBHeader_size/8
    rep stosq
    cmp dword [r12+WebPVP8Config.segmentation],0
    je .mbh_skip
    cmp dword [r12+WebPVP8Config.segment_map_update],0
    je .mbh_skip
    mov rdi,rbx
    movzx esi,byte [r12+WebPVP8Config.segment_probs]
    call webp_bool_get
    test eax,eax
    js .mbh_bad
    test eax,eax
    jnz .mbh_segment_high
    mov rdi,rbx
    movzx esi,byte [r12+WebPVP8Config.segment_probs+1]
    call webp_bool_get
    test eax,eax
    js .mbh_bad
    mov [r15+WebPVP8MBHeader.segment_id],eax
    jmp .mbh_skip
.mbh_segment_high:
    mov rdi,rbx
    movzx esi,byte [r12+WebPVP8Config.segment_probs+2]
    call webp_bool_get
    test eax,eax
    js .mbh_bad
    add eax,2
    mov [r15+WebPVP8MBHeader.segment_id],eax
.mbh_skip:
    cmp dword [rsp],0
    jz .mbh_modes
    mov ecx,[rsp+4]
    cmp ecx,1
    jb .mbh_bad
    cmp ecx,255
    ja .mbh_bad
    mov rdi,rbx
    mov esi,ecx
    call webp_bool_get
    test eax,eax
    js .mbh_bad
    mov [r15+WebPVP8MBHeader.skip_coeff],eax
.mbh_modes:
    mov rdi,rbx
    lea rsi,[r15+WebPVP8MBHeader.y_mode]
    call webp_vp8_decode_keyframe_base_modes
    test eax,eax
    js .mbh_bad
    cmp dword [r15+WebPVP8MBHeader.y_mode],VP8_Y_MODE_B_PRED
    jne .mbh_ok
    test r13,r13
    jz .mbh_bad
    test r14,r14
    jz .mbh_bad
    mov rdi,rbx
    mov rsi,r13
    mov rdx,r14
    lea rcx,[r15+WebPVP8MBHeader.b_modes]
    call webp_vp8_decode_bpred_modes
    test eax,eax
    js .mbh_bad
.mbh_ok:
    xor eax,eax
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.mbh_bad:
    mov rax,-EINVAL
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

; WebPVP8ResidualState* -> 0/-EINVAL.
global webp_vp8_decode_macroblock_residual
webp_vp8_decode_macroblock_residual:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    test rbx,rbx
    jz .residual_bad
    mov rax,[rbx+WebPVP8ResidualState.reader]
    test rax,rax
    jz .residual_bad
    mov rax,[rbx+WebPVP8ResidualState.probs]
    test rax,rax
    jz .residual_bad
    mov rax,[rbx+WebPVP8ResidualState.coeffs]
    test rax,rax
    jz .residual_bad
    mov rax,[rbx+WebPVP8ResidualState.above]
    test rax,rax
    jz .residual_bad
    mov rax,[rbx+WebPVP8ResidualState.left]
    test rax,rax
    jz .residual_bad
    cmp dword [rbx+WebPVP8ResidualState.y_mode],VP8_Y_MODE_B_PRED
    ja .residual_bad
    mov rdi,[rbx+WebPVP8ResidualState.coeffs]
    xor eax,eax
    mov ecx,100                       ; 25 blocks * 16 words
    rep stosq
    cmp dword [rbx+WebPVP8ResidualState.y_mode],VP8_Y_MODE_B_PRED
    je .residual_bpred
    mov r14d,24                       ; Y2
    mov dword [rsp],1
    mov dword [rsp+4],0
    call .decode_one
    test eax,eax
    js .residual_bad
    xor r14d,r14d                     ; Y1 without DC
    mov r15d,16
    mov dword [rsp],0
    mov dword [rsp+4],1
    jmp .residual_range
.residual_bpred:
    xor r14d,r14d                     ; independently predicted Y1
    mov r15d,16
    mov dword [rsp],3
    mov dword [rsp+4],0
.residual_range:
    call .decode_one
    test eax,eax
    js .residual_bad
    inc r14d
    cmp r14d,r15d
    jb .residual_range
    mov r14d,16                       ; U and V
    mov r15d,24
    mov dword [rsp],2
    mov dword [rsp+4],0
.residual_uv:
    call .decode_one
    test eax,eax
    js .residual_bad
    inc r14d
    cmp r14d,r15d
    jb .residual_uv
    xor eax,eax
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.residual_bad:
    mov rax,-EINVAL
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

; Decode block r14d using type/start stored in the caller's local frame.
.decode_one:
    mov rdi,[rbx+WebPVP8ResidualState.reader]
    mov eax,[rsp+8]                   ; caller [rsp], adjusted by return address
    imul eax,264
    add rax,[rbx+WebPVP8ResidualState.probs]
    mov rsi,rax
    mov rdx,r14
    shl rdx,5
    add rdx,[rbx+WebPVP8ResidualState.coeffs]
    mov ecx,[rsp+12]
    lea r10,[rel vp8_residual_above_index]
    movzx r12d,byte [r10+r14]
    lea r10,[rel vp8_residual_left_index]
    movzx r13d,byte [r10+r14]
    mov rax,[rbx+WebPVP8ResidualState.above]
    movzx r8d,byte [rax+r12]
    mov rax,[rbx+WebPVP8ResidualState.left]
    movzx eax,byte [rax+r13]
    add r8d,eax
    call webp_vp8_decode_block
    test eax,eax
    js .decode_return
    mov rdx,r14
    shl rdx,5
    add rdx,[rbx+WebPVP8ResidualState.coeffs]
    xor r10d,r10d
    xor ecx,ecx
.nonzero_scan:
    cmp word [rdx+rcx*2],0
    je .nonzero_next
    mov r10d,1
    jmp .nonzero_store
.nonzero_next:
    inc ecx
    cmp ecx,16
    jb .nonzero_scan
.nonzero_store:
    mov rax,[rbx+WebPVP8ResidualState.above]
    mov [rax+r12],r10b
    mov rax,[rbx+WebPVP8ResidualState.left]
    mov [rax+r13],r10b
    xor eax,eax
.decode_return:
    ret

section .rodata
vp8_residual_left_index:
    db 0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,5,5,6,6,7,7,8
vp8_residual_above_index:
    db 0,1,2,3,0,1,2,3,0,1,2,3,0,1,2,3,4,5,4,5,6,7,6,7,8

; RFC 6386 keyframe 4x4 mode probabilities, flattened [10][10][9].
vp8_kf_bmode_probs:
    db 231,120,48,89,115,113,120,152,112
    db 152,179,64,126,170,118,46,70,95
    db 175,69,143,80,85,82,72,155,103
    db 56,58,10,171,218,189,17,13,152
    db 144,71,10,38,171,213,144,34,26
    db 114,26,17,163,44,195,21,10,173
    db 121,24,80,195,26,62,44,64,85
    db 170,46,55,19,136,160,33,206,71
    db 63,20,8,114,114,208,12,9,226
    db 81,40,11,96,182,84,29,16,36
    db 134,183,89,137,98,101,106,165,148
    db 72,187,100,130,157,111,32,75,80
    db 66,102,167,99,74,62,40,234,128
    db 41,53,9,178,241,141,26,8,107
    db 104,79,12,27,217,255,87,17,7
    db 74,43,26,146,73,166,49,23,157
    db 65,38,105,160,51,52,31,115,128
    db 87,68,71,44,114,51,15,186,23
    db 47,41,14,110,182,183,21,17,194
    db 66,45,25,102,197,189,23,18,22
    db 88,88,147,150,42,46,45,196,205
    db 43,97,183,117,85,38,35,179,61
    db 39,53,200,87,26,21,43,232,171
    db 56,34,51,104,114,102,29,93,77
    db 107,54,32,26,51,1,81,43,31
    db 39,28,85,171,58,165,90,98,64
    db 34,22,116,206,23,34,43,166,73
    db 68,25,106,22,64,171,36,225,114
    db 34,19,21,102,132,188,16,76,124
    db 62,18,78,95,85,57,50,48,51
    db 193,101,35,159,215,111,89,46,111
    db 60,148,31,172,219,228,21,18,111
    db 112,113,77,85,179,255,38,120,114
    db 40,42,1,196,245,209,10,25,109
    db 100,80,8,43,154,1,51,26,71
    db 88,43,29,140,166,213,37,43,154
    db 61,63,30,155,67,45,68,1,209
    db 142,78,78,16,255,128,34,197,171
    db 41,40,5,102,211,183,4,1,221
    db 51,50,17,168,209,192,23,25,82
    db 125,98,42,88,104,85,117,175,82
    db 95,84,53,89,128,100,113,101,45
    db 75,79,123,47,51,128,81,171,1
    db 57,17,5,71,102,57,53,41,49
    db 115,21,2,10,102,255,166,23,6
    db 38,33,13,121,57,73,26,1,85
    db 41,10,67,138,77,110,90,47,114
    db 101,29,16,10,85,128,101,196,26
    db 57,18,10,102,102,213,34,20,43
    db 117,20,15,36,163,128,68,1,26
    db 138,31,36,171,27,166,38,44,229
    db 67,87,58,169,82,115,26,59,179
    db 63,59,90,180,59,166,93,73,154
    db 40,40,21,116,143,209,34,39,175
    db 57,46,22,24,128,1,54,17,37
    db 47,15,16,183,34,223,49,45,183
    db 46,17,33,183,6,98,15,32,183
    db 65,32,73,115,28,128,23,128,205
    db 40,3,9,115,51,192,18,6,223
    db 87,37,9,115,59,77,64,21,47
    db 104,55,44,218,9,54,53,130,226
    db 64,90,70,205,40,41,23,26,57
    db 54,57,112,184,5,41,38,166,213
    db 30,34,26,133,152,116,10,32,134
    db 75,32,12,51,192,255,160,43,51
    db 39,19,53,221,26,114,32,73,255
    db 31,9,65,234,2,15,1,118,73
    db 88,31,35,67,102,85,55,186,85
    db 56,21,23,111,59,205,45,37,192
    db 55,38,70,124,73,102,1,34,98
    db 102,61,71,37,34,53,31,243,192
    db 69,60,71,38,73,119,28,222,37
    db 68,45,128,34,1,47,11,245,171
    db 62,17,19,70,146,85,55,62,70
    db 75,15,9,9,64,255,184,119,16
    db 37,43,37,154,100,163,85,160,1
    db 63,9,92,136,28,64,32,201,85
    db 86,6,28,5,64,255,25,248,1
    db 56,8,17,132,137,255,55,116,128
    db 58,15,20,82,135,57,26,121,40
    db 164,50,31,137,154,133,25,35,218
    db 51,103,44,131,131,123,31,6,158
    db 86,40,64,135,148,224,45,183,128
    db 22,26,17,131,240,154,14,1,209
    db 83,12,13,54,192,255,68,47,28
    db 45,16,21,91,64,222,7,1,197
    db 56,21,39,155,60,138,23,102,213
    db 85,26,85,85,128,128,32,146,171
    db 18,11,7,63,144,171,4,4,246
    db 35,27,10,146,174,171,12,26,128
    db 190,80,35,99,180,80,126,54,45
    db 85,126,47,87,176,51,41,20,32
    db 101,75,128,139,118,146,116,128,85
    db 56,41,15,176,236,85,37,9,62
    db 146,36,19,30,171,255,97,27,20
    db 71,30,17,119,118,255,17,18,138
    db 101,38,60,138,55,70,43,26,142
    db 138,45,61,62,219,1,81,188,64
    db 32,41,20,117,151,142,20,21,163
    db 112,19,12,61,195,128,48,4,24
