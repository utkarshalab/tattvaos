; Bounded byte-oriented tools over the mounted UXFS volume.
%include "storage/uxfs/volume.inc"
bits 64
default rel
extern uxv_ready,uxv_nodes,uxv_cwd,fs_resolve,fs_path,fs_belongs
extern frontend_write,frontend_write_str,ush_streq,calc_format
section .bss
number: resb 67
row: resb 80
grep_found: resq 1
section .rodata
error: db 'ush: invalid arguments, unavailable volume, or invalid file/directory',10,0
nl: db 10,0
space: db ' ',0
type_file: db 'type: file',10,'size: ',0
type_dir: db 'type: directory',10,'size: ',0
bytes_path: db ' bytes',10,'path: ',0
bytes_nl: db ' bytes',10,0
records: db 'records: ',0
used: db ' used, ',0
free: db ' free, 64 total',10,'logical data: ',0
limit: db ' bytes',10,'file limit: 4096 bytes',10,0
dash_n: db '-n',0
digits: db '0123456789abcdef'
section .text
global cmd_stat,cmd_df,cmd_du,cmd_head,cmd_tail,cmd_wc,cmd_grep,cmd_find,cmd_hexdump
global ush_print_number,ush_parse_uint
cmd_stat: mov edx,0
 jmp tool
cmd_df: mov edx,1
 jmp tool
cmd_du: mov edx,2
 jmp tool
cmd_head: mov edx,3
 jmp tool
cmd_tail: mov edx,4
 jmp tool
cmd_wc: mov edx,5
 jmp tool
cmd_grep: mov edx,6
 jmp tool
cmd_find: mov edx,7
 jmp tool
cmd_hexdump: mov edx,8
 jmp tool
; Decimal unsigned integers, bounded to INT32_MAX. Empty/sign/overflow fail -1.
ush_parse_uint:
 xor eax,eax
 cmp byte [rdi],0
 je .bad
.digit:
 movzx edx,byte [rdi]
 test edx,edx
 jz .done
 sub edx,'0'
 cmp edx,9
 ja .bad
 imul rax,rax,10
 add rax,rdx
 cmp rax,0x7fffffff
 ja .bad
 inc rdi
 jmp .digit
.bad: mov rax,-1
.done: ret
ush_print_number:
 sub rsp,8
 mov esi,10
 lea rdx,[number]
 call calc_format
 lea rdi,[number]
 call frontend_write_str
 add rsp,8
 ret
tool:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdx
 mov r13,rsi
 mov r14,rdi
 mov r15,rdi
 cmp qword [uxv_ready],1
 jne .bad
 cmp r12,1
 je .df
 cmp r12,3
 je .line_arguments
 cmp r12,4
 je .line_arguments
 lea rdi,[uxv_cwd]
 cmp r14,1
 je .resolve
 mov rdi,[r13+8]
 cmp r12,6
 jne .resolve
 mov rdi,[r13+16]
 jmp .resolve
.line_arguments:
 mov r15d,10
 cmp r14,2
 je .simple_file
 cmp r14,4
 jne .bad
 mov rdi,[r13+8]
 lea rsi,[dash_n]
 call ush_streq
 test eax,eax
 jnz .bad
 mov rdi,[r13+16]
 call ush_parse_uint
 test rax,rax
 js .bad
 mov r15,rax
 mov rdi,[r13+24]
 jmp .resolve
.simple_file:
 mov rdi,[r13+8]
.resolve:
 call fs_resolve
 test rax,rax
 jz .bad
 mov r14,rax
 cmp r12,0
 je .stat
 cmp r12,2
 je .du
 cmp r12,7
 je .find
 cmp qword [r14+UV_TYPE],1
 jne .bad
 cmp r12,3
 je .head
 cmp r12,4
 je .tail
 cmp r12,5
 je .wc
 cmp r12,6
 je .grep
 jmp .hex
.stat:
 lea rdi,[type_file]
 cmp qword [r14+UV_TYPE],1
 je .type
 lea rdi,[type_dir]
.type:
 call frontend_write_str
 mov rdi,[r14+UV_SIZE]
 call ush_print_number
 lea rdi,[bytes_path]
 call frontend_write_str
 mov rdi,r14
 call frontend_write_str
 lea rdi,[nl]
 call frontend_write_str
 jmp .success
.df:
 xor r14d,r14d
 xor r15d,r15d
 lea rbx,[uxv_nodes]
.df_count:
 cmp qword [rbx+UV_TYPE],0
 je .df_next
 inc r14
 add r15,[rbx+UV_SIZE]
.df_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .df_count
 lea rdi,[records]
 call frontend_write_str
 mov rdi,r14
 call ush_print_number
 lea rdi,[used]
 call frontend_write_str
 mov edi,UV_NODES
 sub rdi,r14
 call ush_print_number
 lea rdi,[free]
 call frontend_write_str
 mov rdi,r15
 call ush_print_number
 lea rdi,[limit]
 call frontend_write_str
 jmp .success
.du:
 xor r15d,r15d
 lea rbx,[uxv_nodes]
.du_count:
 cmp qword [rbx+UV_TYPE],1
 jne .du_next
 mov rdi,rbx
 mov rsi,r14
 call fs_belongs
 test eax,eax
 jz .du_next
 add r15,[rbx+UV_SIZE]
.du_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .du_count
 mov rdi,r15
 call ush_print_number
 lea rdi,[bytes_nl]
 call frontend_write_str
 jmp .success
.head:
 xor esi,esi
 test r15,r15
 jz .slice
 lea rdi,[r14+UV_DATA]
.head_scan:
 cmp rsi,[r14+UV_SIZE]
 jae .slice
 mov al,[rdi+rsi]
 inc rsi
 cmp al,10
 jne .head_scan
 dec r15
 jnz .head_scan
 jmp .slice
.tail:
 mov rsi,[r14+UV_SIZE]
 mov rdx,rsi
 test r15,r15
 jz .tail_empty
 test rdx,rdx
 jz .slice
 lea rdi,[r14+UV_DATA]
 cmp byte [rdi+rdx-1],10
 jne .tail_scan
 dec rdx
.tail_scan:
 test rdx,rdx
 jz .slice
 dec rdx
 cmp byte [rdi+rdx],10
 jne .tail_scan
 dec r15
 jnz .tail_scan
 inc rdx
 sub rsi,rdx
 lea rdi,[rdi+rdx]
 call frontend_write
 jmp .success
.tail_empty:
 xor esi,esi
.slice:
 lea rdi,[r14+UV_DATA]
 call frontend_write
 jmp .success
.wc:
 xor r12d,r12d              ; newline count
 xor r13d,r13d              ; words
 xor r15d,r15d              ; inside a word
 xor ebx,ebx
.wc_scan:
 cmp rbx,[r14+UV_SIZE]
 jae .wc_print
 movzx eax,byte [r14+UV_DATA+rbx]
 inc rbx
 cmp al,10
 jne .wc_space
 inc r12
.wc_space:
 cmp al,32
 je .whitespace
 cmp al,9
 jb .word
 cmp al,13
 jbe .whitespace
.word:
 test r15,r15
 jnz .wc_scan
 inc r13
 mov r15d,1
 jmp .wc_scan
.whitespace:
 xor r15d,r15d
 jmp .wc_scan
.wc_print:
 mov rdi,r12
 call ush_print_number
 lea rdi,[space]
 call frontend_write_str
 mov rdi,r13
 call ush_print_number
 lea rdi,[space]
 call frontend_write_str
 mov rdi,rbx
 call ush_print_number
 lea rdi,[nl]
 call frontend_write_str
 jmp .success
.grep:
 mov qword [grep_found],0
 mov rdi,[r13+8]
 xor r12d,r12d
.pattern_length:
 cmp byte [rdi+r12],0
 je .grep_begin
 inc r12
 jmp .pattern_length
.grep_begin:
 xor ebx,ebx
.line:
 cmp rbx,[r14+UV_SIZE]
 jae .grep_done
 mov r15,rbx
.line_end:
 cmp r15,[r14+UV_SIZE]
 jae .search
 cmp byte [r14+UV_DATA+r15],10
 je .newline_end
 inc r15
 jmp .line_end
.newline_end:
 inc r15
.search:
 mov r11,r15
 cmp byte [r14+UV_DATA+r11-1],10
 jne .search_start
 dec r11
.search_start:
 mov r10,rbx
 mov r8,[r13+8]
.candidate:
 lea rax,[r10+r12]
 cmp rax,r11
 ja .line_next
 xor r9d,r9d
.match:
 cmp r9,r12
 jae .matched
 lea rax,[r10+r9]
 mov al,[r14+UV_DATA+rax]
 cmp al,[r8+r9]
 jne .mismatch
 inc r9
 jmp .match
.mismatch:
 inc r10
 jmp .candidate
.matched:
 mov qword [grep_found],1
 lea rdi,[r14+UV_DATA+rbx]
 mov rsi,r15
 sub rsi,rbx
 call frontend_write
.line_next:
 mov rbx,r15
 jmp .line
.grep_done:
 mov eax,1
 sub rax,[grep_found]
 jmp .done
.find:
 lea rbx,[uxv_nodes]
.find_record:
 cmp qword [rbx+UV_TYPE],0
 je .find_next
 mov rdi,rbx
 mov rsi,r14
 call fs_belongs
 test eax,eax
 jz .find_next
 cmp r15,3
 jne .find_print
 mov rdi,rbx
 cmp word [rdi],'/'
 je .basename_ready
 mov rdx,rbx
.basename:
 cmp byte [rdx],0
 je .basename_ready
 cmp byte [rdx],'/'
 jne .basename_next
 lea rdi,[rdx+1]
.basename_next:
 inc rdx
 jmp .basename
.basename_ready:
 mov rsi,[r13+16]
 call ush_streq
 test eax,eax
 jnz .find_next
.find_print:
 mov rdi,rbx
 call frontend_write_str
 lea rdi,[nl]
 call frontend_write_str
.find_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .find_record
 jmp .success
.hex:
 xor ebx,ebx
.hex_row:
 cmp rbx,[r14+UV_SIZE]
 jae .success
 lea rdi,[row]
 mov al,' '
 mov ecx,80
 rep stosb
 mov byte [row+59],'|'
 mov byte [row+76],'|'
 mov byte [row+77],10
 lea rdi,[row]
 lea r11,[digits]
 mov r8d,ebx
 mov ecx,8
.offset:
 mov eax,r8d
 shr eax,28
 mov al,[r11+rax]
 stosb
 shl r8d,4
 loop .offset
 mov r15,[r14+UV_SIZE]
 sub r15,rbx
 cmp r15,16
 jbe .hex_data
 mov r15d,16
.hex_data:
 lea r8,[r14+UV_DATA+rbx]
 lea r9,[row+10]
 lea r10,[row+60]
 xor ecx,ecx
.hex_byte:
 cmp rcx,r15
 jae .hex_print
 movzx eax,byte [r8+rcx]
 mov edx,eax
 shr eax,4
 mov al,[r11+rax]
 mov [r9],al
 and edx,15
 mov al,[r11+rdx]
 mov [r9+1],al
 mov al,[r8+rcx]
 cmp al,32
 jb .nonprint
 cmp al,126
 jbe .ascii
.nonprint: mov al,'.'
.ascii:
 mov [r10+rcx],al
 add r9,3
 inc ecx
 jmp .hex_byte
.hex_print:
 lea rdi,[row]
 mov esi,78
 call frontend_write
 add rbx,16
 jmp .hex_row
.bad:
 lea rdi,[error]
 call frontend_write_str
 mov eax,1
 cmp r12,6
 jne .done
 mov eax,2
 jmp .done
.success: xor eax,eax
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
