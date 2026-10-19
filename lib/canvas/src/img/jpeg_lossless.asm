; JPEG lossless sequential (SOF3), single-component CFA strips.
%include "inc/abi.inc"
%include "inc/macros.inc"

extern arena_alloc
extern jpeg_huff_build
extern jpeg_huff_decode_stream
extern jpeg_bits_init
extern jpeg_receive_extend
extern jpeg_expect_restart

%define HT_SIZE       1556
%define S_TABLE          0
%define S_WIDTH          8
%define S_HEIGHT        12
%define S_PRECISION     16
%define S_PREDICTOR     20
%define S_POINT         24
%define S_TABLE_ID      28
%define S_RESTART       32
%define S_COUNT         36
%define S_RSTSEQ        40
%define S_ENTROPY       48
%define S_REMAIN        56
%define S_X             64
%define S_Y             68
%define S_INITIAL       72
%define S_SAMPLE_BYTES  76
%define S_READER        80
%define LOCAL_SIZE     128

section .text

; arena, JPEG stream, length, output, expected width, expected height.
; Returns output byte count or -1.
global jpeg_lossless_decode
jpeg_lossless_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,LOCAL_SIZE
    mov rbx,rdi
    mov r12,rsi
    lea r13,[rsi+rdx]
    mov r14,rcx
    mov r15d,r8d
    mov [rsp+S_HEIGHT],r9d
    cmp rdx,4
    jb .bad
    cmp word [r12],0xd8ff
    jne .bad
    mov rdi,rbx
    mov esi,HT_SIZE*4
    call arena_alloc
    test rax,rax
    jz .bad
    mov [rsp+S_TABLE],rax
    mov rdi,rax
    xor eax,eax
    mov ecx,(HT_SIZE*4)/8
    rep stosq
    mov dword [rsp+S_RESTART],0
    mov qword [rsp+S_ENTROPY],0
    lea r11,[r12+2]
.marker:
    lea rax,[r11+4]
    cmp rax,r13
    ja .bad
    cmp byte [r11],0xff
    jne .bad
    movzx eax,byte [r11+1]
    cmp eax,0xd9
    je .parsed
    cmp eax,0xd8
    je .marker_short
    movzx ecx,word [r11+2]
    xchg cl,ch
    cmp ecx,2
    jb .bad
    lea rdx,[r11+rcx+2]
    cmp rdx,r13
    ja .bad
    cmp eax,0xc4
    je .dht
    cmp eax,0xc3
    je .sof3
    cmp eax,0xdd
    je .dri
    cmp eax,0xda
    je .sos
.marker_next:
    lea r11,[r11+rcx+2]
    jmp .marker
.marker_short:
    add r11,2
    jmp .marker
.dht:
    lea r8,[r11+4]
    lea r9,[r11+rcx+2]
.dht_table:
    cmp r8,r9
    jae .marker_next_reload
    lea rax,[r8+17]
    cmp rax,r9
    ja .bad
    movzx eax,byte [r8]
    test eax,0xf0
    jnz .bad
    and eax,0x0f
    cmp eax,3
    ja .bad
    mov r10d,eax
    xor edx,edx
    xor ecx,ecx
.sum:
    movzx eax,byte [r8+rcx+1]
    add edx,eax
    inc ecx
    cmp ecx,16
    jb .sum
    test edx,edx
    jz .bad
    cmp edx,256
    ja .bad
    lea rax,[r8+rdx+17]
    cmp rax,r9
    ja .bad
    mov [rsp+S_COUNT],edx
    imul r10d,HT_SIZE
    mov rdi,[rsp+S_TABLE]
    add rdi,r10
    lea rsi,[r8+1]
    lea rdx,[r8+17]
    mov ecx,[rsp+S_COUNT]
    push r8
    push r9
    push r11
    call jpeg_huff_build
    pop r11
    pop r9
    pop r8
    test eax,eax
    jnz .bad
    add r8,17
    add r8,[rsp+S_COUNT]
    jmp .dht_table
.marker_next_reload:
    movzx ecx,word [r11+2]
    xchg cl,ch
    jmp .marker_next
.sof3:
    cmp ecx,11
    jne .bad
    movzx eax,byte [r11+4]
    cmp eax,2
    jb .bad
    cmp eax,16
    ja .bad
    mov [rsp+S_PRECISION],eax
    movzx eax,word [r11+5]
    xchg al,ah
    cmp eax,[rsp+S_HEIGHT]
    jne .bad
    mov [rsp+S_HEIGHT],eax
    movzx eax,word [r11+7]
    xchg al,ah
    cmp eax,r15d
    jne .bad
    mov [rsp+S_WIDTH],eax
    cmp byte [r11+9],1
    jne .bad
    cmp byte [r11+11],0x11
    jne .bad
    jmp .marker_next
.dri:
    cmp ecx,4
    jne .bad
    movzx eax,word [r11+4]
    xchg al,ah
    mov [rsp+S_RESTART],eax
    jmp .marker_next
.sos:
    cmp ecx,8
    jne .bad
    cmp byte [r11+4],1
    jne .bad
    movzx eax,byte [r11+6]
    shr eax,4
    cmp eax,3
    ja .bad
    mov [rsp+S_TABLE_ID],eax
    movzx eax,byte [r11+7]
    cmp eax,1
    jb .bad
    cmp eax,7
    ja .bad
    mov [rsp+S_PREDICTOR],eax
    cmp byte [r11+8],0
    jne .bad
    movzx eax,byte [r11+9]
    test eax,0xf0
    jnz .bad
    and eax,0x0f
    cmp eax,[rsp+S_PRECISION]
    jae .bad
    mov [rsp+S_POINT],eax
    lea rax,[r11+rcx+2]
    mov [rsp+S_ENTROPY],rax
    mov rdx,r13
    sub rdx,rax
    mov [rsp+S_REMAIN],rdx
    jmp .parsed
.parsed:
    cmp qword [rsp+S_ENTROPY],0
    je .bad
    mov r15,rsp
    mov eax,[rsp+S_PRECISION]
    sub eax,[rsp+S_POINT]
    dec eax
    mov ecx,eax
    mov eax,1
    shl eax,cl
    mov [rsp+S_INITIAL],eax
    mov eax,1
    cmp dword [rsp+S_PRECISION],8
    jbe .bytes_ready
    mov eax,2
.bytes_ready:
    mov [rsp+S_SAMPLE_BYTES],eax
    lea rdi,[rsp+S_READER]
    mov rsi,[rsp+S_ENTROPY]
    mov rdx,[rsp+S_REMAIN]
    call jpeg_bits_init
    mov dword [rsp+S_COUNT],0
    mov dword [rsp+S_RSTSEQ],0
    mov dword [rsp+S_Y],0
.row:
    mov eax,[rsp+S_Y]
    cmp eax,[rsp+S_HEIGHT]
    jae .done
    mov dword [rsp+S_X],0
.pixel:
    mov eax,[rsp+S_X]
    cmp eax,[rsp+S_WIDTH]
    jae .next_row
    cmp dword [rsp+S_COUNT],0
    je .predict_initial
    mov edx,[rsp+S_RESTART]
    test edx,edx
    jz .predict_regular
    mov eax,[rsp+S_COUNT]
    cmp eax,edx
    jne .predict_regular
    lea rdi,[rsp+S_READER]
    mov esi,[rsp+S_RSTSEQ]
    call jpeg_expect_restart
    test eax,eax
    jnz .bad
    inc dword [rsp+S_RSTSEQ]
    and dword [rsp+S_RSTSEQ],7
    mov dword [rsp+S_COUNT],0
    jmp .predict_initial
.predict_regular:
    mov eax,[rsp+S_X]
    test eax,eax
    jz .predict_above
    mov eax,[rsp+S_Y]
    test eax,eax
    jz .predict_left
    call .load_neighbors
    mov eax,[rsp+S_PREDICTOR]
    cmp eax,1
    je .pred_a
    cmp eax,2
    je .pred_b
    cmp eax,3
    je .pred_c
    cmp eax,4
    je .pred4
    cmp eax,5
    je .pred5
    cmp eax,6
    je .pred6
    ; P7 = (A+B)/2
    mov eax,r8d
    add eax,r9d
    sar eax,1
    jmp .have_predictor
.pred_a: mov eax,r8d
    jmp .have_predictor
.pred_b: mov eax,r9d
    jmp .have_predictor
.pred_c: mov eax,r10d
    jmp .have_predictor
.pred4:
    mov eax,r8d
    add eax,r9d
    sub eax,r10d
    jmp .have_predictor
.pred5:
    mov eax,r9d
    sub eax,r10d
    sar eax,1
    add eax,r8d
    jmp .have_predictor
.pred6:
    mov eax,r8d
    sub eax,r10d
    sar eax,1
    add eax,r9d
    jmp .have_predictor
.predict_left:
    call .load_left
    jmp .have_predictor
.predict_above:
    mov eax,[rsp+S_Y]
    test eax,eax
    jz .predict_initial
    call .load_above
    jmp .have_predictor
.predict_initial:
    mov eax,[rsp+S_INITIAL]
.have_predictor:
    push rax
    mov eax,[rsp+8+S_TABLE_ID]
    imul eax,HT_SIZE
    mov rdi,[rsp+8+S_TABLE]
    add rdi,rax
    lea rsi,[rsp+8+S_READER]
    call jpeg_huff_decode_stream
    test rax,rax
    js .decode_bad_pop
    cmp eax,16
    ja .decode_bad_pop
    lea rdi,[rsp+8+S_READER]
    mov esi,eax
    call jpeg_receive_extend
    test edx,edx
    jnz .decode_bad_pop
    pop rcx
    add eax,ecx
    mov ecx,[rsp+S_PRECISION]
    sub ecx,[rsp+S_POINT]
    mov edx,1
    shl edx,cl
    dec edx
    and eax,edx
    mov ecx,[rsp+S_POINT]
    shl eax,cl
    call .store_sample
    inc dword [rsp+S_X]
    inc dword [rsp+S_COUNT]
    jmp .pixel
.decode_bad_pop:
    add rsp,8
    jmp .bad
.next_row:
    inc dword [rsp+S_Y]
    jmp .row
.done:
    mov eax,[rsp+S_WIDTH]
    imul eax,[rsp+S_HEIGHT]
    imul eax,[rsp+S_SAMPLE_BYTES]
    add rsp,LOCAL_SIZE
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    mov rax,-1
    add rsp,LOCAL_SIZE
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; Neighbor/sample helpers use little-endian expanded output.
.sample_offset:
    imul eax,[r15+S_WIDTH]
    add eax,edx
    imul eax,[r15+S_SAMPLE_BYTES]
    ret
.load_left:
    mov eax,[r15+S_Y]
    mov edx,[r15+S_X]
    dec edx
    call .sample_offset
    jmp .load_at
.load_above:
    mov eax,[r15+S_Y]
    dec eax
    mov edx,[r15+S_X]
    call .sample_offset
.load_at:
    cmp dword [r15+S_SAMPLE_BYTES],1
    jne .load_word
    movzx eax,byte [r14+rax]
    ret
.load_word:
    movzx eax,word [r14+rax]
    ret
.load_neighbors:
    mov eax,[r15+S_Y]
    mov edx,[r15+S_X]
    dec edx
    call .sample_offset
    call .load_at
    mov r8d,eax
    mov eax,[r15+S_Y]
    dec eax
    mov edx,[r15+S_X]
    call .sample_offset
    call .load_at
    mov r9d,eax
    mov eax,[r15+S_Y]
    dec eax
    mov edx,[r15+S_X]
    dec edx
    call .sample_offset
    call .load_at
    mov r10d,eax
    ret
.store_sample:
    push rax
    mov eax,[r15+S_Y]
    mov edx,[r15+S_X]
    call .sample_offset
    mov edx,eax
    pop rax
    cmp dword [r15+S_SAMPLE_BYTES],1
    jne .store_word
    mov [r14+rdx],al
    ret
.store_word:
    mov [r14+rdx],ax
    ret

section .data
global jpeg_lossless_version
jpeg_lossless_version: dq 0x010000
