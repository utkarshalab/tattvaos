; Git SHA-256 object hashing and non-delta PACK v2 writer.
%include "include/vcs.inc"
%include "include/git_pack.inc"
%include "lib/crypto/uhash/sha256/sha256.inc"
bits 64
default rel

extern sha256_init,sha256_update,sha256_final,sha256_hash

section .bss
pack_start: resq 1
pack_cursor: resq 1
pack_left: resq 1
pack_expected: resd 1
pack_written: resd 1
pack_unique: resd 1
pack_seen_count: resd 1
pack_seen: resb 4096*GIT_HASH_SIZE
pack_object_hash: resb GIT_HASH_SIZE
pack_ctx: resb sha256_ctx_t_size
object_ctx: resb sha256_ctx_t_size
object_header: resb 32
pack_header: resb 16

section .rodata
pack_magic: db 'PACK'
commit_type: db 'commit'
tree_type: db 'tree'
blob_type: db 'blob'

section .text
global git_object_hash,git_pack_begin,git_pack_begin_unique
global git_pack_add,git_pack_finish

; RDI=ASCII type, RSI=type length, RDX=data, RCX=data length, R8=32-byte digest.
git_object_hash:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .usage
 cmp rsi,6
 ja .usage
 test rdx,rdx
 jz .usage
 test r8,r8
 jz .usage
 cmp rcx,GIT_PACK_MAX_OBJECT
 ja .usage
 mov r12,rdi
 mov r13,rsi
 mov r14,rdx
 mov r15,rcx
 mov rbp,r8
 lea rdi,[object_header]
 mov rsi,r12
 mov rcx,r13
 rep movsb
 mov byte [rdi],' '
 inc rdi
 mov rax,r15
 lea rbx,[object_header+31]
 xor ecx,ecx
.digits:
 xor edx,edx
 mov r8d,10
 div r8
 add dl,'0'
 dec rbx
 mov [rbx],dl
 inc ecx
 test rax,rax
 jnz .digits
 mov rsi,rbx
 rep movsb
 mov byte [rdi],0
 inc rdi
 lea rbx,[object_header]
 sub rdi,rbx
 mov r12,rdi
 lea rdi,[object_ctx]
 call sha256_init
 lea rdi,[object_ctx]
 lea rsi,[object_header]
 mov rdx,r12
 call sha256_update
 lea rdi,[object_ctx]
 mov rsi,r14
 mov rdx,r15
 call sha256_update
 lea rdi,[object_ctx]
 mov rsi,rbp
 call sha256_final
 xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
.done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=output, RSI=capacity, EDX=object count.
git_pack_begin:
 mov dword [pack_unique],0
 jmp pack_begin_common

; Begin a pack whose RDX object count is an upper bound. Duplicate OIDs are
; skipped and the final unique count is patched before the trailer is hashed.
git_pack_begin_unique:
 cmp rdx,4096
 jbe .unique_ok
 mov eax,VCS_ERR_NO_MEM
 ret
.unique_ok:
 mov dword [pack_unique],1
pack_begin_common:
 test rdi,rdi
 jz .usage
 cmp rsi,44                       ; header plus SHA-256 trailer
 jb .space
 mov [pack_start],rdi
 mov [pack_cursor],rdi
 mov [pack_left],rsi
 mov [pack_expected],edx
 mov dword [pack_written],0
 mov dword [pack_seen_count],0
 mov eax,[pack_magic]
 mov [rdi],eax
 mov dword [rdi+4],0x02000000      ; version 2, big endian
 mov eax,edx
 bswap eax
 mov [rdi+8],eax
 add qword [pack_cursor],12
 sub qword [pack_left],12
 xor eax,eax
 ret
.space: mov eax,VCS_ERR_NO_MEM
 ret
.usage: mov eax,VCS_ERR_USAGE
 ret

; EDI=Git type (1 commit, 2 tree, 3 blob), RSI=data, RDX=length.
git_pack_add:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 cmp edi,GIT_PACK_COMMIT
 jb .usage
 cmp edi,GIT_PACK_BLOB
 ja .usage
 test rsi,rsi
 jz .usage
 cmp rdx,GIT_PACK_MAX_OBJECT
 ja .usage
 mov r12d,edi
 mov r13,rsi
 mov r14,rdx
 mov eax,[pack_written]
 cmp eax,[pack_expected]
 jae .usage
 cmp dword [pack_unique],0
 je .encode
 lea rdi,[commit_type]
 mov esi,6
 cmp r12d,GIT_PACK_COMMIT
 je .hash_candidate
 lea rdi,[tree_type]
 mov esi,4
 cmp r12d,GIT_PACK_TREE
 je .hash_candidate
 lea rdi,[blob_type]
.hash_candidate:
 mov rdx,r13
 mov rcx,r14
 lea r8,[pack_object_hash]
 call git_object_hash
 test eax,eax
 jnz .done
 xor ecx,ecx
.seen:
 cmp ecx,[pack_seen_count]
 jae .remember
 mov eax,ecx
 imul rax,GIT_HASH_SIZE
 lea rdi,[pack_seen]
 add rdi,rax
 lea rsi,[pack_object_hash]
 push rcx
 mov ecx,GIT_HASH_SIZE
 repe cmpsb
 pop rcx
 je .duplicate
 inc ecx
 jmp .seen
.remember:
 mov eax,[pack_seen_count]
 cmp eax,4096
 jae .space
 imul rax,GIT_HASH_SIZE
 lea rdi,[pack_seen]
 add rdi,rax
 lea rsi,[pack_object_hash]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 inc dword [pack_seen_count]
.encode:
 ; Encode the pack object header into a temporary buffer.
 lea rdi,[pack_header]
 mov rax,r14
 mov edx,eax
 and edx,15
 shl r12d,4
 or edx,r12d
 shr rax,4
 test rax,rax
 jz .header_last
 or dl,0x80
.header_last:
 mov [rdi],dl
 inc rdi
.header_more:
 test rax,rax
 jz .header_ready
 mov edx,eax
 and edx,0x7f
 shr rax,7
 test rax,rax
 jz .more_last
 or dl,0x80
.more_last:
 mov [rdi],dl
 inc rdi
 jmp .header_more
.header_ready:
 lea rbx,[pack_header]
 sub rdi,rbx
 mov r15,rdi
 ; Stored DEFLATE block: zlib header, block header/LEN/NLEN, data, Adler32.
 mov rax,r15
 add rax,r14
 add rax,11
 cmp [pack_left],rax
 jb .space
 mov rdi,[pack_cursor]
 lea rsi,[pack_header]
 mov rcx,r15
 rep movsb
 mov byte [rdi],0x78
 mov byte [rdi+1],0x01
 mov byte [rdi+2],0x01
 mov ax,r14w
 mov [rdi+3],ax
 not ax
 mov [rdi+5],ax
 add rdi,7
 mov rsi,r13
 mov rcx,r14
 rep movsb
 ; Adler-32, big endian.
 mov eax,1
 xor edx,edx
 xor ecx,ecx
.adler:
 cmp rcx,r14
 jae .adler_done
 movzx r8d,byte [r13+rcx]
 add eax,r8d
 cmp eax,65521
 jb .a_ready
 sub eax,65521
.a_ready:
 add edx,eax
 cmp edx,65521
 jb .b_ready
 sub edx,65521
.b_ready:
 inc rcx
 jmp .adler
.adler_done:
 shl edx,16
 or eax,edx
 bswap eax
 mov [rdi],eax
 add rdi,4
 mov rax,rdi
 sub rax,[pack_cursor]
 mov [pack_cursor],rdi
 sub [pack_left],rax
 inc dword [pack_written]
 xor eax,eax
 jmp .done
.duplicate:
 xor eax,eax
 jmp .done
.space: mov eax,VCS_ERR_NO_MEM
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
.done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Finalize checksum. RAX=status, RDX=complete pack length.
git_pack_finish:
 push rbx
 cmp dword [pack_unique],0
 je .exact_count
 mov eax,[pack_written]
 mov rdx,[pack_start]
 bswap eax
 mov [rdx+8],eax
 jmp .count_ready
.exact_count:
 mov eax,[pack_written]
 cmp eax,[pack_expected]
 jne .usage
.count_ready:
 cmp qword [pack_left],GIT_HASH_SIZE
 jb .space
 mov rbx,[pack_cursor]
 mov rdi,[pack_start]
 mov rsi,rbx
 sub rsi,rdi
 mov rdx,rbx
 call sha256_hash
 add qword [pack_cursor],GIT_HASH_SIZE
 sub qword [pack_left],GIT_HASH_SIZE
 mov rdx,[pack_cursor]
 sub rdx,[pack_start]
 xor eax,eax
 jmp .done
.space: mov eax,VCS_ERR_NO_MEM
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
.done:
 pop rbx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
