; Repository identities, rotation/revocation, and Ed25519 signature sidecars.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel

extern uxv_ready,uxv_nodes,uxv_find,uxv_free,uxv_commit
extern vcs_repo_discover,vcs_load_manifest,vcs_object_name
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_head,vcs_repo_last,vcs_object_path
extern signing_sign,signing_verify,signing_public_from_seed

section .bss
identity_writer: resq 1
identity_path: resb 240
identity_public: resb 32
identity_digest: resb 32
identity_number: resb 16
policy_path: resb 240
trust_path: resb 240

section .rodata
identity_suffix: db '/.vcs/identity',0
policy_suffix: db '/.vcs/policy',0
policy_magic: db 'UVCSPOL1'
identity_text: db 'identity '
identity_text_len equ $-identity_text
signed_text: db 'Signed '
signed_text_len equ $-signed_text
as_text: db ' as '
as_text_len equ $-as_text
verified_text: db 'Verified '
verified_text_len equ $-verified_text
required_text: db 'signed commits required',10
required_text_len equ $-required_text
optional_text: db 'unsigned commits allowed',10
optional_text_len equ $-optional_text
newline: db 10
hex_digits: db '0123456789abcdef'

section .text
global vcs_signature_policy,vcs_signature_prepare

; Repository commit policy. RDX=1 requires a signature, RDX=0 permits unsigned.
; Missing policy metadata means optional signing.
vcs_signature_policy:
 push rbx
 call make_policy_path
 test eax,eax
 jnz .policy_done
 lea rdi,[policy_path]
 call uxv_find
 test rax,rax
 jz .policy_optional
 cmp qword [rax+UV_TYPE],1
 jne .policy_bad
 cmp qword [rax+UV_SIZE],16
 jne .policy_bad
 mov rbx,0x314c4f5053435655
 cmp [rax+UV_DATA],rbx
 jne .policy_bad
 mov rdx,[rax+UV_DATA+8]
 cmp rdx,1
 ja .policy_bad
 xor eax,eax
 jmp .policy_done
.policy_optional:
 xor edx,edx
 xor eax,eax
 jmp .policy_done
.policy_bad:
 mov eax,VCS_ERR_CORRUPT
.policy_done:
 pop rbx
 ret

; Fill one caller-reserved signature node without committing it.
; rdi=commit ID, rsi=digest32, rdx=seed32, rcx=free node.
vcs_signature_prepare:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 mov r12,rsi
 mov r13,rdx
 mov r15,rcx
 test r13,r13
 jz .prepare_usage
 test r15,r15
 jz .prepare_usage
 call make_identity_path
 test eax,eax
 jnz .prepare_done
 lea rdi,[identity_path]
 call uxv_find
 test rax,rax
 jz .prepare_missing
 mov rbx,rax
 call validate_identity
 test eax,eax
 jnz .prepare_corrupt
 lea rdi,[identity_public]
 mov rsi,r13
 call signing_public_from_seed
 test eax,eax
 jnz .prepare_corrupt
 lea rdi,[identity_public]
 mov sil,'x'
 call make_key_path
 test eax,eax
 jnz .prepare_done
 lea rdi,[trust_path]
 call uxv_find
 test rax,rax
 jnz .prepare_permission
 lea rdi,[identity_public]
 lea rsi,[rbx+UV_DATA+16]
 mov ecx,32
 repe cmpsb
 jne .prepare_permission
 mov rdi,rbp
 mov sil,'s'
 call vcs_object_name
 test eax,eax
 jnz .prepare_usage
 mov rax,r15
 call clear_node
 mov rdi,r15
 lea rsi,[vcs_object_path]
 mov ecx,240
 rep movsb
 mov qword [r15+UV_TYPE],1
 mov qword [r15+UV_SIZE],VR_SIG_SIZE
 lea rdi,[r15+UV_DATA]
 mov rax,VR_SIG_MAGIC
 stosq
 mov rax,1
 stosq
 mov rax,rbp
 stosq
 mov rax,[rbx+UV_DATA+8]
 stosq
 lea rsi,[rbx+UV_DATA+16]
 mov ecx,32
 rep movsb
 mov rdi,r12
 mov rsi,r13
 lea rdx,[r15+UV_DATA+64]
 call signing_sign
 test eax,eax
 jnz .prepare_corrupt
 lea rdi,[r15+UV_DATA+128]
 lea rsi,[rbx+UV_DATA+48]
 mov ecx,32
 rep movsb
 xor eax,eax
 jmp .prepare_done
.prepare_usage: mov eax,VCS_ERR_USAGE
 jmp .prepare_done
.prepare_missing: mov eax,VCS_ERR_NOT_FOUND
 jmp .prepare_done
.prepare_permission: mov eax,VCS_ERR_PERM
 jmp .prepare_done
.prepare_corrupt: mov eax,VCS_ERR_CORRUPT
.prepare_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

global vcs_policy
; op 0 show, 1 require signed commits, 2 allow unsigned commits. RSI=writer.
vcs_policy:
 push rbx
 push r12
 sub rsp,8
 cmp rdi,2
 ja .policy_cmd_usage
 test rsi,rsi
 jz .policy_cmd_usage
 mov r12,rdi
 mov [identity_writer],rsi
 cmp qword [uxv_ready],1
 jne .policy_cmd_io
 call vcs_repo_discover
 test eax,eax
 jnz .policy_cmd_done
 cmp r12,1
 jne .policy_cmd_identity_ready
 call make_identity_path
 test eax,eax
 jnz .policy_cmd_done
 lea rdi,[identity_path]
 call uxv_find
 test rax,rax
 jz .policy_cmd_usage
 mov rbx,rax
 call validate_identity
 test eax,eax
 jnz .policy_cmd_corrupt
 lea rdi,[rbx+UV_DATA+16]
 mov sil,'x'
 call make_key_path
 test eax,eax
 jnz .policy_cmd_done
 lea rdi,[trust_path]
 call uxv_find
 test rax,rax
 jnz .policy_cmd_usage
.policy_cmd_identity_ready:
 call make_policy_path
 test eax,eax
 jnz .policy_cmd_done
 lea rdi,[policy_path]
 call uxv_find
 mov rbx,rax
 test r12,r12
 jz .policy_cmd_show
 test rbx,rbx
 jnz .policy_cmd_have
 call uxv_free
 test rax,rax
 jz .policy_cmd_capacity
 mov rbx,rax
.policy_cmd_have:
 cmp qword [rbx+UV_TYPE],0
 je .policy_cmd_write
 cmp qword [rbx+UV_TYPE],1
 jne .policy_cmd_corrupt
 cmp qword [rbx+UV_SIZE],16
 jne .policy_cmd_corrupt
 mov rax,0x314c4f5053435655
 cmp [rbx+UV_DATA],rax
 jne .policy_cmd_corrupt
 cmp qword [rbx+UV_DATA+8],1
 ja .policy_cmd_corrupt
.policy_cmd_write:
 mov rax,rbx
 call clear_node
 mov rdi,rbx
 lea rsi,[policy_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov qword [rbx+UV_SIZE],16
 mov rax,0x314c4f5053435655
 mov [rbx+UV_DATA],rax
 xor eax,eax
 cmp r12,1
 jne .policy_cmd_flag
 inc eax
.policy_cmd_flag:
 mov [rbx+UV_DATA+8],rax
 call uxv_commit
 test rax,rax
 js .policy_cmd_io
 jmp .policy_cmd_print
.policy_cmd_show:
 call vcs_signature_policy
 test eax,eax
 jnz .policy_cmd_done
 mov r12,rdx
.policy_cmd_print:
 lea rdi,[optional_text]
 mov esi,optional_text_len
 test r12,r12
 jz .policy_cmd_emit
 lea rdi,[required_text]
 mov esi,required_text_len
.policy_cmd_emit:
 call emit
 xor eax,eax
 jmp .policy_cmd_done
.policy_cmd_usage: mov eax,VCS_ERR_USAGE
 jmp .policy_cmd_done
.policy_cmd_capacity: mov eax,VCS_ERR_NO_MEM
 jmp .policy_cmd_done
.policy_cmd_corrupt: mov eax,VCS_ERR_CORRUPT
 jmp .policy_cmd_done
.policy_cmd_io: mov eax,VCS_ERR_IO
.policy_cmd_done:
 add rsp,8
 pop r12
 pop rbx
 ret

global vcs_verify_all
; RDI=writer. Every allocated commit must have a valid trusted signature.
vcs_verify_all:
 push rbx
 push r12
 push r13
 push r14
 push r15
 test rdi,rdi
 jz .all_usage
 mov r15,rdi
 cmp qword [uxv_ready],1
 jne .all_io
 call vcs_repo_discover
 test eax,eax
 jnz .all_done
 mov r12d,1
 mov r13,[vcs_repo_last]
.all_loop:
 cmp r12,r13
 ja .all_print_start
 mov edi,3
 mov rsi,r12
 xor edx,edx
 lea r8,[discard]
 call vcs_identity
 test eax,eax
 jnz .all_done
 inc r12
 jmp .all_loop
.all_print_start:
 mov r12d,1
.all_print:
 cmp r12,r13
 ja .all_ok
 mov edi,3
 mov rsi,r12
 xor edx,edx
 mov r8,r15
 call vcs_identity
 test eax,eax
 jnz .all_done
 inc r12
 jmp .all_print
.all_ok: xor eax,eax
 jmp .all_done
.all_usage: mov eax,VCS_ERR_USAGE
 jmp .all_done
.all_io: mov eax,VCS_ERR_IO
.all_done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

discard:
 ret

global vcs_identity
; op 0 show, 1 register(name, seed32), 2 sign(id-or-HEAD, seed32),
; 3 verify(id-or-HEAD), 4 rotate(name, seed32), 5 revoke(name).
vcs_identity:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 cmp rdi,5
 ja .usage
 test r8,r8
 jz .usage
 mov rbp,rdi
 mov r12,rsi
 mov r13,rdx
 mov [identity_writer],r8
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_identity_path
 test eax,eax
 jnz .usage
 lea rdi,[identity_path]
 call uxv_find
 mov rbx,rax
 cmp rbp,1
 je .register
 cmp rbp,4
 je .rotate
 cmp rbp,5
 je .revoke
 test rbx,rbx
 jz .missing
 call validate_identity
 test eax,eax
 jnz .corrupt
 cmp rbp,0
 je .show
 cmp rbp,2
 jne .select_target
 test r13,r13
 jz .usage
.select_target:
 mov r14,r12
 test r14,r14
 jnz .target
 mov r14,[vcs_repo_head]
.target:
 test r14,r14
 jz .missing
 mov rdi,r14
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rdi,r14
 call load_digest
 test eax,eax
 jnz .corrupt
 cmp rbp,3
 je .verify
 ; The supplied seed must belong to the registered repository identity.
 lea rdi,[identity_public]
 mov rsi,r13
 call signing_public_from_seed
 test eax,eax
 jnz .corrupt
 lea rdi,[identity_public]
 mov sil,'x'
 call make_key_path
 test eax,eax
 jnz .usage
 lea rdi,[trust_path]
 call uxv_find
 test rax,rax
 jnz .permission
 lea rdi,[identity_public]
 lea rsi,[rbx+UV_DATA+16]
 mov ecx,32
 repe cmpsb
 jne .permission
 mov rdi,r14
 mov sil,'s'
 call vcs_object_name
 test eax,eax
 jnz .usage
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jnz .conflict
 call uxv_free
 test rax,rax
 jz .capacity
 mov r15,rax
 call clear_node
 lea rdi,[r15]
 lea rsi,[vcs_object_path]
 mov ecx,240
 rep movsb
 mov qword [r15+UV_TYPE],1
 mov qword [r15+UV_SIZE],VR_SIG_SIZE
 lea rdi,[r15+UV_DATA]
 mov rax,VR_SIG_MAGIC
 stosq
 mov rax,1
 stosq
 mov rax,r14
 stosq
 mov rax,[rbx+UV_DATA+8]
 stosq
 lea rsi,[rbx+UV_DATA+16]
 mov ecx,32
 rep movsb
 ; Signature starts at byte 64; bytes 128..159 hold the identity name.
 lea rdi,[identity_digest]
 mov rsi,r13
 lea rdx,[r15+UV_DATA+64]
 call signing_sign
 test eax,eax
 jnz .corrupt
 lea rdi,[r15+UV_DATA+128]
 lea rsi,[rbx+UV_DATA+48]
 mov ecx,32
 rep movsb
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[signed_text]
 mov esi,signed_text_len
 call emit
 mov rdi,r14
 call print_id
 lea rdi,[as_text]
 mov esi,as_text_len
 call emit
 lea rdi,[rbx+UV_DATA+48]
 call print_string
 call print_newline
 jmp .ok

.verify:
 mov rdi,r14
 mov sil,'s'
 call vcs_object_name
 test eax,eax
 jnz .usage
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .missing
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],VR_SIG_SIZE
 jne .corrupt
 lea r15,[rax+UV_DATA]
 mov rdx,VR_SIG_MAGIC
 cmp [r15],rdx
 jne .corrupt
 cmp qword [r15+8],1
 jne .corrupt
 cmp [r15+16],r14
 jne .corrupt
 mov rcx,[r15+24]
 cmp rcx,[rbx+UV_DATA+8]
 jne .corrupt
 test rcx,rcx
 jz .corrupt
 cmp rcx,VR_ID_NAME_MAX
 ja .corrupt
 cmp byte [r15+128+rcx],0
 jne .corrupt
 ; Revocation wins over both the active identity and retained rotation keys.
 lea rdi,[r15+32]
 mov sil,'x'
 call make_key_path
 test eax,eax
 jnz .corrupt
 lea rdi,[trust_path]
 call uxv_find
 test rax,rax
 jnz .permission
 mov rdi,rbx
 mov rsi,r15
 call identity_matches_signature
 test eax,eax
 jnz .trusted
 lea rdi,[r15+32]
 mov sil,'i'
 call make_key_path
 test eax,eax
 jnz .corrupt
 lea rdi,[trust_path]
 call uxv_find
 test rax,rax
 jz .permission
 mov rdi,rax
 mov rsi,r15
 call identity_matches_signature
 test eax,eax
 jz .permission
.trusted:
 lea rdi,[identity_digest]
 lea rsi,[r15+64]
 lea rdx,[r15+32]
 call signing_verify
 test eax,eax
 jnz .corrupt
 lea rdi,[verified_text]
 mov esi,verified_text_len
 call emit
 mov rdi,r14
 call print_id
 lea rdi,[as_text]
 mov esi,as_text_len
 call emit
 lea rdi,[r15+128]
 call print_string
 call print_newline
 jmp .ok

.rotate:
 test rbx,rbx
 jz .missing
 call validate_identity
 test eax,eax
 jnz .corrupt
 test r12,r12
 jz .usage
 test r13,r13
 jz .usage
 mov rdi,r12
 call valid_name
 test eax,eax
 jz .usage
 mov r14,rdx
 mov rdi,r12
 call identity_name_exists
 test eax,eax
 jnz .conflict
 lea rdi,[identity_public]
 mov rsi,r13
 call signing_public_from_seed
 test eax,eax
 jnz .corrupt
 lea rdi,[identity_public]
 lea rsi,[rbx+UV_DATA+16]
 mov ecx,32
 repe cmpsb
 je .conflict
 lea rdi,[identity_public]
 mov sil,'x'
 call make_key_path
 test eax,eax
 jnz .usage
 lea rdi,[trust_path]
 call uxv_find
 test rax,rax
 jnz .permission
 ; Preserve the previous trusted key before replacing the active identity.
 lea rdi,[rbx+UV_DATA+16]
 mov sil,'i'
 call make_key_path
 test eax,eax
 jnz .usage
 lea rdi,[trust_path]
 call uxv_find
 test rax,rax
 jz .rotate_allocate
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],VR_ID_SIZE
 jne .corrupt
 push rbx
 lea rdi,[rax+UV_DATA]
 lea rsi,[rbx+UV_DATA]
 mov ecx,VR_ID_SIZE
 repe cmpsb
 pop rbx
 jne .corrupt
 jmp .rotate_write
.rotate_allocate:
 call uxv_free
 test rax,rax
 jz .capacity
 mov r15,rax
 mov rax,r15
 call clear_node
 mov rdi,r15
 lea rsi,[trust_path]
 mov ecx,240
 rep movsb
 mov qword [r15+UV_TYPE],1
 mov qword [r15+UV_SIZE],VR_ID_SIZE
 lea rdi,[r15+UV_DATA]
 lea rsi,[rbx+UV_DATA]
 mov ecx,VR_ID_SIZE
 rep movsb
.rotate_write:
 mov rax,rbx
 call clear_node
 lea rdi,[rbx]
 lea rsi,[identity_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov qword [rbx+UV_SIZE],VR_ID_SIZE
 lea rdi,[rbx+UV_DATA]
 mov rax,VR_ID_MAGIC
 stosq
 mov rax,r14
 stosq
 lea rsi,[identity_public]
 mov ecx,32
 rep movsb
 mov rsi,r12
 mov rcx,r14
 rep movsb
 mov byte [rdi],0
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[identity_text]
 mov esi,identity_text_len
 call emit
 mov rdi,r12
 call print_string
 call print_newline
 jmp .ok

.revoke:
 test r12,r12
 jz .usage
 ; The active key or any retained rotation key can be selected by name.
 lea r14,[uxv_nodes+UV_NODE]
.revoke_scan:
 cmp qword [r14+UV_TYPE],1
 jne .revoke_next
 cmp qword [r14+UV_SIZE],VR_ID_SIZE
 jne .revoke_next
 mov rax,VR_ID_MAGIC
 cmp [r14+UV_DATA],rax
 jne .revoke_next
 lea rdi,[r14+UV_DATA+48]
 mov rsi,r12
 call same_string
 test eax,eax
 jnz .revoke_found
.revoke_next:
 add r14,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp r14,rax
 jb .revoke_scan
 jmp .missing
.revoke_found:
 lea rdi,[r14+UV_DATA+16]
 mov sil,'x'
 call make_key_path
 test eax,eax
 jnz .usage
 lea rdi,[trust_path]
 call uxv_find
 test rax,rax
 jz .revoke_allocate
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],32
 jne .corrupt
 lea rdi,[rax+UV_DATA]
 lea rsi,[r14+UV_DATA+16]
 mov ecx,32
 repe cmpsb
 jne .corrupt
 jmp .ok
.revoke_allocate:
 call uxv_free
 test rax,rax
 jz .capacity
 mov r15,rax
 mov rax,r15
 call clear_node
 mov rdi,r15
 lea rsi,[trust_path]
 mov ecx,240
 rep movsb
 mov qword [r15+UV_TYPE],1
 mov qword [r15+UV_SIZE],32
 lea rdi,[r15+UV_DATA]
 lea rsi,[r14+UV_DATA+16]
 mov ecx,32
 rep movsb
 call uxv_commit
 test rax,rax
 js .io
 jmp .ok

.register:
 test rbx,rbx
 jnz .conflict
 test r12,r12
 jz .usage
 test r13,r13
 jz .usage
 mov rdi,r12
 call valid_name
 test eax,eax
 jz .usage
 mov r14,rdx
 lea rdi,[identity_public]
 mov rsi,r13
 call signing_public_from_seed
 test eax,eax
 jnz .corrupt
 call uxv_free
 test rax,rax
 jz .capacity
 mov rbx,rax
 call clear_node
 lea rdi,[rbx]
 lea rsi,[identity_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov qword [rbx+UV_SIZE],VR_ID_SIZE
 lea rdi,[rbx+UV_DATA]
 mov rax,VR_ID_MAGIC
 stosq
 mov rax,r14
 stosq
 lea rsi,[identity_public]
 mov ecx,32
 rep movsb
 mov rsi,r12
 mov rcx,r14
 rep movsb
 mov byte [rdi],0
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[identity_text]
 mov esi,identity_text_len
 call emit
 mov rdi,r12
 call print_string
 call print_newline
 jmp .ok

.show:
 lea rdi,[identity_text]
 mov esi,identity_text_len
 call emit
 lea rdi,[rbx+UV_DATA+48]
 call print_string
 lea rdi,[as_text]
 mov esi,as_text_len
 call emit
 lea r12,[rbx+UV_DATA+16]
 mov r13d,32
.show_byte:
 movzx eax,byte [r12]
 mov edx,eax
 shr edx,4
 lea rdi,[identity_number]
 lea rcx,[hex_digits]
 mov dl,[rcx+rdx]
 mov [rdi],dl
 and eax,15
 mov al,[rcx+rax]
 mov [rdi+1],al
 mov esi,2
 call emit
 inc r12
 dec r13
 jnz .show_byte
 call print_newline
 jmp .ok

.ok: xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.missing: mov eax,VCS_ERR_NOT_FOUND
 jmp .done
.capacity: mov eax,VCS_ERR_NO_MEM
 jmp .done
.conflict: mov eax,VCS_ERR_CONFLICT
 jmp .done
.permission: mov eax,VCS_ERR_PERM
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

; RAX = 0/invalid or identity node. Returns EAX=0 when valid.
validate_identity:
 cmp qword [rbx+UV_TYPE],1
 jne .bad
 cmp qword [rbx+UV_SIZE],VR_ID_SIZE
 jne .bad
 mov rax,VR_ID_MAGIC
 cmp [rbx+UV_DATA],rax
 jne .bad
 mov rdx,[rbx+UV_DATA+8]
 test rdx,rdx
 jz .bad
 cmp rdx,VR_ID_NAME_MAX
 ja .bad
 cmp byte [rbx+UV_DATA+48+rdx],0
 jne .bad
 xor eax,eax
 ret
.bad: mov eax,1
 ret

; RDI=identity node, RSI=signature payload. EAX=1 exact trusted match.
identity_matches_signature:
 cmp qword [rdi+UV_TYPE],1
 jne .no
 cmp qword [rdi+UV_SIZE],VR_ID_SIZE
 jne .no
 mov rax,VR_ID_MAGIC
 cmp [rdi+UV_DATA],rax
 jne .no
 mov rax,[rdi+UV_DATA+8]
 cmp rax,[rsi+24]
 jne .no
 push rdi
 push rsi
 lea rdi,[rdi+UV_DATA+16]
 lea rsi,[rsi+32]
 mov ecx,32
 repe cmpsb
 pop rsi
 pop rdi
 jne .no
 lea rdi,[rdi+UV_DATA+48]
 lea rsi,[rsi+128]
 mov ecx,32
 repe cmpsb
 jne .no
 mov eax,1
 ret
.no: xor eax,eax
 ret

same_string:
 xor ecx,ecx
.loop:
 mov al,[rdi+rcx]
 cmp al,[rsi+rcx]
 jne .no
 test al,al
 jz .yes
 inc ecx
 cmp ecx,32
 jb .loop
.no: xor eax,eax
 ret
.yes: mov eax,1
 ret

identity_name_exists:
 push rbx
 mov rbx,rdi
 lea rdx,[uxv_nodes+UV_NODE]
.scan:
 cmp qword [rdx+UV_TYPE],1
 jne .next
 cmp qword [rdx+UV_SIZE],VR_ID_SIZE
 jne .next
 mov rax,VR_ID_MAGIC
 cmp [rdx+UV_DATA],rax
 jne .next
 push rdx
 lea rdi,[rdx+UV_DATA+48]
 mov rsi,rbx
 call same_string
 pop rdx
 test eax,eax
 jnz .found
.next:
 add rdx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rdx,rax
 jb .scan
 xor eax,eax
 pop rbx
 ret
.found:
 mov eax,1
 pop rbx
 ret

; Returns length in RDX and EAX=1, or EAX=0.
valid_name:
 xor edx,edx
.loop:
 movzx eax,byte [rdi+rdx]
 test al,al
 jz .end
 cmp rdx,VR_ID_NAME_MAX
 jae .bad
 cmp al,'-'
 je .good
 cmp al,'.'
 je .good
 cmp al,'_'
 je .good
 cmp al,'0'
 jb .bad
 cmp al,'9'
 jbe .good
 or al,32
 cmp al,'a'
 jb .bad
 cmp al,'z'
 ja .bad
.good:
 inc rdx
 jmp .loop
.end:
 test rdx,rdx
 setnz al
 movzx eax,al
 ret
.bad: xor eax,eax
 ret

make_identity_path:
 lea rdi,[identity_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 mov rcx,[vcs_repo_root_size]
 cmp rcx,225
 ja .bad
 cmp rcx,1
 jne .copy
 xor ecx,ecx
.copy:
 lea rsi,[vcs_repo_root]
 lea rdi,[identity_path]
 rep movsb
 lea rsi,[identity_suffix]
.suffix:
 lodsb
 stosb
 test al,al
 jnz .suffix
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_USAGE
 ret

make_policy_path:
 lea rdi,[policy_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 mov rcx,[vcs_repo_root_size]
 cmp rcx,227
 ja .bad
 cmp rcx,1
 jne .copy
 xor ecx,ecx
.copy:
 lea rsi,[vcs_repo_root]
 lea rdi,[policy_path]
 rep movsb
 lea rsi,[policy_suffix]
.suffix:
 lodsb
 stosb
 test al,al
 jnz .suffix
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_USAGE
 ret

; RDI=public key, SIL='i' retained identity or 'x' revocation marker.
; The 64-bit path prefix is only an index; record bytes resolve collisions.
make_key_path:
 mov r8,rdi
 mov r9b,sil
 lea rdi,[trust_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 mov rcx,[vcs_repo_root_size]
 cmp rcx,216
 ja .bad
 cmp rcx,1
 jne .copy
 xor ecx,ecx
.copy:
 lea rsi,[vcs_repo_root]
 lea rdi,[trust_path]
 rep movsb
 mov byte [rdi],'/'
 mov byte [rdi+1],'.'
 mov byte [rdi+2],'v'
 mov byte [rdi+3],'c'
 mov byte [rdi+4],'s'
 mov byte [rdi+5],'/'
 mov [rdi+6],r9b
 add rdi,7
 mov rsi,r8
 mov ecx,8
 lea r10,[hex_digits]
.byte:
 lodsb
 movzx edx,al
 shr edx,4
 mov dl,[r10+rdx]
 mov [rdi],dl
 movzx edx,al
 and edx,15
 mov dl,[r10+rdx]
 mov [rdi+1],dl
 add rdi,2
 loop .byte
 mov byte [rdi],0
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_USAGE
 ret

load_digest:
 mov sil,'h'
 call vcs_object_name
 test eax,eax
 jnz .bad
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 cmp qword [rax+UV_SIZE],32
 jne .bad
 lea rsi,[rax+UV_DATA]
 lea rdi,[identity_digest]
 mov ecx,32
 rep movsb
 xor eax,eax
 ret
.bad: mov eax,1
 ret

clear_node:
 mov rdi,rax
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 ret

emit:
 push rax
 call [identity_writer]
 pop rax
 ret

print_string:
 mov rsi,rdi
.length:
 cmp byte [rsi],0
 je .write
 inc rsi
 jmp .length
.write:
 sub rsi,rdi
 jmp emit

print_newline:
 lea rdi,[newline]
 mov esi,1
 jmp emit

print_id:
 mov rax,rdi
 lea rdi,[identity_number]
 mov ecx,16
 lea r8,[hex_digits]
.digit:
 rol rax,4
 mov rdx,rax
 and edx,15
 mov dl,[r8+rdx]
 mov [rdi],dl
 inc rdi
 loop .digit
 lea rdi,[identity_number]
 mov esi,16
 jmp emit

section .note.GNU-stack noalloc noexec nowrite progbits
