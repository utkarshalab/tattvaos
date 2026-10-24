; Quote-aware command lists. Validate every segment before any dispatch.
%include "inc/ush.inc"
bits 64
default rel
extern parser_validate
section .bss
global chain_entries
chain_entries: resq 128*2 ; pointer, preceding condition: 0 always, 1 AND, 2 OR
chain_buffer: resb USH_MAX_LINE_LEN
section .text
global chain_prepare
chain_prepare:
 push rbx
 push rbp
 push r12
 push r13
 push r14
 push r15
 sub rsp,24
 test rdi,rdi
 jz .error
 xor ecx,ecx
.bound:
 cmp byte [rdi+rcx],0
 je .copy
 inc ecx
 cmp ecx,USH_MAX_LINE_LEN
 jb .bound
 jmp .error
.copy:
 mov rsi,rdi
 lea rdi,[chain_buffer]
 inc ecx
 rep movsb
 lea r12,[chain_buffer]
 mov r13,r12
 xor ebx,ebx
 xor r14d,r14d
 xor r15d,r15d
 mov qword [rsp],0 ; lexical token active (for comments)
.scan:
 mov al,[r12]
 test al,al
 jz .final
 cmp r15d,1
 je .single
 cmp al,92
 je .escape
 cmp al,34
 je .double
 test r15d,r15d
 jnz .advance_word
 cmp al,39
 je .quote
 cmp al,';'
 je .semicolon
 cmp al,'&'
 je .and
 cmp al,'|'
 je .or
 cmp al,'<'
 je .error
 cmp al,'>'
 je .error
 cmp al,'`'
 je .error
 cmp al,32
 je .space
 cmp al,9
 je .space
 cmp al,10
 je .space
 cmp al,13
 je .space
 cmp al,'#'
 jne .advance_word
 cmp qword [rsp],0
 jne .advance_word
 mov byte [r12],0
 jmp .final
.single:
 cmp al,39
 jne .advance_word
 xor r15d,r15d
 jmp .advance_word
.quote:
 mov r15d,1
 jmp .advance_word
.double:
 xor r15d,2
 jmp .advance_word
.escape:
 inc r12
 cmp byte [r12],0
 je .error
.advance_word:
 mov qword [rsp],1
 inc r12
 jmp .scan
.space:
 mov qword [rsp],0
 inc r12
 jmp .scan
.semicolon:
 mov qword [rsp+8],0
 lea rbp,[r12+1]
 mov byte [r12],0
 jmp .segment
.and:
 cmp byte [r12+1],'&'
 jne .error
 mov qword [rsp+8],1
 jmp .double_operator
.or:
 cmp byte [r12+1],'|'
 jne .error
 mov qword [rsp+8],2
.double_operator:
 mov word [r12],0
 lea rbp,[r12+2]
.segment:
 mov rdi,r13
 call parser_validate
 test rax,rax
 jle .error
 call .append
 jc .error
 mov rbx,[rsp+8]
 mov r12,rbp
 mov r13,rbp
 mov qword [rsp],0
 jmp .scan
.final:
 test r15d,r15d
 jnz .error
 mov rdi,r13
 call parser_validate
 test rax,rax
 js .error
 jz .empty_final
 call .append
 jc .error
 jmp .success
.empty_final:
 test r14,r14
 jz .success
 test rbx,rbx
 jnz .error ; trailing semicolon allowed; dangling AND/OR rejected
.success:
 mov rax,r14
 jmp .return
.error:
 mov rax,-1
.return:
 add rsp,24
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbp
 pop rbx
 ret
.append:
 cmp r14,128
 jae .full
 mov rax,r14
 shl rax,4
 lea rdx,[chain_entries]
 mov [rdx+rax],r13
 mov [rdx+rax+8],rbx
 inc r14
 clc
 ret
.full:
 stc
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
