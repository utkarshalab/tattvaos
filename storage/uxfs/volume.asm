; Serialized BSP-only UXFS v2 volume. Callbacks use SysV:
; read/write(rdi=LBA,rsi=sector count,rdx=buffer), flush() -> 0 or negative.
; No autoformat, borrowed disk buffers, allocation, or success-only I/O stubs.
%include "storage/uxfs/volume.inc"
bits 64
default rel
section .bss
global uxv_read,uxv_write,uxv_flush,uxv_ready,uxv_nodes,uxv_cwd
uxv_read: resq 1
uxv_write: resq 1
uxv_flush: resq 1
uxv_ready: resq 1
generation: resq 1
active: resq 1
candidate: resq 1
candidate_generation: resq 1
header: resb 512
uxv_nodes: resb UV_BYTES
scratch: resb UV_BYTES
validate_path: resb 240
uxv_cwd: resb 240
section .text
global uxv_mount,uxv_commit,uxv_find,uxv_normalize,uxv_free
global uxv_sync
uxv_sync:
 cmp qword [uxv_flush],0
 je .none
 sub rsp,8
 call [uxv_flush]
 test rax,rax
 jns .done
 mov qword [uxv_ready],0
.done:
 add rsp,8
 ret
.none:
 xor eax,eax
 ret
; FNV-1a detects accidental corruption, not hostile tampering.
hash:
 mov rax,0xcbf29ce484222325
 mov r8,0x100000001b3
.loop:
 movzx edx,byte [rdi]
 xor rax,rdx
 imul rax,r8
 inc rdi
 dec rcx
 jnz .loop
 ret
uxv_mount:
 push rbx
 mov qword [uxv_ready],0
 mov qword [generation],0
 mov word [uxv_cwd],'/'
 cmp qword [uxv_read],0
 je .done
 cmp qword [uxv_write],0
 je .done
 cmp qword [uxv_flush],0
 je .done
 xor ebx,ebx
.bank:
 mov rdi,rbx
 imul rdi,UV_BANK
 mov esi,1
 lea rdx,[header]
 call [uxv_read]
 test rax,rax
 js .next
 mov rax,UV_MAGIC
 cmp [header],rax
 jne .next
 cmp qword [header+8],2
 jne .next
 mov rax,[header+16]
 test rax,rax
 jz .next
 cmp rax,[generation]
 jbe .next
 mov [candidate_generation],rax
 mov rax,[header+32]
 mov [candidate],rax
 mov qword [header+32],0
 lea rdi,[header]
 mov ecx,512
 call hash
 cmp rax,[candidate]
 jne .next
 mov rdi,rbx
 imul rdi,UV_BANK
 inc rdi
 mov esi,UV_SECTORS
 lea rdx,[scratch]
 call [uxv_read]
 test rax,rax
 js .next
 lea rdi,[scratch]
 mov ecx,UV_BYTES
 call hash
 cmp rax,[header+24]
 jne .next
 ; Validate every bounded record before publishing it. Namespace lookup also
 ; checks directory traversal, so corrupt paths cannot cause memory accesses.
 cmp word [scratch],'/'
 jne .next
 cmp qword [scratch+UV_TYPE],2
 jne .next
 lea rdi,[scratch]
 mov esi,UV_NODES
.validate:
 mov rax,[rdi+UV_TYPE]
 test rax,rax
 jz .record_ok
 cmp rax,2
 ja .next
 cmp byte [rdi],'/'
 jne .next
 cmp qword [rdi+UV_SIZE],4096
 ja .next
 cmp rax,2
 jne .name
 cmp qword [rdi+UV_SIZE],0
 jne .next
.name:
 xor ecx,ecx
.nul:
 cmp byte [rdi+rcx],0
 je .record_ok
 inc ecx
 cmp ecx,240
 jb .nul
 jmp .next
.record_ok:
 add rdi,UV_NODE
 dec esi
 jnz .validate
 call validate_namespace
 test eax,eax
 jnz .next
 lea rsi,[scratch]
 lea rdi,[uxv_nodes]
 mov ecx,UV_BYTES/8
 rep movsq
 mov rax,[candidate_generation]
 mov [generation],rax
 mov [active],rbx
 mov qword [uxv_ready],1
.next:
 inc ebx
 cmp ebx,2
 jb .bank
.done:
 mov rax,[uxv_ready]
 dec rax
 pop rbx
 ret
uxv_commit:
 push rbx
 cmp qword [uxv_ready],1
 jne .fail
 cmp qword [generation],-1
 je .fail
 mov rbx,[active]
 xor ebx,1
 ; Overwrite only the inactive body. The active bank remains intact.
 mov rdi,rbx
 imul rdi,UV_BANK
 inc rdi
 mov esi,UV_SECTORS
 lea rdx,[uxv_nodes]
 call [uxv_write]
 test rax,rax
 js .fail
 call [uxv_flush]
 test rax,rax
 js .fail
 lea rdi,[header]
 xor eax,eax
 mov ecx,64
 rep stosq
 mov rax,UV_MAGIC
 mov [header],rax
 mov qword [header+8],2
 mov rax,[generation]
 inc rax
 mov [header+16],rax
 lea rdi,[uxv_nodes]
 mov ecx,UV_BYTES
 call hash
 mov [header+24],rax
 lea rdi,[header]
 mov ecx,512
 call hash
 mov [header+32],rax
 mov rdi,rbx
 imul rdi,UV_BANK
 mov esi,1
 lea rdx,[header]
 call [uxv_write]
 test rax,rax
 js .fail
 call [uxv_flush]
 test rax,rax
 js .fail
 mov [active],rbx
 inc qword [generation]
 xor eax,eax
 pop rbx
 ret
.fail:
 ; A final flush can fail after bytes reached disk. Disable this mount rather
 ; than claim rollback or expose uncommitted in-memory changes.
 mov qword [uxv_ready],0
 mov rax,-5
 pop rbx
 ret
; Exact canonical absolute path -> record or 0. Preserves rdi/rsi.
uxv_find:
 lea r10,[uxv_nodes]
find_in:
 mov rax,r10
 mov r9d,UV_NODES
.record:
 cmp qword [rax+UV_TYPE],0
 je .next
 xor ecx,ecx
.name:
 mov dl,[rdi+rcx]
 cmp dl,[rax+rcx]
 jne .next
 test dl,dl
 jz .found
 inc ecx
 cmp ecx,240
 jb .name
.next:
 add rax,UV_NODE
 dec r9d
 jnz .record
 xor eax,eax
.found: ret
; Each active record is canonical and unique, and every proper prefix is an
; existing directory. This rejects malformed checksummed metadata at mount.
validate_namespace:
 push rbx
 push r12
 push r13
 push r14
 push r15
 lea r11,[validate_path]
 lea r12,[scratch+UV_NODE]
 mov r13d,UV_NODES-1
.record:
 cmp qword [r12+UV_TYPE],0
 je .next
 cmp byte [r12+1],0
 je .bad                       ; only slot zero may be root
 mov word [validate_path],'/'
 mov ebx,1
 mov r14d,1
.char:
 mov al,[r12+rbx]
 test al,al
 jz .end_component
 cmp al,'/'
 je .end_component
 cmp al,32
 jb .bad
 cmp al,127
 je .bad
 mov [r11+rbx],al
 inc ebx
 jmp .char
.end_component:
 cmp ebx,r14d
 je .bad
 mov ecx,ebx
 sub ecx,r14d
 cmp ecx,1
 jne .dotdot
 cmp byte [r12+r14],'.'
 je .bad
.dotdot:
 cmp ecx,2
 jne .prefix
 cmp word [r12+r14],'..'
 je .bad
.prefix:
 cmp byte [r12+rbx],0
 je .unique
 mov byte [r11+rbx],0
 lea rdi,[validate_path]
 lea r10,[scratch]
 call find_in
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],2
 jne .bad
 mov byte [r11+rbx],'/'
 inc ebx
 mov r14d,ebx
 jmp .char
.unique:
 lea r15,[scratch]
.prior:
 cmp r15,r12
 jae .next
 cmp qword [r15+UV_TYPE],0
 je .skip
 xor ecx,ecx
.compare:
 mov al,[r12+rcx]
 cmp al,[r15+rcx]
 jne .skip
 test al,al
 jz .bad
 inc ecx
 jmp .compare
.skip:
 add r15,UV_NODE
 jmp .prior
.next:
 add r12,UV_NODE
 dec r13d
 jnz .record
 xor eax,eax
 jmp .done
.bad: mov eax,1
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
uxv_free:
 lea rax,[uxv_nodes+UV_NODE]
 mov ecx,UV_NODES-1
.next:
 cmp qword [rax+UV_TYPE],0
 je .found
 add rax,UV_NODE
 loop .next
 xor eax,eax
.found: ret
; Normalize a nonempty path into 240-byte destination. Checks each traversed
; directory BEFORE consuming the next component (including . and ..).
uxv_normalize:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdi
 mov r13,rsi
 xor ebx,ebx
 cmp byte [r12],0
 je .bad
 cmp byte [r12],'/'
 je .root
 lea rsi,[uxv_cwd]
.cwd:
 mov al,[rsi+rbx]
 mov [r13+rbx],al
 test al,al
 jz .component
 inc ebx
 jmp .cwd
.root:
 mov word [r13],'/'
 mov ebx,1
.component:
 ; Current prefix must be a directory before traversal.
 cmp byte [r12],0
 je .ok
 mov rdi,r13
 call uxv_find
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],2
 jne .bad
.slash:
 cmp byte [r12],'/'
 jne .start
 inc r12
 jmp .slash
.start:
 cmp byte [r12],0
 je .ok
 mov r14,r12
.scan:
 mov al,[r12]
 test al,al
 jz .parsed
 cmp al,'/'
 je .parsed
 cmp al,32
 jb .bad
 cmp al,127
 je .bad
 inc r12
 jmp .scan
.parsed:
 mov r15,r12
 sub r15,r14
 cmp r15,1
 jne .dotdot
 cmp byte [r14],'.'
 je .component
.dotdot:
 cmp r15,2
 jne .append
 cmp word [r14],'..'
 jne .append
.pop:
 cmp ebx,1
 jbe .truncate
 dec ebx
 cmp byte [r13+rbx],'/'
 jne .pop
 test ebx,ebx
 jnz .truncate
 mov ebx,1
.truncate:
 mov byte [r13+rbx],0
 jmp .component
.append:
 cmp ebx,1
 je .copy
 cmp ebx,238
 jae .bad
 mov byte [r13+rbx],'/'
 inc ebx
.copy:
 lea rax,[rbx+r15]
 cmp rax,239
 ja .bad
 mov rcx,r15
 lea rdi,[r13+rbx]
 mov rsi,r14
 rep movsb
 add rbx,r15
 mov byte [r13+rbx],0
 cmp byte [r12],0
 jne .component
.ok:
 xor eax,eax
 jmp .done
.bad:
 mov rax,-22
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
