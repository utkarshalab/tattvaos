; VP8 lossy frame validation and boolean arithmetic decoder.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text

; reader,data,len -> 0/-EINVAL.
global webp_bool_init
webp_bool_init:
    test rdi,rdi
    jz .init_bad
    test rsi,rsi
    jz .init_bad
    cmp rdx,2
    jb .init_bad
    lea rcx,[rsi+2]
    mov [rdi+WebPBoolReader.cursor],rcx
    add rsi,rdx
    jc .init_bad
    mov [rdi+WebPBoolReader.end],rsi
    mov dword [rdi+WebPBoolReader.range],255
    movzx eax,byte [rcx-2]
    shl eax,8
    movzx edx,byte [rcx-1]
    or eax,edx
    mov [rdi+WebPBoolReader.value],eax
    mov dword [rdi+WebPBoolReader.count],0
    mov dword [rdi+WebPBoolReader.error],0
    xor eax,eax
    ret
.init_bad:
    mov rax,-EINVAL
    ret

; reader,probability-of-zero(0..255) -> bit or -EINVAL.
global webp_bool_get
webp_bool_get:
    test rdi,rdi
    jz .get_bad
    cmp esi,255
    ja .get_bad
    cmp dword [rdi+WebPBoolReader.error],8
    ja .get_bad
    mov r8d,[rdi+WebPBoolReader.range]
    lea eax,[r8-1]
    imul eax,esi
    shr eax,8
    inc eax                            ; split
    mov edx,eax
    shl edx,8                          ; scaled split
    mov ecx,[rdi+WebPBoolReader.value]
    xor r9d,r9d
    cmp ecx,edx
    jb .selected
    mov r9d,1
    sub ecx,edx
    sub r8d,eax
    jmp .normalize
.selected:
    mov r8d,eax
.normalize:
    cmp r8d,128
    jae .store
    shl r8d,1
    shl ecx,1
    inc dword [rdi+WebPBoolReader.count]
    cmp dword [rdi+WebPBoolReader.count],8
    jb .normalize
    mov rax,[rdi+WebPBoolReader.cursor]
    cmp rax,[rdi+WebPBoolReader.end]
    jae .get_padding
    movzx edx,byte [rax]
    or ecx,edx
    inc rax
    mov [rdi+WebPBoolReader.cursor],rax
    mov dword [rdi+WebPBoolReader.count],0
    jmp .normalize
.get_padding:
    inc dword [rdi+WebPBoolReader.error]
    cmp dword [rdi+WebPBoolReader.error],8
    ja .get_exhausted
    mov dword [rdi+WebPBoolReader.count],0
    jmp .normalize
.store:
    mov [rdi+WebPBoolReader.range],r8d
    mov [rdi+WebPBoolReader.value],ecx
    mov eax,r9d
    ret
.get_exhausted:
    mov dword [rdi+WebPBoolReader.error],9
.get_bad:
    mov rax,-EINVAL
    ret

; reader,bit_count(0..32) -> unsigned literal or -EINVAL.
global webp_bool_literal
webp_bool_literal:
    PROLOGUE_SAVE rbx,r12,r13
    mov rbx,rdi
    mov r12d,esi
    cmp r12d,32
    ja .literal_bad
    xor r13d,r13d
.literal_next:
    test r12d,r12d
    jz .literal_done
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .literal_bad
    shl r13d,1
    or r13d,eax
    dec r12d
    jmp .literal_next
.literal_done:
    mov eax,r13d
    EPILOGUE_RESTORE rbx,r12,r13
.literal_bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13

; reader,bit_count -> signed magnitude or -EINVAL.
vp8_signed_literal:
    PROLOGUE_SAVE rbx,r12
    mov rbx,rdi
    mov r12d,esi
    call webp_bool_literal
    test rax,rax
    js .signed_bad
    push rax
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    mov edx,eax
    pop rax
    test edx,edx
    js .signed_bad
    test edx,edx
    jz .signed_done
    neg eax
.signed_done:
    EPILOGUE_RESTORE rbx,r12
.signed_bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12

; bool reader,WebPVP8Config* -> 0/-EINVAL. Parses key-frame control fields
; through refresh_entropy_probs; coefficient updates follow this structure.
global webp_vp8_parse_config
webp_vp8_parse_config:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    mov r12,rsi
    test rbx,rbx
    jz .config_bad
    test r12,r12
    jz .config_bad
    mov rdi,r12
    xor eax,eax
    mov ecx,WebPVP8Config_size/8
    rep stosq
    mov byte [r12+WebPVP8Config.segment_probs],255
    mov byte [r12+WebPVP8Config.segment_probs+1],255
    mov byte [r12+WebPVP8Config.segment_probs+2],255
    mov byte [r12+WebPVP8Config.segment_probs+3],255
    mov dword [r12+WebPVP8Config.ref_lf_deltas],2
    mov dword [r12+WebPVP8Config.ref_lf_deltas+8],-2
    mov dword [r12+WebPVP8Config.ref_lf_deltas+12],-2
    mov dword [r12+WebPVP8Config.mode_lf_deltas],4
    mov dword [r12+WebPVP8Config.mode_lf_deltas+4],-2
    mov dword [r12+WebPVP8Config.mode_lf_deltas+8],2
    mov dword [r12+WebPVP8Config.mode_lf_deltas+12],4
    mov rdi,rbx
    mov esi,128
    call webp_bool_get                  ; color space
    test rax,rax
    js .config_bad
    test eax,eax                        ; value 1 is reserved
    jnz .config_bad
    mov [r12+WebPVP8Config.color_space],eax
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.clamping],eax
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.segmentation],eax
    test eax,eax
    jz .filter_header
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.segment_map_update],eax
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.segment_data_update],eax
    test eax,eax
    jz .segment_map
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.segment_absolute],eax
    xor r13d,r13d                      ; feature: quant, filter
.segment_feature:
    xor r14d,r14d
.segment_value:
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    test eax,eax
    jz .segment_next
    mov rdi,rbx
    mov esi,7
    test r13d,r13d
    jz .segment_bits_ready
    mov esi,6
.segment_bits_ready:
    call vp8_signed_literal
    test rax,rax
    js .config_bad
    test r13d,r13d
    jnz .store_segment_filter
    mov [r12+WebPVP8Config.segment_quant+r14*4],eax
    jmp .segment_next
.store_segment_filter:
    mov [r12+WebPVP8Config.segment_filter+r14*4],eax
.segment_next:
    inc r14d
    cmp r14d,4
    jb .segment_value
    inc r13d
    cmp r13d,2
    jb .segment_feature
.segment_map:
    cmp dword [r12+WebPVP8Config.segment_map_update],0
    je .filter_header
    xor r13d,r13d
.segment_prob:
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    test eax,eax
    jz .segment_prob_next
    mov rdi,rbx
    mov esi,8
    call webp_bool_literal
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.segment_probs+r13],al
.segment_prob_next:
    inc r13d
    cmp r13d,3
    jb .segment_prob
.filter_header:
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.filter_type],eax
    mov rdi,rbx
    mov esi,6
    call webp_bool_literal
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.filter_level],eax
    mov rdi,rbx
    mov esi,3
    call webp_bool_literal
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.sharpness],eax
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.lf_adjustments],eax
    test eax,eax
    jz .token_partitions
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.lf_update],eax
    test eax,eax
    jz .token_partitions
    xor r13d,r13d
.lf_delta:
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    test eax,eax
    jz .lf_next
    mov rdi,rbx
    mov esi,6
    call vp8_signed_literal
    test rax,rax
    js .config_bad
    cmp r13d,4
    jae .store_mode_delta
    mov [r12+WebPVP8Config.ref_lf_deltas+r13*4],eax
    jmp .lf_next
.store_mode_delta:
    mov edx,r13d
    sub edx,4
    mov [r12+WebPVP8Config.mode_lf_deltas+rdx*4],eax
.lf_next:
    inc r13d
    cmp r13d,8
    jb .lf_delta
.token_partitions:
    mov rdi,rbx
    mov esi,2
    call webp_bool_literal
    test rax,rax
    js .config_bad
    mov ecx,eax
    mov eax,1
    shl eax,cl
    mov [r12+WebPVP8Config.token_partitions],eax
    mov rdi,rbx
    mov esi,7
    call webp_bool_literal
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.base_qindex],eax
    xor r13d,r13d
.quant_delta:
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    test eax,eax
    jz .quant_next
    mov rdi,rbx
    mov esi,4
    call vp8_signed_literal
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.quant_deltas+r13*4],eax
.quant_next:
    inc r13d
    cmp r13d,5
    jb .quant_delta
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .config_bad
    mov [r12+WebPVP8Config.refresh_entropy],eax
    xor eax,eax
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.config_bad:
    mov rax,-EINVAL
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
; token_data,token_length,partition_count,WebPVP8Partitions* -> 0/-EINVAL.
global webp_vp8_parse_partitions
webp_vp8_parse_partitions:
    test rdi,rdi
    jz .part_bad
    test rcx,rcx
    jz .part_bad
    cmp edx,1
    je .part_count_ok
    cmp edx,2
    je .part_count_ok
    cmp edx,4
    je .part_count_ok
    cmp edx,8
    jne .part_bad
.part_count_ok:
    mov eax,edx
    dec eax
    imul eax,3
    cmp rsi,rax
    jb .part_bad
    mov r8d,edx
    mov [rcx+WebPVP8Partitions.count],edx
    lea r9,[rdi+rax]
    sub rsi,rax
    xor r10d,r10d
.part_size:
    lea eax,[r10+1]
    cmp eax,r8d
    jae .part_last
    movzx eax,byte [rdi]
    movzx edx,byte [rdi+1]
    shl edx,8
    or eax,edx
    movzx edx,byte [rdi+2]
    shl edx,16
    or eax,edx
    add rdi,3
    cmp rsi,rax
    jb .part_bad
    mov [rcx+WebPVP8Partitions.data+r10*8],r9
    mov [rcx+WebPVP8Partitions.length+r10*8],rax
    add r9,rax
    sub rsi,rax
    inc r10d
    jmp .part_size
.part_last:
    mov [rcx+WebPVP8Partitions.data+r10*8],r9
    mov [rcx+WebPVP8Partitions.length+r10*8],rsi
    xor eax,eax
    ret
.part_bad:
    mov rax,-EINVAL
    ret
; VP8 payload,len,WebPVP8Info* -> 0/-EINVAL. WebP carries key frames only.
global webp_vp8_inspect
webp_vp8_inspect:
    test rdi,rdi
    jz .inspect_bad
    test rdx,rdx
    jz .inspect_bad
    cmp rsi,10
    jb .inspect_bad
    mov eax,[rdi]
    and eax,0x00ffffff
    test eax,1                         ; interframe is invalid in WebP
    jnz .inspect_bad
    mov ecx,eax
    shr ecx,1
    and ecx,7
    cmp ecx,3
    ja .inspect_bad
    mov r8d,eax
    shr r8d,4
    and r8d,1
    mov r9d,eax
    shr r9d,5                          ; first partition size
    cmp byte [rdi+3],0x9d
    jne .inspect_bad
    cmp byte [rdi+4],0x01
    jne .inspect_bad
    cmp byte [rdi+5],0x2a
    jne .inspect_bad
    movzx eax,word [rdi+6]
    and eax,0x3fff
    jz .inspect_bad
    movzx r10d,word [rdi+8]
    and r10d,0x3fff
    jz .inspect_bad
    mov r11,rsi
    sub r11,10
    cmp r9,r11
    ja .inspect_bad
    mov [rdx+WebPVP8Info.width],eax
    mov [rdx+WebPVP8Info.height],r10d
    mov [rdx+WebPVP8Info.version],ecx
    mov [rdx+WebPVP8Info.show_frame],r8d
    lea rax,[rdi+10]
    mov [rdx+WebPVP8Info.first],rax
    mov [rdx+WebPVP8Info.first_len],r9
    add rax,r9
    mov [rdx+WebPVP8Info.tokens],rax
    sub r11,r9
    mov [rdx+WebPVP8Info.tokens_len],r11
    xor eax,eax
    ret
.inspect_bad:
    mov rax,-EINVAL
    ret

section .data
global webp_vp8_version
webp_vp8_version: dq 0x010000
