; RFC 6386 VP8 scalar loop-filter primitives.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text

; Clamp eax to signed 8-bit.
vp8_sat_s8:
    cmp eax,-128
    jge .s8_high
    mov eax,-128
    ret
.s8_high:
    cmp eax,127
    jle .s8_done
    mov eax,127
.s8_done:
    ret

; Clamp eax to unsigned 8-bit.
vp8_sat_u8:
    test eax,eax
    jns .u8_high
    xor eax,eax
    ret
.u8_high:
    cmp eax,255
    jle .u8_done
    mov eax,255
.u8_done:
    ret

; q0,step,edge_limit,interior_limit,hev_threshold,kind -> changed/-EINVAL.
; kind: 0 simple, 1 normal subblock edge, 2 normal macroblock edge.
global webp_vp8_filter_sample
webp_vp8_filter_sample:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,48
    mov rbx,rdi
    mov r12d,esi
    mov r13d,edx
    mov r14d,ecx
    mov r15d,r8d
    test rbx,rbx
    jz .bad
    test r12d,r12d
    jz .bad
    cmp r9d,2
    ja .bad
    mov [rsp+32],r9d
    movsxd r10,r12d
    mov r11,r10
    neg r11
    movzx eax,byte [rbx+r11]
    mov [rsp],eax                     ; p0
    lea r11,[r11+r11]
    movzx eax,byte [rbx+r11]
    mov [rsp+4],eax                   ; p1
    sub r11,r10
    movzx eax,byte [rbx+r11]
    mov [rsp+8],eax                   ; p2
    sub r11,r10
    movzx eax,byte [rbx+r11]
    mov [rsp+12],eax                  ; p3
    movzx eax,byte [rbx]
    mov [rsp+16],eax                  ; q0
    movzx eax,byte [rbx+r10]
    mov [rsp+20],eax                  ; q1
    lea r11,[r10+r10]
    movzx eax,byte [rbx+r11]
    mov [rsp+24],eax                  ; q2
    add r11,r10
    movzx eax,byte [rbx+r11]
    mov [rsp+28],eax                  ; q3
    mov eax,[rsp]
    sub eax,[rsp+16]
    cdq
    xor eax,edx
    sub eax,edx
    shl eax,1
    mov ecx,[rsp+4]
    sub ecx,[rsp+20]
    mov edx,ecx
    sar edx,31
    xor ecx,edx
    sub ecx,edx
    shr ecx,1
    add eax,ecx
    cmp dword [rsp+32],0
    jne .normal_threshold
    cmp eax,r13d
    ja .unchanged
    mov dword [rsp+36],1              ; outer taps
    jmp .common
.normal_threshold:
    lea ecx,[r13*2]
    add ecx,r14d
    cmp eax,ecx
    ja .unchanged
    mov ecx,[rsp+12]
    sub ecx,[rsp+8]
    call .abs_ecx
    cmp ecx,r14d
    ja .unchanged
    mov ecx,[rsp+8]
    sub ecx,[rsp+4]
    call .abs_ecx
    cmp ecx,r14d
    ja .unchanged
    mov ecx,[rsp+4]
    sub ecx,[rsp]
    call .abs_ecx
    cmp ecx,r14d
    ja .unchanged
    mov ecx,[rsp+28]
    sub ecx,[rsp+24]
    call .abs_ecx
    cmp ecx,r14d
    ja .unchanged
    mov ecx,[rsp+24]
    sub ecx,[rsp+20]
    call .abs_ecx
    cmp ecx,r14d
    ja .unchanged
    mov ecx,[rsp+20]
    sub ecx,[rsp+16]
    call .abs_ecx
    cmp ecx,r14d
    ja .unchanged
    mov eax,[rsp+4]
    sub eax,[rsp]
    cdq
    xor eax,edx
    sub eax,edx
    cmp eax,r15d
    ja .hev
    mov eax,[rsp+20]
    sub eax,[rsp+16]
    cdq
    xor eax,edx
    sub eax,edx
    cmp eax,r15d
    ja .hev
    mov dword [rsp+36],0
    cmp dword [rsp+32],2
    je .macro_filter
    jmp .common
.hev:
    mov dword [rsp+36],1
.common:
    mov eax,[rsp+16]
    sub eax,[rsp]
    lea eax,[rax+rax*2]
    cmp dword [rsp+36],0
    je .common_sat
    mov ecx,[rsp+4]
    sub ecx,[rsp+20]
    push rax
    mov eax,ecx
    call vp8_sat_s8
    mov ecx,eax
    pop rax
    add eax,ecx
.common_sat:
    call vp8_sat_s8
    mov edx,eax
    add eax,4
    cmp eax,127
    jle .f1_ready
    mov eax,127
.f1_ready:
    sar eax,3
    mov [rsp+40],eax                  ; f1
    mov eax,edx
    add eax,3
    cmp eax,127
    jle .f2_ready
    mov eax,127
.f2_ready:
    sar eax,3
    mov ecx,eax                       ; f2
    add eax,[rsp]
    call vp8_sat_u8
    movsxd r10,r12d
    neg r10
    mov [rbx+r10],al
    mov eax,[rsp+16]
    sub eax,[rsp+40]
    call vp8_sat_u8
    mov [rbx],al
    cmp dword [rsp+36],0
    jne .changed
    mov eax,[rsp+40]
    inc eax
    sar eax,1
    mov ecx,eax
    add eax,[rsp+4]
    call vp8_sat_u8
    movsxd r10,r12d
    neg r10
    add r10,r10
    mov [rbx+r10],al
    mov eax,[rsp+20]
    sub eax,ecx
    call vp8_sat_u8
    movsxd r10,r12d
    mov [rbx+r10],al
    jmp .changed
.macro_filter:
    mov eax,[rsp+4]
    sub eax,[rsp+20]
    call vp8_sat_s8
    mov ecx,[rsp+16]
    sub ecx,[rsp]
    lea ecx,[rcx+rcx*2]
    add eax,ecx
    call vp8_sat_s8
    mov [rsp+40],eax                  ; w
    imul eax,27
    add eax,63
    sar eax,7
    mov ecx,eax
    add eax,[rsp]
    call vp8_sat_u8
    movsxd r10,r12d
    neg r10
    mov [rbx+r10],al
    mov eax,[rsp+16]
    sub eax,ecx
    call vp8_sat_u8
    mov [rbx],al
    mov eax,[rsp+40]
    imul eax,18
    add eax,63
    sar eax,7
    mov ecx,eax
    add eax,[rsp+4]
    call vp8_sat_u8
    movsxd r10,r12d
    neg r10
    add r10,r10
    mov [rbx+r10],al
    mov eax,[rsp+20]
    sub eax,ecx
    call vp8_sat_u8
    movsxd r10,r12d
    mov [rbx+r10],al
    mov eax,[rsp+40]
    imul eax,9
    add eax,63
    sar eax,7
    mov ecx,eax
    add eax,[rsp+8]
    call vp8_sat_u8
    movsxd r10,r12d
    imul r10,-3
    mov [rbx+r10],al
    mov eax,[rsp+24]
    sub eax,ecx
    call vp8_sat_u8
    movsxd r10,r12d
    add r10,r10
    mov [rbx+r10],al
.changed:
    mov eax,1
    add rsp,48
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.unchanged:
    xor eax,eax
    add rsp,48
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.bad:
    mov rax,-EINVAL
    add rsp,48
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.abs_ecx:
    mov eax,ecx
    sar eax,31
    xor ecx,eax
    sub ecx,eax
    ret

; q0,step,advance,count,edge_limit,interior_limit,hev,kind -> changed count.
global webp_vp8_filter_edge
webp_vp8_filter_edge:
    mov r10d,[rsp+8]
    mov r11d,[rsp+16]
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    mov r12d,esi
    mov r13d,edx
    mov r14d,ecx
    mov r15d,r8d
    mov [rsp],r9d
    mov [rsp+4],r10d
    mov [rsp+8],r11d
    mov dword [rsp+12],0
    test rbx,rbx
    jz .edge_bad
    test r12d,r12d
    jz .edge_bad
    test r13d,r13d
    jz .edge_bad
    test r14d,r14d
    jz .edge_bad
    cmp dword [rsp+8],2
    ja .edge_bad
.edge_next:
    mov rdi,rbx
    mov esi,r12d
    mov edx,r15d
    mov ecx,[rsp]
    mov r8d,[rsp+4]
    mov r9d,[rsp+8]
    call webp_vp8_filter_sample
    test eax,eax
    js .edge_bad
    add [rsp+12],eax
    add rbx,r13
    dec r14d
    jnz .edge_next
    mov eax,[rsp+12]
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.edge_bad:
    mov rax,-EINVAL
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

%macro VP8_EDGE 8
    mov rdi,%1
    mov esi,%2
    mov edx,%3
    mov ecx,%4
    mov r8d,%5
    mov r9d,%6
    mov eax,%7
    push qword %8
    push rax
    call webp_vp8_filter_edge
    add rsp,16
    test eax,eax
    js .frame_bad
%endmacro

; WebPVP8FilterFrameState* -> 0/-EINVAL.
global webp_vp8_filter_frame
webp_vp8_filter_frame:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,48
    mov rbx,rdi
    test rbx,rbx
    jz .frame_bad
    cmp qword [rbx+WebPVP8FilterFrameState.y],0
    je .frame_bad
    cmp qword [rbx+WebPVP8FilterFrameState.u],0
    je .frame_bad
    cmp qword [rbx+WebPVP8FilterFrameState.v],0
    je .frame_bad
    cmp qword [rbx+WebPVP8FilterFrameState.config],0
    je .frame_bad
    cmp qword [rbx+WebPVP8FilterFrameState.meta],0
    je .frame_bad
    cmp dword [rbx+WebPVP8FilterFrameState.mb_cols],0
    je .frame_bad
    cmp dword [rbx+WebPVP8FilterFrameState.mb_rows],0
    je .frame_bad
    xor r12d,r12d
.frame_row:
    xor r13d,r13d
.frame_col:
    mov eax,r12d
    imul eax,[rbx+WebPVP8FilterFrameState.mb_cols]
    add eax,r13d
    shl eax,2
    mov rdx,[rbx+WebPVP8FilterFrameState.meta]
    add rdx,rax
    mov [rsp+24],rdx
    mov rcx,[rbx+WebPVP8FilterFrameState.config]
    mov eax,[rcx+WebPVP8Config.filter_level]
    cmp dword [rcx+WebPVP8Config.segmentation],0
    je .level_delta
    movzx edx,byte [rdx]
    mov edx,[rcx+WebPVP8Config.segment_filter+rdx*4]
    cmp dword [rcx+WebPVP8Config.segment_absolute],0
    jne .level_segment_absolute
    add eax,edx
    jmp .level_delta
.level_segment_absolute:
    mov eax,edx
.level_delta:
    cmp dword [rcx+WebPVP8Config.lf_adjustments],0
    je .level_clamp
    add eax,[rcx+WebPVP8Config.ref_lf_deltas]
    mov rdx,[rsp+24]
    cmp byte [rdx+1],VP8_Y_MODE_B_PRED
    jne .level_clamp
    add eax,[rcx+WebPVP8Config.mode_lf_deltas]
.level_clamp:
    test eax,eax
    jns .level_high
    xor eax,eax
.level_high:
    cmp eax,63
    jle .level_ready
    mov eax,63
.level_ready:
    mov [rsp],eax
    test eax,eax
    jz .frame_next
    mov edx,eax
    mov ecx,[rcx+WebPVP8Config.sharpness]
    test ecx,ecx
    jz .interior_floor
    cmp ecx,4
    ja .sharp_shift2
    shr edx,1
    jmp .sharp_cap
.sharp_shift2:
    shr edx,2
.sharp_cap:
    mov eax,9
    sub eax,ecx
    cmp edx,eax
    cmova edx,eax
.interior_floor:
    test edx,edx
    jnz .interior_ready
    mov edx,1
.interior_ready:
    mov [rsp+4],edx
    xor eax,eax
    cmp dword [rsp],15
    setae al
    cmp dword [rsp],40
    setae dl
    movzx edx,dl
    add eax,edx
    mov [rsp+8],eax
    mov rdx,[rsp+24]
    movzx eax,byte [rdx+2]
    cmp byte [rdx+1],VP8_Y_MODE_B_PRED
    sete dl
    movzx edx,dl
    or eax,edx
    mov [rsp+12],eax
    mov eax,r12d
    shl eax,4
    imul eax,[rbx+WebPVP8FilterFrameState.y_stride]
    mov edx,r13d
    shl edx,4
    add eax,edx
    mov r14,[rbx+WebPVP8FilterFrameState.y]
    add r14,rax
    mov eax,r12d
    shl eax,3
    imul eax,[rbx+WebPVP8FilterFrameState.uv_stride]
    mov edx,r13d
    shl edx,3
    add eax,edx
    mov r15,[rbx+WebPVP8FilterFrameState.u]
    add r15,rax
    mov rdx,[rbx+WebPVP8FilterFrameState.v]
    add rdx,rax
    mov [rsp+32],rdx
    mov rcx,[rbx+WebPVP8FilterFrameState.config]
    cmp dword [rcx+WebPVP8Config.filter_type],0
    je .normal
    mov eax,[rsp]
    lea r8d,[rax*2]
    add r8d,[rsp+4]
    mov [rsp+16],r8d
    test r13d,r13d
    jz .simple_internal_v
    add r8d,4
    VP8_EDGE r14,1,[rbx+WebPVP8FilterFrameState.y_stride],16,[rsp+16],0,0,0
.simple_internal_v:
    cmp dword [rsp+12],0
    je .simple_h
    mov eax,[rsp]
    lea r8d,[rax*2]
    add r8d,[rsp+4]
    mov [rsp+16],r8d
    lea rdi,[r14+4]
    VP8_EDGE rdi,1,[rbx+WebPVP8FilterFrameState.y_stride],16,[rsp+16],0,0,0
    lea rdi,[r14+8]
    VP8_EDGE rdi,1,[rbx+WebPVP8FilterFrameState.y_stride],16,[rsp+16],0,0,0
    lea rdi,[r14+12]
    VP8_EDGE rdi,1,[rbx+WebPVP8FilterFrameState.y_stride],16,[rsp+16],0,0,0
.simple_h:
    test r12d,r12d
    jz .simple_internal_h
    mov eax,[rsp]
    lea r8d,[rax*2+4]
    add r8d,[rsp+4]
    mov [rsp+16],r8d
    VP8_EDGE r14,[rbx+WebPVP8FilterFrameState.y_stride],1,16,[rsp+16],0,0,0
.simple_internal_h:
    cmp dword [rsp+12],0
    je .frame_next
    mov eax,[rsp]
    lea r8d,[rax*2]
    add r8d,[rsp+4]
    mov [rsp+16],r8d
    mov eax,[rbx+WebPVP8FilterFrameState.y_stride]
    lea rdi,[r14+rax*4]
    VP8_EDGE rdi,[rbx+WebPVP8FilterFrameState.y_stride],1,16,[rsp+16],0,0,0
    lea rdi,[r14+rax*8]
    VP8_EDGE rdi,[rbx+WebPVP8FilterFrameState.y_stride],1,16,[rsp+16],0,0,0
    lea rdi,[r14+rax*8]
    lea rdi,[rdi+rax*4]
    VP8_EDGE rdi,[rbx+WebPVP8FilterFrameState.y_stride],1,16,[rsp+16],0,0,0
    jmp .frame_next
.normal:
    test r13d,r13d
    jz .normal_internal_v
    mov r8d,[rsp]
    add r8d,2
    mov [rsp+16],r8d
    VP8_EDGE r14,1,[rbx+WebPVP8FilterFrameState.y_stride],16,[rsp+16],[rsp+4],[rsp+8],2
    VP8_EDGE r15,1,[rbx+WebPVP8FilterFrameState.uv_stride],8,[rsp+16],[rsp+4],[rsp+8],2
    mov rdi,[rsp+32]
    VP8_EDGE rdi,1,[rbx+WebPVP8FilterFrameState.uv_stride],8,[rsp+16],[rsp+4],[rsp+8],2
.normal_internal_v:
    cmp dword [rsp+12],0
    je .normal_h
    mov r8d,[rsp]
    mov [rsp+16],r8d
    lea rdi,[r14+4]
    VP8_EDGE rdi,1,[rbx+WebPVP8FilterFrameState.y_stride],16,[rsp+16],[rsp+4],[rsp+8],1
    lea rdi,[r14+8]
    VP8_EDGE rdi,1,[rbx+WebPVP8FilterFrameState.y_stride],16,[rsp+16],[rsp+4],[rsp+8],1
    lea rdi,[r14+12]
    VP8_EDGE rdi,1,[rbx+WebPVP8FilterFrameState.y_stride],16,[rsp+16],[rsp+4],[rsp+8],1
    lea rdi,[r15+4]
    VP8_EDGE rdi,1,[rbx+WebPVP8FilterFrameState.uv_stride],8,[rsp+16],[rsp+4],[rsp+8],1
    mov rdi,[rsp+32]
    add rdi,4
    VP8_EDGE rdi,1,[rbx+WebPVP8FilterFrameState.uv_stride],8,[rsp+16],[rsp+4],[rsp+8],1
.normal_h:
    test r12d,r12d
    jz .normal_internal_h
    mov r8d,[rsp]
    add r8d,2
    mov [rsp+16],r8d
    VP8_EDGE r14,[rbx+WebPVP8FilterFrameState.y_stride],1,16,[rsp+16],[rsp+4],[rsp+8],2
    VP8_EDGE r15,[rbx+WebPVP8FilterFrameState.uv_stride],1,8,[rsp+16],[rsp+4],[rsp+8],2
    mov rdi,[rsp+32]
    VP8_EDGE rdi,[rbx+WebPVP8FilterFrameState.uv_stride],1,8,[rsp+16],[rsp+4],[rsp+8],2
.normal_internal_h:
    cmp dword [rsp+12],0
    je .frame_next
    mov r8d,[rsp]
    mov [rsp+16],r8d
    mov eax,[rbx+WebPVP8FilterFrameState.y_stride]
    lea rdi,[r14+rax*4]
    VP8_EDGE rdi,[rbx+WebPVP8FilterFrameState.y_stride],1,16,[rsp+16],[rsp+4],[rsp+8],1
    lea rdi,[r14+rax*8]
    VP8_EDGE rdi,[rbx+WebPVP8FilterFrameState.y_stride],1,16,[rsp+16],[rsp+4],[rsp+8],1
    lea rdi,[r14+rax*8]
    lea rdi,[rdi+rax*4]
    VP8_EDGE rdi,[rbx+WebPVP8FilterFrameState.y_stride],1,16,[rsp+16],[rsp+4],[rsp+8],1
    mov eax,[rbx+WebPVP8FilterFrameState.uv_stride]
    lea rdi,[r15+rax*4]
    VP8_EDGE rdi,[rbx+WebPVP8FilterFrameState.uv_stride],1,8,[rsp+16],[rsp+4],[rsp+8],1
    mov rdi,[rsp+32]
    lea rdi,[rdi+rax*4]
    VP8_EDGE rdi,[rbx+WebPVP8FilterFrameState.uv_stride],1,8,[rsp+16],[rsp+4],[rsp+8],1
.frame_next:
    inc r13d
    cmp r13d,[rbx+WebPVP8FilterFrameState.mb_cols]
    jb .frame_col
    inc r12d
    cmp r12d,[rbx+WebPVP8FilterFrameState.mb_rows]
    jb .frame_row
    xor eax,eax
    add rsp,48
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.frame_bad:
    mov rax,-EINVAL
    add rsp,48
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

section .data
global webp_vp8_filter_version
webp_vp8_filter_version: dq 0x010000
