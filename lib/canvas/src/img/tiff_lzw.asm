; TIFF LZW (MSB-first codes, clear=256, EOI=257, early-change=1).
%include "inc/abi.inc"
%include "inc/macros.inc"

extern arena_alloc

%define W_PREFIX       0
%define W_SUFFIX    8192
%define W_STACK    12288
%define W_SIZE     16384

%define S_WORK         0
%define S_OUTPOS       8
%define S_BITBUF      16
%define S_NBITS       24
%define S_WIDTH       28
%define S_NEXT        32
%define S_OLD         36
%define S_FIRST       40
%define S_STACKLEN    44
%define S_CODE        48
%define S_INCODE      52
%define STACK_SIZE    64

section .text

; arena, source, source length, destination, exact output capacity.
; Returns bytes written, or -1 for malformed/truncated input.
global tiff_lzw_decode
tiff_lzw_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,STACK_SIZE
    mov rbx,rdi
    mov r12,rsi
    lea r13,[rsi+rdx]
    mov r14,rcx
    mov r15,r8
    mov rdi,rbx
    mov esi,W_SIZE
    call arena_alloc
    test rax,rax
    jz .bad
    mov [rsp+S_WORK],rax
    mov qword [rsp+S_OUTPOS],0
    mov qword [rsp+S_BITBUF],0
    mov dword [rsp+S_NBITS],0
    mov dword [rsp+S_WIDTH],9
    mov dword [rsp+S_NEXT],258
    mov dword [rsp+S_OLD],-1
    xor ecx,ecx
.init_literals:
    mov [rax+W_SUFFIX+rcx],cl
    inc ecx
    cmp ecx,256
    jb .init_literals

.code_loop:
    ; Read one MSB-first variable-width code.
.refill:
    mov ecx,[rsp+S_NBITS]
    cmp ecx,[rsp+S_WIDTH]
    jae .have_code
    cmp r12,r13
    jae .bad
    shl qword [rsp+S_BITBUF],8
    movzx eax,byte [r12]
    or [rsp+S_BITBUF],rax
    inc r12
    add dword [rsp+S_NBITS],8
    jmp .refill
.have_code:
    mov ecx,[rsp+S_NBITS]
    sub ecx,[rsp+S_WIDTH]
    mov rax,[rsp+S_BITBUF]
    shr rax,cl
    mov ecx,[rsp+S_WIDTH]
    mov edx,1
    shl edx,cl
    dec edx
    and eax,edx
    sub [rsp+S_NBITS],ecx
    mov [rsp+S_CODE],eax
    cmp eax,257
    je .finish
    cmp eax,256
    jne .data_code
    mov dword [rsp+S_WIDTH],9
    mov dword [rsp+S_NEXT],258
    mov dword [rsp+S_OLD],-1
    jmp .code_loop

.data_code:
    mov [rsp+S_INCODE],eax
    mov edx,[rsp+S_OLD]
    cmp edx,-1
    jne .known_old
    cmp eax,256
    jae .bad
    mov rcx,[rsp+S_OUTPOS]
    cmp rcx,r15
    jae .bad
    mov [r14+rcx],al
    inc qword [rsp+S_OUTPOS]
    mov [rsp+S_FIRST],eax
    mov [rsp+S_OLD],eax
    jmp .code_loop

.known_old:
    mov ecx,[rsp+S_NEXT]
    cmp eax,ecx
    ja .bad
    mov dword [rsp+S_STACKLEN],0
    jne .expand
    ; KwKwK: decode the previous string and append its first byte.
    mov eax,[rsp+S_FIRST]
    mov rdi,[rsp+S_WORK]
    mov [rdi+W_STACK],al
    mov dword [rsp+S_STACKLEN],1
    mov eax,[rsp+S_OLD]
.expand:
    cmp eax,256
    jb .literal
    cmp eax,[rsp+S_NEXT]
    jae .bad
    mov ecx,[rsp+S_STACKLEN]
    cmp ecx,4096
    jae .bad
    mov rdi,[rsp+S_WORK]
    mov dl,[rdi+W_SUFFIX+rax]
    mov [rdi+W_STACK+rcx],dl
    inc dword [rsp+S_STACKLEN]
    movzx eax,word [rdi+W_PREFIX+rax*2]
    jmp .expand
.literal:
    mov [rsp+S_FIRST],eax
    mov ecx,[rsp+S_STACKLEN]
    cmp ecx,4096
    jae .bad
    mov rdi,[rsp+S_WORK]
    mov [rdi+W_STACK+rcx],al
    inc dword [rsp+S_STACKLEN]
.emit:
    mov ecx,[rsp+S_STACKLEN]
    test ecx,ecx
    jz .add_entry
    mov rax,[rsp+S_OUTPOS]
    cmp rax,r15
    jae .bad
    dec ecx
    mov [rsp+S_STACKLEN],ecx
    mov rdi,[rsp+S_WORK]
    mov dl,[rdi+W_STACK+rcx]
    mov [r14+rax],dl
    inc qword [rsp+S_OUTPOS]
    jmp .emit
.add_entry:
    mov eax,[rsp+S_NEXT]
    cmp eax,4096
    jae .set_old
    mov rdi,[rsp+S_WORK]
    mov dx,[rsp+S_OLD]
    mov [rdi+W_PREFIX+rax*2],dx
    mov dl,[rsp+S_FIRST]
    mov [rdi+W_SUFFIX+rax],dl
    inc eax
    mov [rsp+S_NEXT],eax
    cmp dword [rsp+S_WIDTH],12
    jae .set_old
    mov ecx,[rsp+S_WIDTH]
    mov edx,1
    shl edx,cl
    dec edx                             ; TIFF early-change threshold
    cmp eax,edx
    jne .set_old
    inc dword [rsp+S_WIDTH]
.set_old:
    mov eax,[rsp+S_INCODE]
    mov [rsp+S_OLD],eax
    jmp .code_loop

.finish:
    mov rax,[rsp+S_OUTPOS]
    cmp rax,r15
    jne .bad
    add rsp,STACK_SIZE
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    mov rax,-1
    add rsp,STACK_SIZE
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global tiff_lzw_version
tiff_lzw_version: dq 0x010000
