; Persistent bounded stash stack backed by ordinary validated snapshot commits.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "lib/storage/uxfs/volume.inc"
bits 64
default rel

extern uxv_ready,uxv_find,uxv_free,uxv_commit
extern vcs_repo_discover,vcs_load_manifest,vcs_history,vcs_history_signed
extern vcs_checkout,vcs_threeway_replay
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_head

%define STASH_HEADER 16
%define STASH_RECORD 16
%define STASH_MAX ((4096-STASH_HEADER)/STASH_RECORD)

section .bss
stash_writer: resq 1
stash_node: resq 1
stash_count: resq 1
stash_path: resb 240
active_path: resb 240
active_name: resb 33
stash_number: resb 20

section .rodata
stash_magic: db 'UVCSST1'
stash_suffix: db '/.vcs/stash',0
active_suffix: db '/.vcs/active',0
index_suffix: db '/.vcs/index',0
merge_suffix: db '/.vcs/merge',0
rebase_suffix: db '/.vcs/rebase',0
pick_suffix: db '/.vcs/pick',0
conflict_suffix: db '/.vcs/conflicts',0
default_message: db 'stash',0
saved_text: db 'Saved stash '
saved_text_len equ $-saved_text
applied_text: db 'Applied stash '
applied_text_len equ $-applied_text
dropped_text: db 'Dropped stash '
dropped_text_len equ $-dropped_text
entry_text: db 'stash@{'
entry_text_len equ $-entry_text
entry_middle: db '} '
entry_middle_len equ $-entry_middle
space: db ' '
newline: db 10
hex: db '0123456789abcdef'

section .text
global vcs_stash
; RDI=op: 0 save, 1 list, 2 apply, 3 pop, 4 drop.
; RSI=save message or NULL, RDX=optional signing seed, RCX=writer.
vcs_stash:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 cmp rdi,4
 ja .usage
 test rcx,rcx
 jz .usage
 cmp qword [uxv_ready],1
 jne .io
 mov rbp,rdi
 mov r12,rsi
 mov r13,rdx
 mov [stash_writer],rcx
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call load_stack
 test eax,eax
 jnz .done
 test rbp,rbp
 jz .save
 cmp rbp,1
 je .list
 cmp rbp,2
 je .apply
 cmp rbp,3
 je .pop
 jmp .drop

.save:
 mov r14,[vcs_repo_head]
 test r14,r14
 jz .conflict
 cmp qword [stash_count],STASH_MAX
 jae .capacity
 call operations_clear
 test eax,eax
 jnz .conflict
 call capture_active
 test eax,eax
 jnz .done
 test r12,r12
 jnz .message_ready
 lea r12,[default_message]
.message_ready:
 test r13,r13
 jz .save_unsigned
 mov rdi,r12
 mov rsi,r13
 lea rdx,[silent]
 call vcs_history_signed
 jmp .save_result
.save_unsigned:
 mov edi,1
 mov rsi,r12
 lea rdx,[silent]
 call vcs_history
.save_result:
 test eax,eax
 jnz .done
 mov r15,[vcs_repo_head]
 cmp r15,r14
 je .conflict
 ; Publish the ownership record before restoring the original branch/HEAD.
 mov rax,[stash_count]
 imul rax,STASH_RECORD
 mov rbx,[stash_node]
 lea rbx,[rbx+UV_DATA+STASH_HEADER+rax]
 mov [rbx],r15
 mov [rbx+8],r14
 inc qword [stash_count]
 mov rbx,[stash_node]
 mov rax,[stash_count]
 mov [rbx+UV_DATA+8],rax
 imul rax,STASH_RECORD
 add rax,STASH_HEADER
 mov [rbx+UV_SIZE],rax
 call uxv_commit
 test eax,eax
 jnz .io
 mov rdi,r14
 lea rsi,[silent]
 lea rdx,[active_name]
 cmp byte [active_name],0
 jne .save_checkout
 xor edx,edx
.save_checkout:
 call vcs_checkout
 test eax,eax
 jnz .done
 lea rdi,[saved_text]
 mov esi,saved_text_len
 call emit
 mov rdi,r15
 call emit_id
 call emit_newline
 xor eax,eax
 jmp .done

.list:
 mov r14,[stash_count]
 xor r15d,r15d
.list_loop:
 test r14,r14
 jz .ok
 dec r14
 lea rdi,[entry_text]
 mov esi,entry_text_len
 call emit
 mov rdi,r15
 call emit_decimal
 lea rdi,[entry_middle]
 mov esi,entry_middle_len
 call emit
 mov rbx,[stash_node]
 mov rax,r14
 imul rax,STASH_RECORD
 mov rdi,[rbx+UV_DATA+STASH_HEADER+rax]
 push rdi
 call emit_id
 lea rdi,[space]
 mov esi,1
 call emit
 pop rdi
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rcx,[rax+32]
 btr rcx,63
 lea rdi,[rax+VR_MESSAGE]
 mov rsi,rcx
 call emit_escaped
 call emit_newline
 inc r15
 jmp .list_loop

.apply:
 call top_record
 test eax,eax
 jnz .done
 mov r14,rdx                    ; stash commit
 mov rdi,rcx                    ; original base
 mov rsi,[vcs_repo_head]
 test rsi,rsi
 jz .conflict
 mov rdx,r14
 call vcs_threeway_replay
 test eax,eax
 jnz .done
.apply_report:
 mov r15,rdx                    ; conflict count
 lea rdi,[applied_text]
 mov esi,applied_text_len
 call emit
 mov rdi,r14
 call emit_id
 call emit_newline
 mov rdx,r15
 xor eax,eax
 jmp .done

.pop:
 call top_record
 test eax,eax
 jnz .done
 mov r14,rdx
 mov rdi,rcx
 mov rsi,[vcs_repo_head]
 test rsi,rsi
 jz .conflict
 mov rdx,r14
 call vcs_threeway_replay
 test eax,eax
 jnz .done
 test rdx,rdx
 jnz .apply_report               ; retain a conflicted stash
 call remove_top
 test eax,eax
 jnz .done
 xor edx,edx
 jmp .apply_report

.drop:
 call top_record
 test eax,eax
 jnz .done
 mov r14,rdx
 call remove_top
 test eax,eax
 jnz .done
 lea rdi,[dropped_text]
 mov esi,dropped_text_len
 call emit
 mov rdi,r14
 call emit_id
 call emit_newline
.ok:
 xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.conflict: mov eax,VCS_ERR_CONFLICT
 jmp .done
.capacity: mov eax,VCS_ERR_NO_MEM
 jmp .done
.corrupt: mov eax,VCS_ERR_CORRUPT
 jmp .done
.io: mov eax,VCS_ERR_IO
.done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Load or allocate the stack node, validating every referenced snapshot.
load_stack:
 push rbx
 push r12
 push r13
 push r14
 sub rsp,8
 lea rsi,[stash_suffix]
 lea rdi,[stash_path]
 call make_path
 lea rdi,[stash_path]
 call uxv_find
 test rax,rax
 jnz .existing
 call uxv_free
 test rax,rax
 jz .full
 mov [stash_node],rax
 mov rbx,rax
 mov rdi,rbx
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 lea rdi,[rbx]
 lea rsi,[stash_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov qword [rbx+UV_SIZE],STASH_HEADER
 mov rax,[stash_magic]
 mov [rbx+UV_DATA],rax
 mov qword [rbx+UV_DATA+8],0
 mov qword [stash_count],0
 xor eax,eax
 jmp .done
.existing:
 mov [stash_node],rax
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rcx,[rax+UV_SIZE]
 cmp rcx,STASH_HEADER
 jb .bad
 mov rdx,[stash_magic]
 cmp [rax+UV_DATA],rdx
 jne .bad
 mov r12,[rax+UV_DATA+8]
 cmp r12,STASH_MAX
 ja .bad
 mov rdx,r12
 imul rdx,STASH_RECORD
 add rdx,STASH_HEADER
 cmp rcx,rdx
 jne .bad
 mov [stash_count],r12
 xor r13d,r13d
.validate:
 cmp r13,r12
 jae .valid
 mov rbx,[stash_node]
 mov rax,r13
 imul rax,STASH_RECORD
 lea rbx,[rbx+UV_DATA+STASH_HEADER+rax]
 mov rdi,[rbx]
 test rdi,rdi
 jz .bad
 mov r14,[rbx+8]
 test r14,r14
 jz .bad
 call vcs_load_manifest
 test rax,rax
 jz .bad
 cmp [rax+16],r14
 jne .bad
 inc r13
 jmp .validate
.valid: xor eax,eax
 jmp .done
.full: mov eax,VCS_ERR_NO_MEM
 jmp .done
.bad: mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,8
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

top_record:
 mov rax,[stash_count]
 test rax,rax
 jz .missing
 dec rax
 imul rax,STASH_RECORD
 mov rbx,[stash_node]
 lea rbx,[rbx+UV_DATA+STASH_HEADER+rax]
 mov rdx,[rbx]
 mov rcx,[rbx+8]
 xor eax,eax
 ret
.missing: mov eax,VCS_ERR_NOT_FOUND
 ret

remove_top:
 sub rsp,8
 mov rax,[stash_count]
 test rax,rax
 jz .missing
 dec rax
 mov [stash_count],rax
 mov rbx,[stash_node]
 mov [rbx+UV_DATA+8],rax
 imul rax,STASH_RECORD
 add rax,STASH_HEADER
 mov [rbx+UV_SIZE],rax
 call uxv_commit
 test eax,eax
 jnz .io
 xor eax,eax
 jmp .done
.missing: mov eax,VCS_ERR_NOT_FOUND
 jmp .done
.io: mov eax,VCS_ERR_IO
.done:
 add rsp,8
 ret

operations_clear:
 sub rsp,8
 lea rsi,[index_suffix]
 call metadata_exists
 test eax,eax
 jnz .busy
 lea rsi,[merge_suffix]
 call metadata_exists
 test eax,eax
 jnz .busy
 lea rsi,[rebase_suffix]
 call metadata_exists
 test eax,eax
 jnz .busy
 lea rsi,[pick_suffix]
 call metadata_exists
 test eax,eax
 jnz .busy
 lea rsi,[conflict_suffix]
 call metadata_exists
 test eax,eax
 jnz .busy
 xor eax,eax
 jmp .done
.busy: mov eax,1
.done:
 add rsp,8
 ret

metadata_exists:
 sub rsp,8
 lea rdi,[active_path]
 call make_path
 lea rdi,[active_path]
 call uxv_find
 test rax,rax
 setnz al
 movzx eax,al
 add rsp,8
 ret

capture_active:
 sub rsp,8
 lea rdi,[active_name]
 xor eax,eax
 mov ecx,33
 rep stosb
 lea rsi,[active_suffix]
 lea rdi,[active_path]
 call make_path
 lea rdi,[active_path]
 call uxv_find
 test rax,rax
 jz .none
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rcx,[rax+UV_SIZE]
 cmp rcx,2
 jb .bad
 cmp rcx,33
 ja .bad
 cmp byte [rax+UV_DATA+rcx-1],0
 jne .bad
 lea rsi,[rax+UV_DATA]
 lea rdi,[active_name]
 rep movsb
.none: xor eax,eax
 jmp .done
.bad: mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,8
 ret

; RDI=destination, RSI=NUL suffix. Root avoids a duplicate slash.
make_path:
 push rbx
 mov rbx,rsi
 push rdi
 xor eax,eax
 mov ecx,30
 rep stosq
 pop rdi
 lea rsi,[vcs_repo_root]
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .copy_root
 xor ecx,ecx
.copy_root:
 rep movsb
 mov rsi,rbx
.suffix:
 lodsb
 stosb
 test al,al
 jnz .suffix
 pop rbx
 ret

emit_id:
 mov rax,rdi
 lea rdi,[stash_number]
 mov ecx,16
 lea r8,[hex]
.id_digit:
 rol rax,4
 mov rdx,rax
 and edx,15
 mov dl,[r8+rdx]
 mov [rdi],dl
 inc rdi
 loop .id_digit
 lea rdi,[stash_number]
 mov esi,16
 jmp emit

emit_decimal:
 lea r8,[stash_number+20]
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
 jmp emit

emit_escaped:
 sub rsp,8
 test rsi,rsi
 jz .escaped_done
 mov rcx,rsi
.escaped_byte:
 mov al,[rdi]
 cmp al,10
 je .escape
 cmp al,13
 je .escape
 cmp al,32
 jb .escape
 cmp al,126
 ja .escape
 cmp al,92
 je .escape
 push rcx
 push rdi
 mov esi,1
 call emit
 pop rdi
 pop rcx
 inc rdi
 loop .escaped_byte
.escaped_done:
 add rsp,8
 ret
.escape:
 push rcx
 push rdi
 movzx eax,al
 mov byte [stash_number],92
 mov byte [stash_number+1],'x'
 mov edx,eax
 shr edx,4
 lea r8,[hex]
 mov dl,[r8+rdx]
 mov [stash_number+2],dl
 and eax,15
 mov al,[r8+rax]
 mov [stash_number+3],al
 lea rdi,[stash_number]
 mov esi,4
 call emit
 pop rdi
 pop rcx
 inc rdi
 loop .escaped_byte
 add rsp,8
 ret

emit_newline:
 lea rdi,[newline]
 mov esi,1
 jmp emit

silent:
 ret

emit:
 jmp [stash_writer]

section .note.GNU-stack noalloc noexec nowrite progbits
