; Strict bounded Git protocol-v2 upload request parser.
%include "include/vcs.inc"
bits 64
default rel

extern bridge_pkt_decode

%define GIT_REQUEST_LS_REFS 1
%define GIT_REQUEST_FETCH 2

section .bss
request_cursor: resq 1
request_left: resq 1
request_want: resb 32
request_operation: resq 1
request_format: resb 1
request_done: resb 1
request_want_set: resb 1

section .rodata
ls_command: db 'command=ls-refs',10
ls_command_len equ $-ls_command
fetch_command: db 'command=fetch',10
fetch_command_len equ $-fetch_command
format_line: db 'object-format=sha256',10
format_line_len equ $-format_line
want_prefix: db 'want '
done_line: db 'done',10

section .text
global git_protocol_v2_parse_request
; RDI=complete request, RSI=length.
; RAX=status, RDX=operation, RCX=32-byte wanted OID or zero for ls-refs.
git_protocol_v2_parse_request:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .usage
 test rsi,rsi
 jz .usage
 mov [request_cursor],rdi
 mov [request_left],rsi
 mov qword [request_operation],0
 mov byte [request_format],0
 mov byte [request_done],0
 mov byte [request_want_set],0
 call next_packet
 test eax,eax
 jnz .done
 test r9,r9
 jnz .corrupt
 lea rdi,[ls_command]
 mov esi,ls_command_len
 call packet_equal
 test eax,eax
 jz .ls
 lea rdi,[fetch_command]
 mov esi,fetch_command_len
 call packet_equal
 test eax,eax
 jnz .corrupt
 mov qword [request_operation],GIT_REQUEST_FETCH
 jmp .headers
.ls:
 mov qword [request_operation],GIT_REQUEST_LS_REFS
.headers:
 call next_packet
 test eax,eax
 jnz .done
 cmp r9,1
 je .arguments
 test r9,r9
 jnz .corrupt
 lea rdi,[format_line]
 mov esi,format_line_len
 call packet_equal
 test eax,eax
 jnz .headers                    ; ignore bounded agent/session headers
 mov byte [request_format],1
 jmp .headers
.arguments:
 cmp byte [request_format],1
 jne .corrupt
.argument:
 call next_packet
 test eax,eax
 jnz .done
 test r9,r9
 jz .argument_payload
 jmp .corrupt
.argument_payload:
 test rcx,rcx
 jz .finish
 cmp qword [request_operation],GIT_REQUEST_LS_REFS
 je .argument                    ; peel/symrefs/ref-prefix are response filters
 cmp rcx,69
 jne .fetch_done_check
 cmp dword [rdx],0x746e6177      ; "want"
 jne .fetch_done_check
 cmp byte [rdx+4],' '
 jne .corrupt
 cmp byte [request_want_set],0
 jne .corrupt
 lea rsi,[rdx+5]
 lea rdi,[request_want]
 mov ecx,32
.hex_byte:
 call hex_nibble
 jc .corrupt
 shl al,4
 mov bl,al
 call hex_nibble
 jc .corrupt
 or al,bl
 stosb
 loop .hex_byte
 cmp byte [rsi],10
 jne .corrupt
 mov byte [request_want_set],1
 jmp .argument
.fetch_done_check:
 lea rdi,[done_line]
 mov esi,done_line_len
 call packet_equal
 test eax,eax
 jnz .corrupt
 mov byte [request_done],1
 jmp .argument
.finish:
 cmp qword [request_left],0
 jne .corrupt
 mov rdx,[request_operation]
 cmp rdx,GIT_REQUEST_LS_REFS
 je .finish_ls
 cmp byte [request_done],1
 jne .corrupt
 cmp byte [request_want_set],1
 jne .corrupt
 lea rcx,[request_want]
 xor eax,eax
 jmp .done
.finish_ls:
 xor ecx,ecx
 xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.corrupt: mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

next_packet:
 sub rsp,8
 mov rdi,[request_cursor]
 mov rsi,[request_left]
 call bridge_pkt_decode
 test eax,eax
 jnz .packet_done
 add [request_cursor],r8
 sub [request_left],r8
.packet_done:
 add rsp,8
 ret

; Current packet RDX/RCX compared with RDI/RSI. EAX=0 equal.
packet_equal:
 cmp rcx,rsi
 jne .not_equal
 repe cmpsb
 jne .not_equal
 xor eax,eax
 ret
.not_equal: mov eax,1
 ret

; Read one hexadecimal nibble from RSI, advance, CF on invalid.
hex_nibble:
 lodsb
 cmp al,'0'
 jb .bad
 cmp al,'9'
 jbe .number
 or al,32
 cmp al,'a'
 jb .bad
 cmp al,'f'
 ja .bad
 sub al,'a'-10
 clc
 ret
.number:
 sub al,'0'
 clc
 ret
.bad: stc
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
