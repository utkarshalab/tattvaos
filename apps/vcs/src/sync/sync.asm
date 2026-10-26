; Resumable signed native bundle framing for non-blocking unet streams.
%include "include/vcs.inc"
%include "include/wire.inc"
%include "lib/crypto/uhash/sha256/sha256.inc"
bits 64
default rel
extern sha256_init,sha256_update,sha256_final
extern signing_public_from_seed,signing_sign,signing_verify
extern unet_send,unet_recv

struc vcs_xfer
 .state: resd 1
 .operation: resd 1
 .offset: resq 1
 .payload: resq 1
 .payload_len: resq 1
 .capacity: resq 1
 .objects: resq 1
 .repository: resq 1
 .io: resq 1
 .io_context: resq 1
 .trust: resq 1
 .header: resb VCS_WIRE_HEADER
 .hash: resb sha256_ctx_t_size
 .digest: resb 32
endstruc

section .text
global vcs_sync_send_begin,vcs_sync_receive_begin,vcs_sync_step
global vcs_sync_unet_send,vcs_sync_unet_receive

; rdi=state, esi=operation, rdx=payload, rcx=length, r8=object count,
; r9=repository id; stack: seed32, send(ctx,bytes,length), context.
vcs_sync_send_begin:
 push rbx
 push r12
 mov rbx,rdi
 mov r12,rdx
 test rbx,rbx
 jz .usage
 test r12,r12
 jz .usage
 test rcx,rcx
 jz .usage
 cmp rcx,VCS_WIRE_MAX_PAYLOAD
 ja .usage
 cmp esi,VCS_WIRE_FETCH
 jb .usage
 cmp esi,VCS_WIRE_PATCH
 ja .usage
 mov rax,[rsp+24]
 test rax,rax
 jz .usage
 mov rdx,[rsp+32]
 test rdx,rdx
 jz .usage
 mov dword [rbx+vcs_xfer.state],VCS_XFER_HEADER
 mov [rbx+vcs_xfer.operation],esi
 mov qword [rbx+vcs_xfer.offset],0
 mov [rbx+vcs_xfer.payload],r12
 mov [rbx+vcs_xfer.payload_len],rcx
 mov [rbx+vcs_xfer.capacity],rcx
 mov [rbx+vcs_xfer.objects],r8
 mov [rbx+vcs_xfer.repository],r9
 mov [rbx+vcs_xfer.io],rdx
 mov rdx,[rsp+40]
 mov [rbx+vcs_xfer.io_context],rdx
 mov qword [rbx+vcs_xfer.trust],0
 lea rdi,[rbx+vcs_xfer.header]
 xor eax,eax
 mov ecx,VCS_WIRE_HEADER/8
 rep stosq
 mov rax,VCS_WIRE_MAGIC
 mov [rbx+vcs_xfer.header+VW_MAGIC],rax
 mov dword [rbx+vcs_xfer.header+VW_VERSION],VCS_WIRE_VERSION
 mov eax,[rbx+vcs_xfer.operation]
 mov [rbx+vcs_xfer.header+VW_OPERATION],eax
 mov rax,[rbx+vcs_xfer.payload_len]
 mov [rbx+vcs_xfer.header+VW_PAYLOAD],rax
 mov rax,[rbx+vcs_xfer.objects]
 mov [rbx+vcs_xfer.header+VW_OBJECTS],rax
 mov rax,[rbx+vcs_xfer.repository]
 mov [rbx+vcs_xfer.header+VW_REPOSITORY],rax
 call sync_hash_frame
 lea rsi,[rbx+vcs_xfer.digest]
 lea rdi,[rbx+vcs_xfer.header+VW_DIGEST]
 mov ecx,32
 rep movsb
 lea rdi,[rbx+vcs_xfer.header+VW_PUBLIC]
 mov rsi,[rsp+24]
 call signing_public_from_seed
 test eax,eax
 jnz .corrupt
 lea rdi,[rbx+vcs_xfer.header+VW_DIGEST]
 mov rsi,[rsp+24]
 lea rdx,[rbx+vcs_xfer.header+VW_SIGNATURE]
 call signing_sign
 test eax,eax
 jnz .corrupt
 xor eax,eax
 jmp .done
.usage:
 mov eax,VCS_ERR_USAGE
 jmp .done
.corrupt:
 mov dword [rbx+vcs_xfer.state],VCS_XFER_FAILED
 mov eax,VCS_ERR_CORRUPT
.done:
 pop r12
 pop rbx
 ret

; rdi=state, rsi=storage, rdx=capacity, rcx=recv callback, r8=ctx,
; r9=trust(public32) callback. Trust is mandatory.
vcs_sync_receive_begin:
 test rdi,rdi
 jz .bad
 test rsi,rsi
 jz .bad
 test rdx,rdx
 jz .bad
 cmp rdx,VCS_WIRE_MAX_PAYLOAD
 ja .bad
 test rcx,rcx
 jz .bad
 test r9,r9
 jz .bad
 mov dword [rdi+vcs_xfer.state],VCS_XFER_HEADER
 mov qword [rdi+vcs_xfer.offset],0
 mov [rdi+vcs_xfer.payload],rsi
 mov [rdi+vcs_xfer.capacity],rdx
 mov qword [rdi+vcs_xfer.payload_len],0
 mov [rdi+vcs_xfer.io],rcx
 mov [rdi+vcs_xfer.io_context],r8
 mov [rdi+vcs_xfer.trust],r9
 xor eax,eax
 ret
.bad:
 mov eax,VCS_ERR_USAGE
 ret

; One non-blocking I/O attempt. 0=complete, 1=again; other values are errors.
vcs_sync_step:
 push rbx
 push r12
 push r13
 mov rbx,rdi
 test rbx,rbx
 jz .step_usage
 mov eax,[rbx+vcs_xfer.state]
 cmp eax,VCS_XFER_DONE
 je .complete
 cmp eax,VCS_XFER_FAILED
 je .io_error
 cmp eax,VCS_XFER_HEADER
 je .header
 cmp eax,VCS_XFER_PAYLOAD
 jne .bad_frame
 mov r12,[rbx+vcs_xfer.payload]
 mov r13,[rbx+vcs_xfer.payload_len]
 jmp .transfer
.header:
 lea r12,[rbx+vcs_xfer.header]
 mov r13,VCS_WIRE_HEADER
.transfer:
 mov rdx,r13
 sub rdx,[rbx+vcs_xfer.offset]
 jz .phase_done
 mov rsi,r12
 add rsi,[rbx+vcs_xfer.offset]
 mov rdi,[rbx+vcs_xfer.io_context]
 call [rbx+vcs_xfer.io]
 test rax,rax
 js .again
 jz .io_error
 mov rcx,r13
 sub rcx,[rbx+vcs_xfer.offset]
 cmp rax,rcx
 ja .bad_frame
 add [rbx+vcs_xfer.offset],rax
 cmp [rbx+vcs_xfer.offset],r13
 jb .again
.phase_done:
 cmp dword [rbx+vcs_xfer.state],VCS_XFER_HEADER
 jne .finish
 cmp qword [rbx+vcs_xfer.header+VW_MAGIC],VCS_WIRE_MAGIC
 jne .bad_frame
 cmp dword [rbx+vcs_xfer.header+VW_VERSION],VCS_WIRE_VERSION
 jne .bad_frame
 mov eax,[rbx+vcs_xfer.header+VW_OPERATION]
 cmp eax,VCS_WIRE_FETCH
 jb .bad_frame
 cmp eax,VCS_WIRE_PATCH
 ja .bad_frame
 mov [rbx+vcs_xfer.operation],eax
 mov rax,[rbx+vcs_xfer.header+VW_PAYLOAD]
 test rax,rax
 jz .bad_frame
 cmp rax,VCS_WIRE_MAX_PAYLOAD
 ja .bad_frame
 cmp rax,[rbx+vcs_xfer.capacity]
 ja .io_error
 mov [rbx+vcs_xfer.payload_len],rax
 mov rax,[rbx+vcs_xfer.header+VW_OBJECTS]
 mov [rbx+vcs_xfer.objects],rax
 mov rax,[rbx+vcs_xfer.header+VW_REPOSITORY]
 mov [rbx+vcs_xfer.repository],rax
 mov qword [rbx+vcs_xfer.offset],0
 mov dword [rbx+vcs_xfer.state],VCS_XFER_PAYLOAD
 jmp .again
.finish:
 cmp qword [rbx+vcs_xfer.trust],0
 je .mark_done
 call sync_hash_frame
 lea rdi,[rbx+vcs_xfer.digest]
 lea rsi,[rbx+vcs_xfer.header+VW_DIGEST]
 mov ecx,32
 repe cmpsb
 jne .bad_frame
 lea rdi,[rbx+vcs_xfer.header+VW_PUBLIC]
 call [rbx+vcs_xfer.trust]
 test eax,eax
 jnz .permission
 lea rdi,[rbx+vcs_xfer.header+VW_DIGEST]
 lea rsi,[rbx+vcs_xfer.header+VW_SIGNATURE]
 lea rdx,[rbx+vcs_xfer.header+VW_PUBLIC]
 call signing_verify
 test eax,eax
 jnz .permission
.mark_done:
 mov dword [rbx+vcs_xfer.state],VCS_XFER_DONE
.complete:
 mov edx,[rbx+vcs_xfer.operation]
 xor eax,eax
 jmp .step_done
.again:
 mov eax,VCS_XFER_AGAIN
 jmp .step_done
.step_usage:
 mov eax,VCS_ERR_USAGE
 jmp .step_done
.io_error:
 mov eax,VCS_ERR_IO
 jmp .fail
.bad_frame:
 mov eax,VCS_ERR_CORRUPT
 jmp .fail
.permission:
 mov eax,VCS_ERR_PERM
.fail:
 mov dword [rbx+vcs_xfer.state],VCS_XFER_FAILED
.step_done:
 pop r13
 pop r12
 pop rbx
 ret

; Digest binds metadata (bytes 0..39) and payload; signer fields are excluded.
sync_hash_frame:
 lea rdi,[rbx+vcs_xfer.hash]
 call sha256_init
 lea rdi,[rbx+vcs_xfer.hash]
 lea rsi,[rbx+vcs_xfer.header]
 mov edx,VW_DIGEST
 call sha256_update
 lea rdi,[rbx+vcs_xfer.hash]
 mov rsi,[rbx+vcs_xfer.payload]
 mov rdx,[rbx+vcs_xfer.payload_len]
 call sha256_update
 lea rdi,[rbx+vcs_xfer.hash]
 lea rsi,[rbx+vcs_xfer.digest]
 call sha256_final
 ret

vcs_sync_unet_send:
 xor ecx,ecx
 jmp unet_send
vcs_sync_unet_receive:
 xor ecx,ecx
 jmp unet_recv

section .note.GNU-stack noalloc noexec nowrite progbits
