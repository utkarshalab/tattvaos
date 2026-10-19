; VP8L canonical Huffman tables. Codes are consumed least-significant bit first.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern webp_bits_get

section .text

; table,lengths,symbol_count -> 0 or -EINVAL.
global webp_huff_build
webp_huff_build:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    test rbx,rbx
    jz .bad
    test r12,r12
    jz .bad
    test r13,r13
    jz .bad
    cmp r13,WEBP_HUFF_MAX_SYMBOLS
    ja .bad
    mov rdi,rbx
    xor eax,eax
    mov ecx,WEBP_HUFF_SYMBOLS/8
    rep stosq
    xor r14d,r14d                    ; symbol
    xor r15d,r15d                    ; non-zero lengths
.count:
    cmp r14,r13
    jae .validate
    movzx eax,byte [r12+r14]
    cmp eax,15
    ja .bad
    test eax,eax
    jz .count_next
    inc dword [rbx+WEBP_HUFF_COUNTS+rax*4]
    inc r15d
.count_next:
    inc r14
    jmp .count
.validate:
    test r15d,r15d
    jz .bad
    mov edx,1
    mov ecx,1
.slots:
    shl edx,1
    sub edx,[rbx+WEBP_HUFF_COUNTS+rcx*4]
    js .bad
    inc ecx
    cmp ecx,16
    jb .slots
    test edx,edx
    jz .canonical
    cmp r15d,1                       ; VP8L simple one-symbol tree
    jne .bad
.canonical:
    xor r8d,r8d                      ; canonical code
    xor r9d,r9d                      ; first symbol index
    xor r10d,r10d                    ; previous count
    mov ecx,1
.first:
    add r8d,r10d
    shl r8d,1
    mov [rbx+WEBP_HUFF_FIRST_CODE+rcx*4],r8d
    mov [rbx+WEBP_HUFF_FIRST_SYM+rcx*4],r9d
    mov r10d,[rbx+WEBP_HUFF_COUNTS+rcx*4]
    add r9d,r10d
    inc ecx
    cmp ecx,16
    jb .first
    xor r14d,r14d
    mov ecx,1
.length:
    cmp ecx,16
    jae .ok
    xor edx,edx
.symbol:
    cmp rdx,r13
    jae .next_length
    movzx eax,byte [r12+rdx]
    cmp eax,ecx
    jne .symbol_next
    mov [rbx+WEBP_HUFF_SYMBOLS+r14*2],dx
    inc r14d
.symbol_next:
    inc edx
    jmp .symbol
.next_length:
    inc ecx
    jmp .length
.ok:
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; table,WebPBitReader* -> symbol or -EINVAL.
global webp_huff_decode
webp_huff_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14
    mov rbx,rdi
    mov r12,rsi
    cmp dword [rbx+WEBP_HUFF_COUNTS],0
    je .decode_bits
    mov eax,[rbx+WEBP_HUFF_FIRST_CODE]
    EPILOGUE_RESTORE rbx,r12,r13,r14
    ret
.decode_bits:
    xor r13d,r13d                    ; canonical code
    mov r14d,1                       ; length
.bit:
    mov rdi,r12
    mov esi,1
    call webp_bits_get
    test rax,rax
    js .bad
    shl r13d,1                       ; Huffman codes are consumed MSB first
    or r13d,eax                      ; within the LSB-packed bit stream
    mov eax,[rbx+WEBP_HUFF_FIRST_CODE+r14*4]
    cmp r13d,eax
    jb near .next
    mov edx,r13d
    sub edx,eax
    cmp edx,[rbx+WEBP_HUFF_COUNTS+r14*4]
    jae near .next
    add edx,[rbx+WEBP_HUFF_FIRST_SYM+r14*4]
    movzx eax,word [rbx+WEBP_HUFF_SYMBOLS+rdx*2]
    EPILOGUE_RESTORE rbx,r12,r13,r14
    ret
.next:
    inc r14d
    cmp r14d,16
    jb .bit
.bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13,r14
    ret

; reader,alphabet_size,out_table,length_scratch,temp_table -> 0 or -EINVAL.
; length_scratch must hold alphabet_size+19 bytes.
global webp_huff_read
webp_huff_read:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    mov r12d,esi
    mov r13,rdx
    mov r14,rcx
    mov r15,r8
    test rbx,rbx
    jz .read_bad
    test r13,r13
    jz .read_bad
    test r14,r14
    jz .read_bad
    test r15,r15
    jz .read_bad
    test r12d,r12d
    jz .read_bad
    cmp r12d,WEBP_HUFF_MAX_SYMBOLS
    ja .read_bad
    mov rdi,r14
    xor eax,eax
    mov ecx,r12d
    add ecx,19
    rep stosb
    mov rdi,rbx
    mov esi,1
    call webp_bits_get
    test rax,rax
    js .read_bad
    test eax,eax
    jz .normal
    mov rdi,rbx
    mov esi,1
    call webp_bits_get
    test rax,rax
    js .read_bad
    inc eax
    mov [rsp],eax                    ; simple symbol count
    mov rdi,rbx
    mov esi,1
    call webp_bits_get
    test rax,rax
    js .read_bad
    imul esi,eax,7
    inc esi
    mov rdi,rbx
    call webp_bits_get
    test rax,rax
    js .read_bad
    cmp eax,r12d
    jae .read_bad
    mov [rsp+4],eax
    mov byte [r14+rax],1
    cmp dword [rsp],1
    je .simple_single
    mov rdi,rbx
    mov esi,8
    call webp_bits_get
    test rax,rax
    js .read_bad
    cmp eax,r12d
    jae .read_bad
    cmp eax,[rsp+4]
    je .simple_single                  ; duplicate symbols encode a constant tree
    mov byte [r14+rax],1
    jmp .build
.simple_single:
    mov rdi,r13
    xor eax,eax
    mov ecx,WEBP_HUFF_SYMBOLS/8
    rep stosq
    mov dword [r13+WEBP_HUFF_COUNTS],1
    mov eax,[rsp+4]
    mov [r13+WEBP_HUFF_FIRST_CODE],eax
    xor eax,eax
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

.normal:
    lea rax,[r14+r12]
    mov [rsp+24],rax                 ; code-length lengths
    mov rdi,rbx
    mov esi,4
    call webp_bits_get
    test rax,rax
    js .read_bad
    add eax,4
    mov [rsp],eax                    ; number of code-length codes
    mov dword [rsp+4],0
.code_length_loop:
    mov ecx,[rsp+4]
    cmp ecx,[rsp]
    jae .code_length_build
    mov rdi,rbx
    mov esi,3
    call webp_bits_get
    test rax,rax
    js .read_bad
    mov ecx,[rsp+4]
    lea rdx,[rel code_length_order]
    movzx edx,byte [rdx+rcx]
    mov rdi,[rsp+24]
    mov [rdi+rdx],al
    inc dword [rsp+4]
    jmp .code_length_loop
.code_length_build:
    mov rdi,r15
    mov rsi,[rsp+24]
    mov edx,19
    call webp_huff_build
    test rax,rax
    js .read_bad
    mov dword [rsp+8],r12d           ; symbol limit
    mov rdi,rbx
    mov esi,1
    call webp_bits_get
    test rax,rax
    js .read_bad
    test eax,eax
    jz .lengths_start
    mov rdi,rbx
    mov esi,3
    call webp_bits_get
    test rax,rax
    js .read_bad
    lea esi,[rax*2+2]
    mov rdi,rbx
    call webp_bits_get
    test rax,rax
    js .read_bad
    add eax,2
    cmp eax,r12d
    ja .read_bad
    mov [rsp+8],eax
.lengths_start:
    mov dword [rsp+12],0             ; output index
    mov dword [rsp+16],0             ; previous nonzero length
.lengths_loop:
    mov eax,[rsp+12]
    cmp eax,[rsp+8]
    jae .build
    mov rdi,r15
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .read_bad
    cmp eax,15
    ja .repeat
    mov ecx,[rsp+12]
    mov [r14+rcx],al
    test eax,eax
    jz .literal_done
    mov [rsp+16],eax
.literal_done:
    inc dword [rsp+12]
    jmp .lengths_loop
.repeat:
    mov [rsp+28],eax
    cmp eax,16
    je .repeat_previous
    cmp eax,17
    je .repeat_zero_short
    cmp eax,18
    jne .read_bad
    mov esi,7
    mov dword [rsp+20],11
    jmp .repeat_bits
.repeat_zero_short:
    mov esi,3
    mov dword [rsp+20],3
    jmp .repeat_bits
.repeat_previous:
    mov esi,2
    mov dword [rsp+20],3
.repeat_bits:
    mov rdi,rbx
    call webp_bits_get
    test rax,rax
    js .read_bad
    add [rsp+20],eax
    mov ecx,[rsp+12]
    mov edx,ecx
    add edx,[rsp+20]
    cmp edx,[rsp+8]
    ja .read_bad
    xor eax,eax
    cmp dword [rsp+28],16
    jne .repeat_value_ready
    mov eax,[rsp+16]
    test eax,eax
    jnz .repeat_value_ready
    mov eax,8                          ; code 16 has implicit initial value 8
.repeat_value_ready:
    mov edx,[rsp+20]
.repeat_store:
    test edx,edx
    jz .repeat_done
    mov [r14+rcx],al
    inc ecx
    dec edx
    jmp .repeat_store
.repeat_done:
    mov [rsp+12],ecx
    jmp .lengths_loop
.build:
    mov rdi,r13
    mov rsi,r14
    mov edx,r12d
    call webp_huff_build
    test rax,rax
    js .read_bad
    xor eax,eax
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.read_bad:
    mov rax,-EINVAL
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; reader,cache_bits(0 or 1..11),group,scratch,temp_table -> 0 or -EINVAL.
global webp_huff_group_read
webp_huff_group_read:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12d,esi
    mov r13,rdx
    mov r14,rcx
    mov r15,r8
    cmp r12d,11
    ja .group_bad
    mov esi,280
    test r12d,r12d
    jz .green_size_ready
    mov ecx,r12d
    mov eax,1
    shl eax,cl
    add esi,eax
.green_size_ready:
    mov rdi,rbx
    lea rdx,[r13+WEBP_GROUP_GREEN]
    mov rcx,r14
    mov r8,r15
    call webp_huff_read
    test rax,rax
    js .group_bad
    mov rdi,rbx
    mov esi,256
    lea rdx,[r13+WEBP_GROUP_RED]
    mov rcx,r14
    mov r8,r15
    call webp_huff_read
    test rax,rax
    js .group_bad
    mov rdi,rbx
    mov esi,256
    lea rdx,[r13+WEBP_GROUP_BLUE]
    mov rcx,r14
    mov r8,r15
    call webp_huff_read
    test rax,rax
    js .group_bad
    mov rdi,rbx
    mov esi,256
    lea rdx,[r13+WEBP_GROUP_ALPHA]
    mov rcx,r14
    mov r8,r15
    call webp_huff_read
    test rax,rax
    js .group_bad
    mov rdi,rbx
    mov esi,40
    lea rdx,[r13+WEBP_GROUP_DISTANCE]
    mov rcx,r14
    mov r8,r15
    call webp_huff_read
    test rax,rax
    js .group_bad
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.group_bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global webp_huffman_version
webp_huffman_version: dq 0x010000

section .rodata
code_length_order: db 17,18,0,1,2,3,4,5,16,6,7,8,9,10,11,12,13,14,15
