; Allocation-free Git packet-line and fast-import export boundary.
%include "include/vcs.inc"
%include "include/wire.inc"
%include "include/repository.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel

extern vcs_load_manifest,vcs_object_name,vcs_object_path
extern vcs_repo_discover,vcs_repo_root,vcs_repo_root_size,vcs_repo_head
extern vcs_history,vcs_history_signed,vcs_checkout
extern uxv_find,uxv_free,uxv_normalize,uxv_nodes

section .bss
export_cursor: resq 1
export_left: resq 1
export_start: resq 1
decimal: resb 20
import_cursor: resq 1
import_end: resq 1
import_writer: resq 1
import_seed: resq 1
import_count: resq 1
import_blob_ptr: resq VR_FILES
import_blob_len: resq VR_FILES
import_nodes: resq VR_FILES
import_new: resb VR_FILES
import_paths: resb VR_FILES*VR_PATH
import_message: resb 216
import_absolute: resb 240
import_canonical: resb 240
import_mark_base: resq 1
import_previous_head: resq 1
history_ids: resq UV_NODES
history_count: resq 1
history_mark: resq 1

section .rodata
hex: db '0123456789abcdef'
blob_line: db 'blob',10
blob_line_len equ $-blob_line
mark_line: db 'mark :'
mark_line_len equ $-mark_line
data_line: db 'data '
data_line_len equ $-data_line
commit_line: db 'commit refs/heads/main',10
commit_line_len equ $-commit_line
identity_line: db 'author Tattva VCS <vcs@tattva.local> 0 +0000',10,'committer Tattva VCS <vcs@tattva.local> 0 +0000',10
identity_line_len equ $-identity_line
deleteall_line: db 'deleteall',10
deleteall_line_len equ $-deleteall_line
modify_line: db 'M 100644 :'
modify_line_len equ $-modify_line
done_line: db 'done',10
done_line_len equ $-done_line
newline: db 10
author_prefix: db 'author '
author_prefix_len equ $-author_prefix
committer_prefix: db 'committer '
committer_prefix_len equ $-committer_prefix

section .text
global bridge_pkt_encode,bridge_pkt_decode
global bridge_git_import,bridge_git_export,bridge_git_export_history,bridge_git_serve

; Encode one Git pkt-line.
; rdi=payload, rsi=length, rdx=output, rcx=capacity
; rax=status, rdx=encoded length.
bridge_pkt_encode:
 test rdi,rdi
 jz .encode_usage
 test rdx,rdx
 jz .encode_usage
 cmp rsi,65515                 ; 0xffff minus four-byte prefix
 ja .encode_usage
 lea r8,[rsi+4]
 cmp rcx,r8
 jb .encode_space
 mov r9,rdi
 mov r10,rdx
 mov rax,r8
 lea r11,[rel hex]
 mov ecx,4
.digit:
 rol ax,4
 movzx edi,al
 and edi,15
 mov dil,[r11+rdi]
 mov [r10],dil
 inc r10
 loop .digit
 mov rdi,r10
 mov rsi,r9
 mov rcx,r8
 sub rcx,4
 rep movsb
 mov rdx,r8
 xor eax,eax
 ret
.encode_space:
 mov eax,VCS_ERR_NO_MEM
 ret
.encode_usage:
 mov eax,VCS_ERR_USAGE
 ret

; Decode one complete Git pkt-line.
; rdi=input, rsi=available bytes
; rax=status, rdx=payload pointer, rcx=payload length, r8=consumed bytes.
; Flush packet 0000 succeeds with a zero payload/length and consumes four.
bridge_pkt_decode:
 test rdi,rdi
 jz .decode_usage
 cmp rsi,4
 jb .decode_again
 xor eax,eax
 xor ecx,ecx
.nibble:
 movzx edx,byte [rdi+rcx]
 cmp dl,'0'
 jb .decode_corrupt
 cmp dl,'9'
 jbe .number
 or dl,32
 cmp dl,'a'
 jb .decode_corrupt
 cmp dl,'f'
 ja .decode_corrupt
 sub dl,'a'-10
 jmp .add
.number:
 sub dl,'0'
.add:
 shl eax,4
 or al,dl
 inc ecx
 cmp ecx,4
 jb .nibble
 test eax,eax
 jz .flush
 cmp eax,2
 jbe .special
 cmp eax,4
 jb .decode_corrupt
 cmp rax,rsi
 ja .decode_again
 mov r8,rax
 lea rdx,[rdi+4]
 lea rcx,[rax-4]
 xor eax,eax
 ret
.flush:
 xor edx,edx
 xor ecx,ecx
 mov r8d,4
 xor r9d,r9d
 xor eax,eax
 ret
.special:
 xor edx,edx
 xor ecx,ecx
 mov r8d,4
 mov r9,rax
 xor eax,eax
 ret
.decode_again:
 mov eax,VCS_XFER_AGAIN
 ret
.decode_corrupt:
 mov eax,VCS_ERR_CORRUPT
 ret
.decode_usage:
 mov eax,VCS_ERR_USAGE
 ret

; Export one validated snapshot as a Git fast-import stream.
; rdi=commit ID, rsi=output, rdx=capacity -> rax=status, rdx=bytes.
; Every file receives a mark, followed by one snapshot commit on main.
bridge_git_export:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .export_usage
 test rsi,rsi
 jz .export_usage
 mov [export_start],rsi
 mov [export_cursor],rsi
 mov [export_left],rdx
 call vcs_load_manifest
 test rax,rax
 jz .export_corrupt
 mov rbp,rax
 mov r12,[rbp+24]
 xor r13d,r13d
.export_blob:
 cmp r13,r12
 jae .export_commit
 mov r14,r13
 shl r14,8
 add r14,rbp
 add r14,VR_HEADER
 lea rdi,[blob_line]
 mov esi,blob_line_len
 call append
 test eax,eax
 jnz .export_done
 lea rdi,[mark_line]
 mov esi,mark_line_len
 call append
 test eax,eax
 jnz .export_done
 lea rdi,[r13+1]
 call append_decimal
 test eax,eax
 jnz .export_done
 call append_newline
 test eax,eax
 jnz .export_done
 lea rdi,[data_line]
 mov esi,data_line_len
 call append
 test eax,eax
 jnz .export_done
 mov rdi,[r14+VR_SIZE]
 call append_decimal
 test eax,eax
 jnz .export_done
 call append_newline
 test eax,eax
 jnz .export_done
 mov rdi,[r14+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz .export_corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .export_corrupt
 cmp qword [rax+UV_TYPE],1
 jne .export_corrupt
 mov rsi,[r14+VR_SIZE]
 cmp [rax+UV_SIZE],rsi
 jne .export_corrupt
 lea rdi,[rax+UV_DATA]
 call append
 test eax,eax
 jnz .export_done
 call append_newline
 test eax,eax
 jnz .export_done
 inc r13
 jmp .export_blob
.export_commit:
 lea rdi,[commit_line]
 mov esi,commit_line_len
 call append
 test eax,eax
 jnz .export_done
 lea rdi,[mark_line]
 mov esi,mark_line_len
 call append
 test eax,eax
 jnz .export_done
 lea rdi,[r12+1]
 call append_decimal
 test eax,eax
 jnz .export_done
 call append_newline
 test eax,eax
 jnz .export_done
 lea rdi,[identity_line]
 mov esi,identity_line_len
 call append
 test eax,eax
 jnz .export_done
 lea rdi,[data_line]
 mov esi,data_line_len
 call append
 test eax,eax
 jnz .export_done
 mov r15,[rbp+32]
 btr r15,63
 mov rdi,r15
 call append_decimal
 test eax,eax
 jnz .export_done
 call append_newline
 test eax,eax
 jnz .export_done
 lea rdi,[rbp+VR_MESSAGE]
 mov rsi,r15
 call append
 test eax,eax
 jnz .export_done
 call append_newline
 test eax,eax
 jnz .export_done
 lea rdi,[deleteall_line]
 mov esi,deleteall_line_len
 call append
 test eax,eax
 jnz .export_done
 xor r13d,r13d
.export_entry:
 cmp r13,r12
 jae .export_finish
 mov r14,r13
 shl r14,8
 add r14,rbp
 add r14,VR_HEADER
 lea rdi,[modify_line]
 mov esi,modify_line_len
 call append
 test eax,eax
 jnz .export_done
 lea rdi,[r13+1]
 call append_decimal
 test eax,eax
 jnz .export_done
 mov al,' '
 call append_byte
 test eax,eax
 jnz .export_done
 mov rdi,r14
 call append_quoted_path
 test eax,eax
 jnz .export_done
 call append_newline
 test eax,eax
 jnz .export_done
 inc r13
 jmp .export_entry
.export_finish:
 lea rdi,[done_line]
 mov esi,done_line_len
 call append
 test eax,eax
 jnz .export_done
 mov rdx,[export_cursor]
 sub rdx,[export_start]
 xor eax,eax
 jmp .export_done
.export_usage: mov eax,VCS_ERR_USAGE
 jmp .export_done
.export_corrupt: mov eax,VCS_ERR_CORRUPT
.export_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Export the complete bounded first-parent history ending at RDI.
; RSI=output, RDX=capacity -> RAX=status, RDX=bytes.
bridge_git_export_history:
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
 mov [export_start],rsi
 mov [export_cursor],rsi
 mov [export_left],rdx
 mov qword [history_count],0
 mov qword [history_mark],0
 mov r12,rdi
.collect:
 mov rax,[history_count]
 cmp rax,UV_NODES
 jae .capacity
 lea rdx,[history_ids]
 mov [rdx+rax*8],r12
 inc qword [history_count]
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r12,[rax+16]
 test r12,r12
 jnz .collect
 mov r13,[history_count]
.emit_commit:
 test r13,r13
 jz .finish
 dec r13
 lea rax,[history_ids]
 mov rdi,[rax+r13*8]
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rdi,rax
 call export_history_manifest
 test eax,eax
 jnz .done
 jmp .emit_commit
.finish:
 lea rdi,[done_line]
 mov esi,done_line_len
 call append
 test eax,eax
 jnz .done
 mov rdx,[export_cursor]
 sub rdx,[export_start]
 xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.capacity: mov eax,VCS_ERR_NO_MEM
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

; RDI=validated manifest. Emit blobs and one sequential branch commit.
export_history_manifest:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 mov r12,[rbp+24]
 xor r13d,r13d
.blob:
 cmp r13,r12
 jae .commit
 mov r14,r13
 shl r14,8
 add r14,rbp
 add r14,VR_HEADER
 lea rdi,[blob_line]
 mov esi,blob_line_len
 call append
 test eax,eax
 jnz .done
 lea rdi,[mark_line]
 mov esi,mark_line_len
 call append
 test eax,eax
 jnz .done
 mov rdi,[history_mark]
 add rdi,r13
 inc rdi
 call append_decimal
 test eax,eax
 jnz .done
 call append_newline
 test eax,eax
 jnz .done
 lea rdi,[data_line]
 mov esi,data_line_len
 call append
 test eax,eax
 jnz .done
 mov rdi,[r14+VR_SIZE]
 call append_decimal
 test eax,eax
 jnz .done
 call append_newline
 test eax,eax
 jnz .done
 mov rdi,[r14+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz .corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 mov rsi,[r14+VR_SIZE]
 cmp [rax+UV_SIZE],rsi
 jne .corrupt
 lea rdi,[rax+UV_DATA]
 call append
 test eax,eax
 jnz .done
 call append_newline
 test eax,eax
 jnz .done
 inc r13
 jmp .blob
.commit:
 lea rdi,[commit_line]
 mov esi,commit_line_len
 call append
 test eax,eax
 jnz .done
 lea rdi,[mark_line]
 mov esi,mark_line_len
 call append
 test eax,eax
 jnz .done
 mov rdi,[history_mark]
 add rdi,r12
 inc rdi
 call append_decimal
 test eax,eax
 jnz .done
 call append_newline
 test eax,eax
 jnz .done
 lea rdi,[identity_line]
 mov esi,identity_line_len
 call append
 test eax,eax
 jnz .done
 lea rdi,[data_line]
 mov esi,data_line_len
 call append
 test eax,eax
 jnz .done
 mov r15,[rbp+32]
 btr r15,63
 mov rdi,r15
 call append_decimal
 test eax,eax
 jnz .done
 call append_newline
 test eax,eax
 jnz .done
 lea rdi,[rbp+VR_MESSAGE]
 mov rsi,r15
 call append
 test eax,eax
 jnz .done
 call append_newline
 test eax,eax
 jnz .done
 lea rdi,[deleteall_line]
 mov esi,deleteall_line_len
 call append
 test eax,eax
 jnz .done
 xor r13d,r13d
.entry:
 cmp r13,r12
 jae .ok
 mov r14,r13
 shl r14,8
 add r14,rbp
 add r14,VR_HEADER
 lea rdi,[modify_line]
 mov esi,modify_line_len
 call append
 test eax,eax
 jnz .done
 mov rdi,[history_mark]
 add rdi,r13
 inc rdi
 call append_decimal
 test eax,eax
 jnz .done
 mov al,' '
 call append_byte
 test eax,eax
 jnz .done
 mov rdi,r14
 call append_quoted_path
 test eax,eax
 jnz .done
 call append_newline
 test eax,eax
 jnz .done
 inc r13
 jmp .entry
.ok:
 mov rax,r12
 inc rax
 add [history_mark],rax
 xor eax,eax
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

append:
 mov rcx,[export_left]
 cmp rcx,rsi
 jb .space
 mov r8,rsi
 mov rdx,rdi
 mov rdi,[export_cursor]
 mov rcx,rsi
 mov rsi,rdx
 rep movsb
 mov [export_cursor],rdi
 sub [export_left],r8
 xor eax,eax
 ret
.space: mov eax,VCS_ERR_NO_MEM
 ret

append_byte:
 mov [decimal],al
 lea rdi,[decimal]
 mov esi,1
 jmp append

append_newline:
 lea rdi,[newline]
 mov esi,1
 jmp append

append_decimal:
 sub rsp,8
 lea r8,[decimal+20]
 mov rax,rdi
 xor ecx,ecx
.decimal_digit:
 xor edx,edx
 mov edi,10
 div rdi
 add dl,'0'
 dec r8
 mov [r8],dl
 inc ecx
 test rax,rax
 jnz .decimal_digit
 mov rdi,r8
 mov rsi,rcx
 call append
 add rsp,8
 ret

; Git C-style quoted path with unsafe bytes encoded as three-digit octal.
append_quoted_path:
 push rbx
 push r12
 sub rsp,8
 mov r12,rdi
 mov al,'"'
 call append_byte
 test eax,eax
 jnz .path_done
 xor ebx,ebx
.path_byte:
 cmp rbx,VR_PATH
 jae .path_bad
 movzx eax,byte [r12+rbx]
 test al,al
 jz .path_close
 cmp al,33
 jb .path_escape
 cmp al,126
 ja .path_escape
 cmp al,'"'
 je .path_escape
 cmp al,92
 je .path_escape
 call append_byte
 test eax,eax
 jnz .path_done
 inc rbx
 jmp .path_byte
.path_escape:
 mov dl,al
 mov byte [decimal],92
 mov al,dl
 shr al,6
 and al,3
 add al,'0'
 mov [decimal+1],al
 mov al,dl
 shr al,3
 and al,7
 add al,'0'
 mov [decimal+2],al
 mov al,dl
 and al,7
 add al,'0'
 mov [decimal+3],al
 lea rdi,[decimal]
 mov esi,4
 call append
 test eax,eax
 jnz .path_done
 inc rbx
 jmp .path_byte
.path_close:
 mov al,'"'
 call append_byte
 jmp .path_done
.path_bad: mov eax,VCS_ERR_CORRUPT
.path_done:
 add rsp,8
 pop r12
 pop rbx
 ret

; Import one or more sequential snapshots emitted above.
; rdi=input, rsi=length, rdx=optional signing seed, rcx=writer.
; Import is intentionally restricted to an unborn repository and never
; overwrites an existing working file.
bridge_git_import:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .import_usage
 test rsi,rsi
 jz .import_usage
 test rcx,rcx
 jz .import_usage
 mov [import_cursor],rdi
 lea rax,[rdi+rsi]
 mov [import_end],rax
 mov [import_seed],rdx
 mov [import_writer],rcx
 mov qword [import_count],0
 mov qword [import_mark_base],0
 lea rdi,[import_nodes]
 xor eax,eax
 mov ecx,VR_FILES
 rep stosq
 lea rdi,[import_new]
 mov ecx,VR_FILES
 rep stosb
 call vcs_repo_discover
 test eax,eax
 jnz .import_done
 cmp qword [vcs_repo_head],0
 jne .import_conflict
 call require_empty_worktree
 test eax,eax
 jnz .import_conflict
.import_blobs:
 lea rdi,[blob_line]
 mov esi,blob_line_len
 call peek
 test eax,eax
 jnz .import_commit
 call expect
 test eax,eax
 jnz .import_corrupt
 mov r12,[import_count]
 cmp r12,VR_FILES
 jae .import_capacity
 lea rdi,[mark_line]
 mov esi,mark_line_len
 call expect
 test eax,eax
 jnz .import_corrupt
 call parse_decimal_line
 test eax,eax
 jnz .import_corrupt
 mov rcx,[import_mark_base]
 add rcx,r12
 inc rcx
 cmp rdx,rcx
 jne .import_corrupt
 lea rdi,[data_line]
 mov esi,data_line_len
 call expect
 test eax,eax
 jnz .import_corrupt
 call parse_decimal_line
 test eax,eax
 jnz .import_corrupt
 cmp rdx,4096
 ja .import_capacity
 mov r13,rdx
 call take_data
 test eax,eax
 jnz .import_corrupt
 lea rax,[import_blob_ptr]
 mov [rax+r12*8],rdx
 lea rax,[import_blob_len]
 mov [rax+r12*8],r13
 inc qword [import_count]
 jmp .import_blobs
.import_commit:
 lea rdi,[commit_line]
 mov esi,commit_line_len
 call expect
 test eax,eax
 jnz .import_corrupt
 lea rdi,[mark_line]
 mov esi,mark_line_len
 call expect
 test eax,eax
 jnz .import_corrupt
 call parse_decimal_line
 test eax,eax
 jnz .import_corrupt
 mov rax,[import_mark_base]
 add rax,[import_count]
 inc rax
 cmp rdx,rax
 jne .import_corrupt
 lea rdi,[author_prefix]
 mov esi,author_prefix_len
 call expect
 test eax,eax
 jnz .import_corrupt
 call skip_line
 test eax,eax
 jnz .import_corrupt
 lea rdi,[committer_prefix]
 mov esi,committer_prefix_len
 call expect
 test eax,eax
 jnz .import_corrupt
 call skip_line
 test eax,eax
 jnz .import_corrupt
 lea rdi,[data_line]
 mov esi,data_line_len
 call expect
 test eax,eax
 jnz .import_corrupt
 call parse_decimal_line
 test eax,eax
 jnz .import_corrupt
 test rdx,rdx
 jz .import_usage
 cmp rdx,VR_MESSAGE_MAX
 ja .import_usage
 mov r12,rdx
 call take_data
 test eax,eax
 jnz .import_corrupt
 mov rsi,rdx
 lea rdi,[import_message]
 mov rcx,r12
.message_copy:
 lodsb
 test al,al
 jz .import_usage
 stosb
 loop .message_copy
 mov byte [rdi],0
 lea rdi,[deleteall_line]
 mov esi,deleteall_line_len
 call expect
 test eax,eax
 jnz .import_corrupt
 xor r12d,r12d
.import_entries:
 cmp r12,[import_count]
 jae .import_end_stream
 lea rdi,[modify_line]
 mov esi,modify_line_len
 call expect
 test eax,eax
 jnz .import_corrupt
 call parse_decimal_space
 test eax,eax
 jnz .import_corrupt
 mov rax,[import_mark_base]
 add rax,r12
 inc rax
 cmp rdx,rax
 jne .import_corrupt
 mov rax,r12
 imul rax,VR_PATH
 lea rdi,[import_paths+rax]
 call parse_quoted_path
 test eax,eax
 jnz .import_corrupt
 inc r12
 jmp .import_entries
.import_end_stream:
 call vcs_repo_discover
 test eax,eax
 jnz .import_done
 mov rax,[vcs_repo_head]
 mov [import_previous_head],rax
 call materialize
 test eax,eax
 jnz .import_done
 mov rdx,[import_writer]
 mov rsi,[import_seed]
 test rsi,rsi
 jz .import_unsigned
 lea rdi,[import_message]
 call vcs_history_signed
 jmp .import_commit_result
.import_unsigned:
 mov edi,1
 lea rsi,[import_message]
 call vcs_history
.import_commit_result:
 test eax,eax
 jnz .import_commit_failed
 mov rax,[import_count]
 inc rax
 add [import_mark_base],rax
 lea rdi,[done_line]
 mov esi,done_line_len
 call peek
 test eax,eax
 jnz .import_next_commit
 call expect
 mov rax,[import_cursor]
 cmp rax,[import_end]
 jne .import_corrupt
 xor eax,eax
 jmp .import_done
.import_next_commit:
 mov qword [import_count],0
 lea rdi,[import_nodes]
 xor eax,eax
 mov ecx,VR_FILES
 rep stosq
 lea rdi,[import_new]
 mov ecx,VR_FILES
 rep stosb
 jmp .import_blobs
.import_commit_failed:
 mov r15,rax
 call clear_import_nodes
 mov rdi,[import_previous_head]
 test rdi,rdi
 jz .import_failure_restored
 lea rsi,[bridge_silent]
 xor edx,edx
 call vcs_checkout
.import_failure_restored:
 mov rax,r15
 jmp .import_done
.import_usage: mov eax,VCS_ERR_USAGE
 jmp .import_done
.import_conflict: mov eax,VCS_ERR_CONFLICT
 jmp .import_done
.import_capacity: mov eax,VCS_ERR_NO_MEM
 jmp .import_done
.import_corrupt: mov eax,VCS_ERR_CORRUPT
.import_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Exact byte prefix at the cursor, without/with consumption.
peek:
 mov rax,[import_end]
 sub rax,[import_cursor]
 cmp rax,rsi
 jb .no
 mov rcx,rsi
 mov rdx,rdi
 mov rdi,[import_cursor]
 mov rsi,rdx
 repe cmpsb
 jne .no
 xor eax,eax
 ret
.no: mov eax,1
 ret

expect:
 push rbx
 mov rbx,rsi
 call peek
 test eax,eax
 jnz .done
 add [import_cursor],rbx
.done:
 pop rbx
 ret

; Decimal terminated by LF. Returns value in RDX.
parse_decimal_line:
 mov r8b,10
 jmp parse_decimal

; Decimal terminated by space. Returns value in RDX.
parse_decimal_space:
 mov r8b,' '
parse_decimal:
 mov rsi,[import_cursor]
 mov r9,[import_end]
 xor edx,edx
 xor ecx,ecx
.digit:
 cmp rsi,r9
 jae .bad
 movzx eax,byte [rsi]
 cmp al,r8b
 je .end
 cmp al,'0'
 jb .bad
 cmp al,'9'
 ja .bad
 imul rdx,rdx,10
 sub al,'0'
 movzx eax,al
 add rdx,rax
 cmp rdx,4096
 ja .bad
 inc rsi
 inc ecx
 cmp ecx,5
 jbe .digit
.bad: mov eax,VCS_ERR_CORRUPT
 ret
.end:
 test ecx,ecx
 jz .bad
 inc rsi
 mov [import_cursor],rsi
 xor eax,eax
 ret

; RDX=size. Returns data pointer in RDX and consumes its required LF.
take_data:
 mov rax,[import_cursor]
 mov rcx,[import_end]
 sub rcx,rax
 cmp rcx,rdx
 jbe .bad
 lea rcx,[rax+rdx]
 cmp byte [rcx],10
 jne .bad
 lea rsi,[rcx+1]
 mov [import_cursor],rsi
 mov rdx,rax
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret

skip_line:
 mov rax,[import_cursor]
 mov rdx,[import_end]
.scan:
 cmp rax,rdx
 jae .bad
 cmp byte [rax],10
 je .found
 inc rax
 jmp .scan
.found:
 inc rax
 mov [import_cursor],rax
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret

; Decode the exporter's quoted path and consume its LF.
parse_quoted_path:
 push rbx
 mov rbx,rdi
 mov rsi,[import_cursor]
 mov rdx,[import_end]
 cmp rsi,rdx
 jae .bad
 cmp byte [rsi],'"'
 jne .bad
 inc rsi
 xor ecx,ecx
.path:
 cmp rsi,rdx
 jae .bad
 mov al,[rsi]
 inc rsi
 cmp al,'"'
 je .close
 cmp al,92
 jne .store
 lea rax,[rsi+3]
 cmp rax,rdx
 ja .bad
 xor eax,eax
 mov r8d,3
.octal:
 movzx r9d,byte [rsi]
 cmp r9b,'0'
 jb .bad
 cmp r9b,'7'
 ja .bad
 shl eax,3
 sub r9b,'0'
 or al,r9b
 inc rsi
 dec r8d
 jnz .octal
.store:
 test al,al
 jz .bad
 cmp ecx,VR_PATH-1
 jae .bad
 mov [rbx+rcx],al
 inc ecx
 jmp .path
.close:
 test ecx,ecx
 jz .bad
 cmp rsi,rdx
 jae .bad
 cmp byte [rsi],10
 jne .bad
 inc rsi
 mov byte [rbx+rcx],0
 mov [import_cursor],rsi
 mov rdi,rbx
 call validate_relative
 jmp .done
.bad: mov eax,VCS_ERR_CORRUPT
.done:
 pop rbx
 ret

; Reject absolute, empty, dot, parent, and metadata path components.
validate_relative:
 cmp byte [rdi],0
 je .bad
 cmp byte [rdi],'/'
 je .bad
 mov rsi,rdi
.component:
 mov rdx,rsi
.find_end:
 mov al,[rsi]
 test al,al
 jz .check
 cmp al,'/'
 je .check
 cmp al,32
 jb .bad
 cmp al,127
 je .bad
 inc rsi
 jmp .find_end
.check:
 cmp rsi,rdx
 je .bad
 mov rcx,rsi
 sub rcx,rdx
 cmp rcx,1
 jne .dotdot
 cmp byte [rdx],'.'
 je .bad
.dotdot:
 cmp rcx,2
 jne .metadata
 cmp byte [rdx],'.'
 jne .metadata
 cmp byte [rdx+1],'.'
 je .bad
.metadata:
 cmp rcx,4
 jne .next
 cmp dword [rdx],0x7363762e       ; .vcs
 je .bad
.next:
 cmp byte [rsi],0
 je .ok
 inc rsi
 cmp byte [rsi],0
 je .bad
 jmp .component
.ok: xor eax,eax
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret

; An unborn import must not silently absorb pre-existing regular files.
require_empty_worktree:
 push rbx
 push r12
 push r13
 lea rbx,[uxv_nodes+UV_NODE]
.node:
 cmp qword [rbx+UV_TYPE],1
 jne .next
 lea r12,[rbx]
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 je .root_repo
 lea rdi,[vcs_repo_root]
 mov rsi,r12
 repe cmpsb
 jne .next
 cmp byte [rsi],'/'
 jne .next
 lea r13,[rsi+1]
 jmp .classify
.root_repo:
 cmp byte [r12],'/'
 jne .next
 lea r13,[r12+1]
.classify:
 cmp byte [r13],'.'
 jne .busy
 cmp byte [r13+1],'v'
 jne .busy
 cmp byte [r13+2],'c'
 jne .busy
 cmp byte [r13+3],'s'
 jne .busy
 cmp byte [r13+4],'/'
 je .next
 cmp byte [r13+4],0
 je .next
.busy:
 mov eax,1
 jmp .done
.next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .node
 xor eax,eax
.done:
 pop r13
 pop r12
 pop rbx
 ret

materialize:
 push rbx
 push r12
 push r13
 push r14
 sub rsp,8
 xor r12d,r12d
.preflight:
 cmp r12,[import_count]
 jae .delete_old
 mov rax,r12
 imul rax,VR_PATH
 lea r13,[import_paths+rax]
 call build_absolute
 test eax,eax
 jnz .fail
 lea rdi,[import_absolute]
 lea rsi,[import_canonical]
 call uxv_normalize
 test rax,rax
 js .conflict
 lea rdi,[import_canonical]
 call uxv_find
 test rax,rax
 jnz .existing
 call uxv_free
 test rax,rax
 jz .capacity
 mov r14,rax
 mov byte [import_new+r12],1
 mov rdi,r14
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 mov qword [r14+UV_TYPE],3       ; reserve until every path is preflighted
 jmp .remember
.existing:
 cmp qword [rax+UV_TYPE],1
 jne .conflict
 mov r14,rax
.remember:
 lea rdx,[import_nodes]
 mov [rdx+r12*8],r14
 inc r12
 jmp .preflight
.delete_old:
 lea rbx,[uxv_nodes+UV_NODE]
.old_node:
 cmp qword [rbx+UV_TYPE],1
 jne .old_next
 mov rdi,rbx
 call working_node
 test eax,eax
 jz .old_next
 mov rdi,rbx
 call node_is_target
 test eax,eax
 jnz .old_next
 mov rdi,rbx
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
.old_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .old_node
 xor r12d,r12d
.write:
 cmp r12,[import_count]
 jae .ok
 lea rax,[import_nodes]
 mov r14,[rax+r12*8]
 mov rdi,r14
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 mov rax,r12
 imul rax,VR_PATH
 lea r13,[import_paths+rax]
 call build_absolute
 lea rdi,[import_absolute]
 lea rsi,[import_canonical]
 call uxv_normalize
 test rax,rax
 js .conflict
 mov rdi,r14
 lea rsi,[import_canonical]
 mov ecx,240
 rep movsb
 mov qword [r14+UV_TYPE],1
 lea rax,[import_blob_len]
 mov rcx,[rax+r12*8]
 mov [r14+UV_SIZE],rcx
 lea rax,[import_blob_ptr]
 mov rsi,[rax+r12*8]
 lea rdi,[r14+UV_DATA]
 rep movsb
 inc r12
 jmp .write
.ok: xor eax,eax
 jmp .done
.conflict: mov eax,VCS_ERR_CONFLICT
 jmp .fail
.capacity: mov eax,VCS_ERR_NO_MEM
.fail:
 push rax
 call clear_import_nodes
 pop rax
.done:
 add rsp,8
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

build_absolute:
 lea rdi,[import_absolute]
 xor eax,eax
 mov ecx,30
 rep stosq
 lea rsi,[vcs_repo_root]
 lea rdi,[import_absolute]
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 je .root
 rep movsb
 mov byte [rdi],'/'
 inc rdi
 jmp .relative
.root:
 rep movsb
.relative:
 mov rsi,r13
.copy:
 lodsb
 stosb
 test al,al
 jnz .copy
 xor eax,eax
 ret

clear_import_nodes:
 lea rdx,[import_nodes]
 xor ecx,ecx
.clear:
 cmp rcx,VR_FILES
 jae .done
 mov rdi,[rdx+rcx*8]
 test rdi,rdi
 jz .next
 cmp byte [import_new+rcx],0
 je .forget
 push rcx
 push rdx
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 pop rdx
 pop rcx
.forget:
 mov qword [rdx+rcx*8],0
.next:
 inc rcx
 jmp .clear
.done: ret

; RDI=node -> EAX=1 for a regular file in this worktree outside .vcs.
working_node:
 push rbx
 push r12
 mov rbx,rdi
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 je .root
 lea rdi,[vcs_repo_root]
 mov rsi,rbx
 repe cmpsb
 jne .no
 cmp byte [rsi],'/'
 jne .no
 lea r12,[rsi+1]
 jmp .metadata
.root:
 cmp byte [rbx],'/'
 jne .no
 lea r12,[rbx+1]
.metadata:
 cmp dword [r12],0x7363762e
 jne .yes
 cmp byte [r12+4],'/'
 je .no
 cmp byte [r12+4],0
 je .no
.yes: mov eax,1
 jmp .done
.no: xor eax,eax
.done:
 pop r12
 pop rbx
 ret

; RDI=node -> EAX=1 when its canonical path is in the incoming snapshot.
node_is_target:
 push rbx
 push r12
 push r13
 mov rbx,rdi
 xor r12d,r12d
.target:
 cmp r12,[import_count]
 jae .no
 mov rax,r12
 imul rax,VR_PATH
 lea r13,[import_paths+rax]
 call build_absolute
 lea rdi,[import_absolute]
 lea rsi,[import_canonical]
 call uxv_normalize
 test rax,rax
 js .no
 mov rdi,rbx
 lea rsi,[import_canonical]
 mov ecx,240
 repe cmpsb
 je .yes
 inc r12
 jmp .target
.yes: mov eax,1
 jmp .done
.no: xor eax,eax
.done:
 pop r13
 pop r12
 pop rbx
 ret

bridge_git_serve:
 mov eax,VCS_ERR_UNSUPPORTED
 ret

bridge_silent:
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
