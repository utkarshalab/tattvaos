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
request_shallow: resb 32
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
request_server_options: resb 1
request_shallow_count: resb 1
request_filter_component: resb 64

section .rodata
ls_command: db 'command=ls-refs',10
ls_command_len equ $-ls_command
fetch_command: db 'command=fetch',10
fetch_command_len equ $-fetch_command
format_line: db 'object-format=sha256',10
format_line_len equ $-format_line
agent_prefix: db 'agent='
agent_prefix_len equ $-agent_prefix
server_option_prefix: db 'server-option='
server_option_prefix_len equ $-server_option_prefix
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
filter_tree_prefix: db 'filter tree:'
filter_tree_prefix_len equ $-filter_tree_prefix
filter_blob_limit_prefix: db 'filter blob:limit='
filter_blob_limit_prefix_len equ $-filter_blob_limit_prefix
filter_combine_prefix: db 'filter combine:'
filter_combine_prefix_len equ $-filter_combine_prefix
component_blob_none: db 'blob:none'
component_blob_none_len equ $-component_blob_none
component_tree: db 'tree:'
component_tree_len equ $-component_tree
component_blob_limit: db 'blob:limit='
component_blob_limit_len equ $-component_blob_limit
deepen_prefix: db 'deepen '
deepen_prefix_len equ $-deepen_prefix
shallow_prefix: db 'shallow '
shallow_prefix_len equ $-shallow_prefix
deepen_relative_line: db 'deepen-relative',10
deepen_relative_line_len equ $-deepen_relative_line
want_ref_main_line: db 'want-ref refs/heads/main',10
want_ref_main_line_len equ $-want_ref_main_line
want_ref_head_line: db 'want-ref HEAD',10
want_ref_head_line_len equ $-want_ref_head_line
ref_prefix_marker: db 'ref-prefix '
ref_prefix_marker_len equ $-ref_prefix_marker
head_ref: db 'HEAD'
head_ref_len equ $-head_ref
main_ref: db 'refs/heads/main'
main_ref_len equ $-main_ref

section .text
global git_protocol_v2_parse_request,git_protocol_v2_haves
global git_protocol_v2_shallow
; RDI=complete request, RSI=length.
; RAX=status, RDX=operation, RCX=32-byte wanted OID or zero for ls-refs,
; R8 flags: ls-refs bits 0..3; fetch bit 4 want-ref, bit 5 sideband-all,
; bit 6 blob:none, bit 7 tree filter, bit 8 deepen, bit 9 blob:limit,
; bit 10 deepen-relative, bit 11 want-ref HEAD, bit 12 want-ref main;
; history depth is at bits 16..23, tree depth at bits 24..31, and the blob
; limit at bits 32..48.
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
 mov byte [request_server_options],0
 mov byte [request_shallow_count],0
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
 jnz .server_option_header
 cmp byte [request_agent],0
 jne .corrupt
 mov byte [request_agent],1
 jmp .headers
.server_option_header:
 call validate_server_option_header
 test eax,eax
 jnz .corrupt
 cmp byte [request_server_options],8
 jae .corrupt
 inc byte [request_server_options]
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
 lea rdi,[want_ref_main_line]
 mov esi,want_ref_main_line_len
 call packet_equal
 test eax,eax
 jz .fetch_want_ref_main
 lea rdi,[want_ref_head_line]
 mov esi,want_ref_head_line_len
 call packet_equal
 test eax,eax
 jz .fetch_want_ref_head
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
 cmp byte [request_want_ref],0
 je .corrupt
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
.fetch_want_ref_head:
 test qword [request_flags],2048
 jnz .corrupt
 or qword [request_flags],2048
 jmp .fetch_want_ref
.fetch_want_ref_main:
 test qword [request_flags],4096
 jnz .corrupt
 or qword [request_flags],4096
.fetch_want_ref:
 cmp byte [request_want_set],0
 jne .corrupt
 cmp byte [request_have_count],0
 jne .corrupt
 cmp byte [request_want_ref],2
 jae .corrupt
 inc byte [request_want_ref]
 jmp .argument
.fetch_done_check:
 call parse_shallow
 test eax,eax
 jz .argument
 cmp eax,1
 jne .corrupt
 call parse_deepen
 test eax,eax
 jz .argument
 cmp eax,1
 jne .corrupt
 lea rdi,[deepen_relative_line]
 mov esi,deepen_relative_line_len
 call packet_equal
 test eax,eax
 jnz .fetch_done_line
 test qword [request_flags],1024
 jnz .corrupt
 or qword [request_flags],1024
 jmp .argument
.fetch_done_line:
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
 call parse_combine_filter
 test eax,eax
 jz .argument
 cmp eax,1
 jne .corrupt
 lea rdi,[filter_blob_none_line]
 mov esi,filter_blob_none_line_len
 call packet_equal
 test eax,eax
 jz .fetch_filter_blob_none
 call parse_tree_filter
 test eax,eax
 jz .argument
 cmp eax,1
 jne .corrupt
.fetch_filter_blob_limit:
 call parse_blob_limit
 test eax,eax
 jnz .corrupt
 jmp .argument
.fetch_filter_blob_none:
 test qword [request_flags],704
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
 test qword [request_flags],1024
 jz .finish_shallow_state
 test qword [request_flags],256
 jz .corrupt
 cmp byte [request_shallow_count],1
 jne .corrupt
 jmp .finish_fetch_ready
.finish_shallow_state:
 cmp byte [request_shallow_count],0
 je .finish_fetch_ready
 test qword [request_flags],256
 jz .corrupt
.finish_fetch_ready:
 cmp byte [request_want_set],1
 je .finish_want
 cmp byte [request_want_ref],0
 je .corrupt
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

; Return the single client shallow boundary from the most recent parse.
; RAX=32-byte OID or null, RDX=count (0 or 1).
git_protocol_v2_shallow:
 movzx edx,byte [request_shallow_count]
 xor eax,eax
 test edx,edx
 jz .shallow_done
 lea rax,[request_shallow]
.shallow_done:
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

; Accept one advertised server-option capability with 1..128 value bytes.
; NUL and embedded LF are forbidden; the packet's final LF is framing.
validate_server_option_header:
 cmp rcx,server_option_prefix_len+2
 jb .option_bad
 cmp rcx,server_option_prefix_len+129
 ja .option_bad
 cmp byte [rdx+rcx-1],10
 jne .option_bad
 push rdx
 push rcx
 mov rdi,rdx
 lea rsi,[server_option_prefix]
 mov ecx,server_option_prefix_len
 repe cmpsb
 pop rcx
 pop rdx
 jne .option_bad
 lea rdi,[rdx+server_option_prefix_len]
 sub rcx,server_option_prefix_len+1
.option_byte:
 mov al,[rdi]
 test al,al
 jz .option_bad
 cmp al,10
 je .option_bad
 inc rdi
 loop .option_byte
 xor eax,eax
 ret
.option_bad:
 mov eax,VCS_ERR_CORRUPT
 ret

; Parse `deepen N\n`, where N is 1..255. EAX=1 means not this argument.
parse_deepen:
 cmp rcx,deepen_prefix_len+2
 jb .deepen_not
 push rdx
 push rcx
 mov rdi,rdx
 lea rsi,[deepen_prefix]
 mov ecx,deepen_prefix_len
 repe cmpsb
 pop rcx
 pop rdx
 jne .deepen_not
 test qword [request_flags],256
 jnz .deepen_bad
 cmp byte [rdx+rcx-1],10
 jne .deepen_bad
 lea rsi,[rdx+deepen_prefix_len]
 sub rcx,deepen_prefix_len+1
 test rcx,rcx
 jz .deepen_bad
 cmp rcx,3
 ja .deepen_bad
 xor eax,eax
.deepen_digit:
 movzx edx,byte [rsi]
 cmp dl,'0'
 jb .deepen_bad
 cmp dl,'9'
 ja .deepen_bad
 imul eax,eax,10
 sub dl,'0'
 movzx edx,dl
 add eax,edx
 inc rsi
 loop .deepen_digit
 test eax,eax
 jz .deepen_bad
 cmp eax,255
 ja .deepen_bad
 mov rdx,rax
 shl rdx,16
 or rdx,256
 or qword [request_flags],rdx
 xor eax,eax
 ret
.deepen_not:
 mov eax,1
 ret
.deepen_bad:
 mov eax,VCS_ERR_CORRUPT
 ret

; Parse one `shallow <64-hex>\n` declaration. EAX=1 means not this argument.
parse_shallow:
 cmp rcx,shallow_prefix_len+64+1
 jne .shallow_not
 push rdx
 push rcx
 mov rdi,rdx
 lea rsi,[shallow_prefix]
 mov ecx,shallow_prefix_len
 repe cmpsb
 pop rcx
 pop rdx
 jne .shallow_not
 cmp byte [request_shallow_count],0
 jne .shallow_bad
 cmp byte [rdx+rcx-1],10
 jne .shallow_bad
 lea rsi,[rdx+shallow_prefix_len]
 lea rdi,[request_shallow]
 mov ecx,32
.shallow_hex_byte:
 call hex_nibble
 jc .shallow_bad
 shl al,4
 mov bl,al
 call hex_nibble
 jc .shallow_bad
 or al,bl
 stosb
 loop .shallow_hex_byte
 cmp byte [rsi],10
 jne .shallow_bad
 mov byte [request_shallow_count],1
 xor eax,eax
 ret
.shallow_not:
 mov eax,1
 ret
.shallow_bad:
 mov eax,VCS_ERR_CORRUPT
 ret

; Parse `filter blob:limit=N[kmg]\n`; scaled values saturate at 65536.
parse_blob_limit:
 cmp rcx,filter_blob_limit_prefix_len+2
 jb .limit_bad
 push rdx
 push rcx
 mov rdi,rdx
 lea rsi,[filter_blob_limit_prefix]
 mov ecx,filter_blob_limit_prefix_len
 repe cmpsb
 pop rcx
 pop rdx
 jne .limit_bad
 test qword [request_flags],704
 jnz .limit_bad
 cmp byte [rdx+rcx-1],10
 jne .limit_bad
 lea rsi,[rdx+filter_blob_limit_prefix_len]
 sub rcx,filter_blob_limit_prefix_len+1
 test rcx,rcx
 jz .limit_bad
 xor r8d,r8d
 mov dl,[rsi+rcx-1]
 or dl,32
 cmp dl,'k'
 je .limit_k
 cmp dl,'m'
 je .limit_m
 cmp dl,'g'
 je .limit_g
 jmp .limit_digits_ready
.limit_k:
 mov r8d,10
 jmp .limit_suffix
.limit_m:
 mov r8d,20
 jmp .limit_suffix
.limit_g:
 mov r8d,30
.limit_suffix:
 dec rcx
 jz .limit_bad
.limit_digits_ready:
 cmp rcx,10
 ja .limit_bad
 xor eax,eax
.limit_digit:
 movzx edx,byte [rsi]
 cmp dl,'0'
 jb .limit_bad
 cmp dl,'9'
 ja .limit_bad
 cmp rax,65536
 jae .limit_next
 imul rax,rax,10
 sub dl,'0'
 movzx edx,dl
 add rax,rdx
 cmp rax,65536
 jbe .limit_next
 mov eax,65536
.limit_next:
 inc rsi
 loop .limit_digit
 cmp rax,65536
 jae .limit_store
 mov ecx,r8d
 shl rax,cl
 cmp rax,65536
 jbe .limit_store
 mov eax,65536
.limit_store:
 mov rdx,rax
 shl rdx,32
 or rdx,512
 or qword [request_flags],rdx
 xor eax,eax
 ret
.limit_bad:
 mov eax,VCS_ERR_CORRUPT
 ret

; Parse `filter tree:N\n`, where the exclusive depth N is in 0..255.
; EAX=1 means that the packet is not a tree filter.
parse_tree_filter:
 cmp rcx,filter_tree_prefix_len+2
 jb .tree_not
 push rdx
 push rcx
 mov rdi,rdx
 lea rsi,[filter_tree_prefix]
 mov ecx,filter_tree_prefix_len
 repe cmpsb
 pop rcx
 pop rdx
 jne .tree_not
 test qword [request_flags],704
 jnz .tree_bad
 cmp byte [rdx+rcx-1],10
 jne .tree_bad
 lea rsi,[rdx+filter_tree_prefix_len]
 sub rcx,filter_tree_prefix_len+1
 test rcx,rcx
 jz .tree_bad
 cmp rcx,3
 ja .tree_bad
 xor eax,eax
.tree_digit:
 movzx edx,byte [rsi]
 cmp dl,'0'
 jb .tree_bad
 cmp dl,'9'
 ja .tree_bad
 imul eax,eax,10
 sub dl,'0'
 movzx edx,dl
 add eax,edx
 cmp eax,255
 ja .tree_bad
 inc rsi
 loop .tree_digit
 mov edx,eax
 shl rdx,24
 or rdx,128
 or [request_flags],rdx
 xor eax,eax
 ret
.tree_not:
 mov eax,1
 ret
.tree_bad:
 mov eax,VCS_ERR_CORRUPT
 ret

; Parse `filter combine:<part>+<part>[+<part>]\n`. Supported components are
; the bounded blob:none, blob:limit, and tree filters. Components are decoded
; from Git's percent encoding before validation. EAX=1 means not a combine.
parse_combine_filter:
 cmp rcx,filter_combine_prefix_len+4
 jb .combine_not
 push rdx
 push rcx
 mov rdi,rdx
 lea rsi,[filter_combine_prefix]
 mov ecx,filter_combine_prefix_len
 repe cmpsb
 pop rcx
 pop rdx
 jne .combine_not
 test qword [request_flags],704
 jnz .combine_bad
 cmp byte [rdx+rcx-1],10
 jne .combine_bad
 push r12
 push r13
 push r14
 mov r12,rdx
 add r12,filter_combine_prefix_len
 lea r13,[rdx+rcx-1]
 xor r14d,r14d
.combine_part:
 cmp r12,r13
 jae .combine_bad_saved
 cmp r14,3
 jae .combine_bad_saved
 mov rdi,r12
.combine_scan:
 cmp rdi,r13
 jae .combine_part_ready
 cmp byte [rdi],'+'
 je .combine_part_ready
 inc rdi
 jmp .combine_scan
.combine_part_ready:
 mov rsi,rdi
 sub rsi,r12
 test rsi,rsi
 jz .combine_bad_saved
 push rdi
 mov rdi,r12
 call decode_filter_component
 test eax,eax
 jnz .combine_bad_separator
 call parse_filter_component
.combine_bad_separator:
 pop rdi
 test eax,eax
 jnz .combine_bad_saved
 inc r14
 cmp rdi,r13
 jae .combine_finish
 lea r12,[rdi+1]
 jmp .combine_part
.combine_finish:
 cmp r14,2
 jb .combine_bad_saved
 pop r14
 pop r13
 pop r12
 xor eax,eax
 ret
.combine_bad_saved:
 pop r14
 pop r13
 pop r12
.combine_bad:
 mov eax,VCS_ERR_CORRUPT
 ret
.combine_not:
 mov eax,1
 ret

; RDI=component, RSI=length. Apply one unique supported component.
parse_filter_component:
 push r12
 push r13
 push r14
 push r15
 mov r12,rdi
 mov r13,rsi
 lea rdi,[component_blob_none]
 mov esi,component_blob_none_len
 call component_equal
 test eax,eax
 jz .component_blob_none
 lea rdi,[component_tree]
 mov esi,component_tree_len
 call component_prefix
 test eax,eax
 jz .component_tree_raw
 lea rdi,[component_blob_limit]
 mov esi,component_blob_limit_len
 call component_prefix
 test eax,eax
 jz .component_limit_raw
 jmp .component_bad
.component_blob_none:
 test qword [request_flags],64
 jnz .component_bad
 or qword [request_flags],64
 jmp .component_ok
.component_tree_raw:
 mov r14,component_tree_len
.component_tree:
 test qword [request_flags],128
 jnz .component_bad
 mov r15,r13
 sub r15,r14
 test r15,r15
 jz .component_bad
 cmp r15,3
 ja .component_bad
 lea rsi,[r12+r14]
 xor eax,eax
.component_tree_digit:
 movzx edx,byte [rsi]
 cmp dl,'0'
 jb .component_bad
 cmp dl,'9'
 ja .component_bad
 imul eax,eax,10
 sub dl,'0'
 movzx edx,dl
 add eax,edx
 cmp eax,255
 ja .component_bad
 inc rsi
 dec r15
 jnz .component_tree_digit
 mov edx,eax
 shl rdx,24
 or rdx,128
 or qword [request_flags],rdx
 jmp .component_ok
.component_limit_raw:
 mov r14,component_blob_limit_len
.component_limit:
 test qword [request_flags],512
 jnz .component_bad
 mov r15,r13
 sub r15,r14
 test r15,r15
 jz .component_bad
 lea rsi,[r12+r14]
 xor r8d,r8d
 mov dl,[rsi+r15-1]
 or dl,32
 cmp dl,'k'
 je .component_limit_k
 cmp dl,'m'
 je .component_limit_m
 cmp dl,'g'
 je .component_limit_g
 jmp .component_limit_digits
.component_limit_k:
 mov r8d,10
 jmp .component_limit_suffix
.component_limit_m:
 mov r8d,20
 jmp .component_limit_suffix
.component_limit_g:
 mov r8d,30
.component_limit_suffix:
 dec r15
 jz .component_bad
.component_limit_digits:
 cmp r15,10
 ja .component_bad
 xor eax,eax
 mov rcx,r15
.component_limit_digit:
 movzx edx,byte [rsi]
 cmp dl,'0'
 jb .component_bad
 cmp dl,'9'
 ja .component_bad
 cmp rax,65536
 jae .component_limit_next
 imul rax,rax,10
 sub dl,'0'
 movzx edx,dl
 add rax,rdx
 cmp rax,65536
 jbe .component_limit_next
 mov eax,65536
.component_limit_next:
 inc rsi
 loop .component_limit_digit
 cmp rax,65536
 jae .component_limit_store
 mov ecx,r8d
 shl rax,cl
 cmp rax,65536
 jbe .component_limit_store
 mov eax,65536
.component_limit_store:
 mov rdx,rax
 shl rdx,32
 or rdx,512
 or qword [request_flags],rdx
.component_ok:
 xor eax,eax
 jmp .component_done
.component_bad:
 mov eax,VCS_ERR_CORRUPT
.component_done:
 pop r15
 pop r14
 pop r13
 pop r12
 ret

; Compare the saved R12/R13 component with RDI/RSI.
component_equal:
 cmp r13,rsi
 jne component_not_equal
 jmp component_compare
component_prefix:
 cmp r13,rsi
 jb component_not_equal
component_compare:
 mov rcx,rsi
 mov rsi,r12
 repe cmpsb
 jne component_not_equal
 xor eax,eax
 ret
component_not_equal:
 mov eax,1
 ret

; Decode one bounded percent-encoded combine component.
; RDI=input, RSI=length -> RDI=scratch, RSI=decoded length, RAX=status.
decode_filter_component:
 test rsi,rsi
 jz .decode_component_bad
 cmp rsi,64
 ja .decode_component_bad
 mov r8,rdi
 mov r9,rsi
 lea r10,[request_filter_component]
 mov r11,r10
.decode_component_byte:
 test r9,r9
 jz .decode_component_done
 mov al,[r8]
 cmp al,'%'
 jne .decode_component_store
 cmp r9,3
 jb .decode_component_bad
 mov al,[r8+1]
 call filter_hex_nibble
 jc .decode_component_bad
 shl al,4
 mov dl,al
 mov al,[r8+2]
 call filter_hex_nibble
 jc .decode_component_bad
 or al,dl
 add r8,3
 sub r9,3
 jmp .decode_component_value
.decode_component_store:
 inc r8
 dec r9
.decode_component_value:
 test al,al
 jz .decode_component_bad
 mov [r11],al
 inc r11
 jmp .decode_component_byte
.decode_component_done:
 lea rdi,[request_filter_component]
 mov rsi,r11
 sub rsi,rdi
 xor eax,eax
 ret
.decode_component_bad:
 mov eax,VCS_ERR_CORRUPT
 ret

; AL=hex digit, returns AL=value and CF on invalid input.
filter_hex_nibble:
 cmp al,'0'
 jb .filter_hex_bad
 cmp al,'9'
 jbe .filter_hex_number
 or al,32
 cmp al,'a'
 jb .filter_hex_bad
 cmp al,'f'
 ja .filter_hex_bad
 sub al,'a'-10
 clc
 ret
.filter_hex_number:
 sub al,'0'
 clc
 ret
.filter_hex_bad:
 stc
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
