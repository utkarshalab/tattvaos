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
request_have: resb 64*32
request_operation: resq 1
request_flags: resq 1
request_format: resb 1
request_agent: resb 1
request_done: resb 1
request_want_set: resb 1
request_have_count: resb 1
request_wait_done: resb 1
request_peel: resb 1
request_unborn: resb 1
request_want_ref: resb 1

section .rodata
ls_command: db 'command=ls-refs',10
ls_command_len equ $-ls_command
fetch_command: db 'command=fetch',10
fetch_command_len equ $-fetch_command
format_line: db 'object-format=sha256',10
format_line_len equ $-format_line
agent_prefix: db 'agent='
agent_prefix_len equ $-agent_prefix
want_prefix: db 'want '
done_line: db 'done',10
symrefs_line: db 'symrefs',10
symrefs_line_len equ $-symrefs_line
peel_line: db 'peel',10
peel_line_len equ $-peel_line
unborn_line: db 'unborn',10
unborn_line_len equ $-unborn_line
thin_pack_line: db 'thin-pack',10
thin_pack_line_len equ $-thin_pack_line
no_progress_line: db 'no-progress',10
no_progress_line_len equ $-no_progress_line
ofs_delta_line: db 'ofs-delta',10
ofs_delta_line_len equ $-ofs_delta_line
include_tag_line: db 'include-tag',10
include_tag_line_len equ $-include_tag_line
wait_done_line: db 'wait-for-done',10
wait_done_line_len equ $-wait_done_line
sideband_all_line: db 'sideband-all',10
sideband_all_line_len equ $-sideband_all_line
filter_blob_none_line: db 'filter blob:none',10
filter_blob_none_line_len equ $-filter_blob_none_line
filter_tree_zero_line: db 'filter tree:0',10
filter_tree_zero_line_len equ $-filter_tree_zero_line
want_ref_line: db 'want-ref refs/heads/main',10
want_ref_line_len equ $-want_ref_line
ref_prefix_marker: db 'ref-prefix '
ref_prefix_marker_len equ $-ref_prefix_marker
head_ref: db 'HEAD'
head_ref_len equ $-head_ref
main_ref: db 'refs/heads/main'
main_ref_len equ $-main_ref

section .text
global git_protocol_v2_parse_request,git_protocol_v2_haves
; RDI=complete request, RSI=length.
; RAX=status, RDX=operation, RCX=32-byte wanted OID or zero for ls-refs,
; R8 flags: ls-refs bits 0..3; fetch bit 4 want-ref, bit 5 sideband-all,
; bit 6 blob:none, bit 7 tree:0.
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
 mov qword [request_flags],0
 mov byte [request_format],0
 mov byte [request_agent],0
 mov byte [request_done],0
 mov byte [request_want_set],0
 mov byte [request_have_count],0
 mov byte [request_wait_done],0
 mov byte [request_peel],0
 mov byte [request_unborn],0
 mov byte [request_want_ref],0
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
 jnz .agent_header
 cmp byte [request_format],0
 jne .corrupt
 mov byte [request_format],1
 jmp .headers
.agent_header:
 call validate_agent_header
 test eax,eax
 jnz .corrupt
 cmp byte [request_agent],0
 jne .corrupt
 mov byte [request_agent],1
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
 je .ls_argument
 cmp byte [request_done],0
 jne .corrupt
 lea rdi,[want_ref_line]
 mov esi,want_ref_line_len
 call packet_equal
 test eax,eax
 jz .fetch_want_ref
 cmp rcx,69
 jne .fetch_done_check
 cmp dword [rdx],0x746e6177      ; "want"
 jne .fetch_have_check
 cmp byte [rdx+4],' '
 jne .corrupt
 cmp byte [request_want_set],0
 jne .corrupt
 cmp byte [request_want_ref],0
 jne .corrupt
 cmp byte [request_have_count],0
 jne .corrupt
 lea rsi,[rdx+5]
 lea rdi,[request_want]
 mov ecx,32
.want_hex_byte:
 call hex_nibble
 jc .corrupt
 shl al,4
 mov bl,al
 call hex_nibble
 jc .corrupt
 or al,bl
 stosb
 loop .want_hex_byte
 cmp byte [rsi],10
 jne .corrupt
 mov byte [request_want_set],1
 jmp .argument
.fetch_have_check:
 cmp dword [rdx],0x65766168      ; "have"
 jne .fetch_done_check
 cmp byte [rdx+4],' '
 jne .corrupt
 cmp byte [request_want_set],1
 je .fetch_have_ready
 cmp byte [request_want_ref],1
 jne .corrupt
.fetch_have_ready:
 cmp byte [request_have_count],64
 jae .corrupt
 lea rsi,[rdx+5]
 movzx eax,byte [request_have_count]
 shl rax,5
 lea rdi,[request_have+rax]
 mov ecx,32
.have_hex_byte:
 call hex_nibble
 jc .corrupt
 shl al,4
 mov bl,al
 call hex_nibble
 jc .corrupt
 or al,bl
 stosb
 loop .have_hex_byte
 cmp byte [rsi],10
 jne .corrupt
 inc byte [request_have_count]
 jmp .argument
.fetch_want_ref:
 cmp byte [request_want_set],0
 jne .corrupt
 cmp byte [request_want_ref],0
 jne .corrupt
 cmp byte [request_have_count],0
 jne .corrupt
 mov byte [request_want_ref],1
 jmp .argument
.fetch_done_check:
 lea rdi,[done_line]
 mov esi,done_line_len
 call packet_equal
 test eax,eax
 jz .fetch_done
 lea rdi,[thin_pack_line]
 mov esi,thin_pack_line_len
 call packet_equal
 test eax,eax
 jz .argument
 lea rdi,[no_progress_line]
 mov esi,no_progress_line_len
 call packet_equal
 test eax,eax
 jz .argument
 lea rdi,[ofs_delta_line]
 mov esi,ofs_delta_line_len
 call packet_equal
 test eax,eax
 jz .argument
 lea rdi,[include_tag_line]
 mov esi,include_tag_line_len
 call packet_equal
 test eax,eax
 jz .argument
 lea rdi,[wait_done_line]
 mov esi,wait_done_line_len
 call packet_equal
 test eax,eax
 jnz .fetch_sideband_all_check
 cmp byte [request_wait_done],0
 jne .corrupt
 mov byte [request_wait_done],1
 jmp .argument
.fetch_sideband_all_check:
 lea rdi,[sideband_all_line]
 mov esi,sideband_all_line_len
 call packet_equal
 test eax,eax
 jnz .fetch_filter_check
 test qword [request_flags],32
 jnz .corrupt
 or qword [request_flags],32
 jmp .argument
.fetch_filter_check:
 lea rdi,[filter_blob_none_line]
 mov esi,filter_blob_none_line_len
 call packet_equal
 test eax,eax
 jz .fetch_filter_blob_none
 lea rdi,[filter_tree_zero_line]
 mov esi,filter_tree_zero_line_len
 call packet_equal
 test eax,eax
 jnz .corrupt
 test qword [request_flags],192
 jnz .corrupt
 or qword [request_flags],128
 jmp .argument
.fetch_filter_blob_none:
 test qword [request_flags],192
 jnz .corrupt
 or qword [request_flags],64
 jmp .argument
.fetch_done:
 mov byte [request_done],1
 jmp .argument
.ls_argument:
 lea rdi,[symrefs_line]
 mov esi,symrefs_line_len
 call packet_equal
 test eax,eax
 jz .ls_symrefs
 lea rdi,[peel_line]
 mov esi,peel_line_len
 call packet_equal
 test eax,eax
 jz .ls_peel
 lea rdi,[unborn_line]
 mov esi,unborn_line_len
 call packet_equal
 test eax,eax
 jz .ls_unborn
 call parse_ref_prefix
 test eax,eax
 jnz .corrupt
 jmp .argument
.ls_symrefs:
 test qword [request_flags],1
 jnz .corrupt
 or qword [request_flags],1
 jmp .argument
.ls_peel:
 cmp byte [request_peel],0
 jne .corrupt
 mov byte [request_peel],1
 jmp .argument
.ls_unborn:
 cmp byte [request_unborn],0
 jne .corrupt
 mov byte [request_unborn],1
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
 je .finish_want
 cmp byte [request_want_ref],1
 jne .corrupt
 xor ecx,ecx
 mov r8,[request_flags]
 or r8,16
 xor eax,eax
 jmp .done
.finish_want:
 lea rcx,[request_want]
 mov r8,[request_flags]
 xor eax,eax
 jmp .done
.finish_ls:
 xor ecx,ecx
 mov r8,[request_flags]
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

; Return the immutable have set from the most recent successful parse.
; RAX=32-byte record array, RDX=count (0..64).
git_protocol_v2_haves:
 lea rax,[request_have]
 movzx edx,byte [request_have_count]
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
 push rcx
 push rdx
 cmp rcx,rsi
 jne .not_equal
 mov rsi,rdx
 repe cmpsb
 jne .not_equal
 xor eax,eax
 jmp .equal_done
.not_equal:
 mov eax,1
.equal_done:
 pop rdx
 pop rcx
 ret

; Accept one printable, newline-terminated agent header and no other command
; header extensions. RDX/RCX are the current decoded packet payload.
validate_agent_header:
 cmp rcx,agent_prefix_len+2
 jb .agent_bad
 cmp rcx,256
 ja .agent_bad
 cmp byte [rdx+rcx-1],10
 jne .agent_bad
 push rdx
 push rcx
 mov rdi,rdx
 lea rsi,[agent_prefix]
 mov ecx,agent_prefix_len
 repe cmpsb
 pop rcx
 pop rdx
 jne .agent_bad
 lea rdi,[rdx+agent_prefix_len]
 sub rcx,agent_prefix_len+1
.agent_byte:
 mov al,[rdi]
 cmp al,32
 jb .agent_bad
 cmp al,126
 ja .agent_bad
 inc rdi
 loop .agent_byte
 xor eax,eax
 ret
.agent_bad:
 mov eax,VCS_ERR_CORRUPT
 ret

; Inspect the current RDX/RCX packet as a ref-prefix argument. The filter bit
; distinguishes an explicit filter that matches no exported refs from no filter.
parse_ref_prefix:
 cmp rcx,ref_prefix_marker_len+1
 jb .not_prefix
 cmp byte [rdx+rcx-1],10
 jne .not_prefix
 push rdx
 push rcx
 mov rdi,rdx
 lea rsi,[ref_prefix_marker]
 mov ecx,ref_prefix_marker_len
 repe cmpsb
 pop rcx
 pop rdx
 jne .not_prefix
 or qword [request_flags],8
 lea rdx,[rdx+ref_prefix_marker_len]
 sub rcx,ref_prefix_marker_len+1
 lea rdi,[head_ref]
 mov esi,head_ref_len
 call ref_has_prefix
 test eax,eax
 jz .check_main
 or qword [request_flags],2
.check_main:
 lea rdi,[main_ref]
 mov esi,main_ref_len
 call ref_has_prefix
 test eax,eax
 jz .prefix_done
 or qword [request_flags],4
.prefix_done:
 xor eax,eax
 ret
.not_prefix:
 mov eax,1
 ret

; RDI=ref, RSI=ref length, RDX=prefix, RCX=prefix length. EAX=1 on match.
ref_has_prefix:
 push rcx
 push rdx
 push rsi
 cmp rcx,rsi
 ja .prefix_no
 test rcx,rcx
 jz .prefix_yes
 mov rsi,rdx
 repe cmpsb
 jne .prefix_no
.prefix_yes:
 mov eax,1
 jmp .prefix_result
.prefix_no:
 xor eax,eax
.prefix_result:
 pop rsi
 pop rdx
 pop rcx
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
