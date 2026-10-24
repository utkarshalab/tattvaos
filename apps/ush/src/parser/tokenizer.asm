; Bounded quote-aware tokenizer and variable expansion, one shell instance.
; parser_tokenize(rdi=NUL input) -> rax=argc or -1. Does not modify input.
; token_argc=0 on any error; token_argv is always terminated with NULL.
%include "inc/ush.inc"
bits 64
default rel
extern env_get_var,calc_format,ush_last_status
section .bss
global token_argc,token_argv
token_argc: resq 1
token_argv: resq USH_MAX_ARGS+1
token_buffer: resb USH_MAX_LINE_LEN
expand_name: resb 64
expand_status: resb 32
token_validation: resq 1
section .text
global parser_tokenize,parser_validate
parser_tokenize:
 mov qword [token_validation],0
 jmp parser_start
parser_validate:
 mov qword [token_validation],1
parser_start:
 push rbx
 push rbp
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov qword [token_argc],0
 mov qword [token_argv],0
 test rdi,rdi
 jz .error
 mov r12,rdi
 xor ecx,ecx
.bound:
 cmp byte [r12+rcx],0
 je .start
 inc ecx
 cmp ecx,USH_MAX_LINE_LEN
 jb .bound
 jmp .error
.start:
 lea r13,[token_buffer]
 xor r14d,r14d ; completed args
 xor r15d,r15d ; quote: 0 none, 1 single, 2 double
 xor ebx,ebx ; token active
.loop:
 mov al,[r12]
 test al,al
 jz .end
 test r15d,r15d
 jnz .word
 cmp al,32
 je .separator
 cmp al,9
 je .separator
 cmp al,13
 je .separator
 cmp al,10
 je .separator
 cmp al,'#'
 jne .word
 test ebx,ebx
 jz .end
.word:
 test ebx,ebx
 jnz .active
 cmp r14d,USH_MAX_ARGS
 jae .error
 lea rdx,[token_argv]
 mov [rdx+r14*8],r13
 mov ebx,1
.active:
 cmp r15d,1
 je .single
 cmp al,39
 jne .double_check
 test r15d,r15d
 jnz .literal
 mov r15d,1
 inc r12
 jmp .loop
.single:
 cmp al,39
 jne .literal
 xor r15d,r15d
 inc r12
 jmp .loop
.double_check:
 cmp al,34
 jne .escape
 xor r15d,2
 inc r12
 jmp .loop
.escape:
 cmp al,92
 jne .dollar
 inc r12
 mov al,[r12]
 test al,al
 jz .error
 jmp .literal
.dollar:
 cmp al,'$'
 je .expand
 ; Unsupported shell operators are errors, never executed as literal commands.
 test r15d,r15d
 jnz .literal
 cmp al,';'
 je .error
 cmp al,'|'
 je .error
 cmp al,'&'
 je .error
 cmp al,'<'
 je .error
 cmp al,'>'
 je .error
 cmp al,'`'
 je .error
.literal:
 call .put
 jc .error
 inc r12
 jmp .loop
.separator:
 inc r12
 test ebx,ebx
 jz .loop
 xor eax,eax
 call .put
 jc .error
 inc r14d
 xor ebx,ebx
 jmp .loop
.expand:
 inc r12
 cmp byte [r12],'?'
 je .status
 xor ebp,ebp ; braced flag
 cmp byte [r12],'('
 je .error
 cmp byte [r12],'{'
 jne .name_start
 mov ebp,1
 inc r12
.name_start:
 xor ecx,ecx
 lea rdx,[expand_name]
.name_loop:
 mov al,[r12]
 cmp al,'_'
 je .name_char
 cmp al,'A'
 jb .name_digit
 cmp al,'Z'
 jbe .name_char
 cmp al,'a'
 jb .name_digit
 cmp al,'z'
 jbe .name_char
.name_digit:
 test ecx,ecx
 jz .name_done
 cmp al,'0'
 jb .name_done
 cmp al,'9'
 ja .name_done
.name_char:
 cmp ecx,63
 jae .error
 mov [rdx+rcx],al
 inc ecx
 inc r12
 jmp .name_loop
.name_done:
 test ecx,ecx
 jz .literal_dollar
 mov byte [rdx+rcx],0
 test ebp,ebp
 jz .lookup
 cmp byte [r12],'}'
 jne .error
 inc r12
.lookup:
 cmp qword [token_validation],0
 jne .loop
 lea rdi,[expand_name]
 call env_get_var
 test rax,rax
 jz .loop
 mov rbp,rax
.copy_expansion:
 mov al,[rbp]
 test al,al
 jz .loop
 call .put
 jc .error
 inc rbp
 jmp .copy_expansion
.literal_dollar:
 test ebp,ebp
 jnz .error
 mov al,'$'
 call .put
 jc .error
 jmp .loop
.status:
 inc r12
 cmp qword [token_validation],0
 jne .loop
 mov rdi,[ush_last_status]
 mov esi,10
 lea rdx,[expand_status]
 call calc_format
 mov rbp,rax
 jmp .copy_expansion
.end:
 test r15d,r15d
 jnz .error
 test ebx,ebx
 jz .success
 xor eax,eax
 call .put
 jc .error
 inc r14d
.success:
 lea rdx,[token_argv]
 mov qword [rdx+r14*8],0
 mov [token_argc],r14
 mov rax,r14
 jmp .return
.error:
 mov qword [token_argc],0
 mov qword [token_argv],0
 mov rax,-1
.return:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbp
 pop rbx
 ret
.put:
 lea rdx,[token_buffer+USH_MAX_LINE_LEN]
 cmp r13,rdx
 jae .full
 mov [r13],al
 inc r13
 clc
 ret
.full:
 stc
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
