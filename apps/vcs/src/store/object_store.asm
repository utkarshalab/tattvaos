; Scalable v3 chunk envelope/extent writer, reader and verifier.
%include "include/vcs.inc"
%define VCS_OBJECT_STORE_IMPLEMENTATION
%include "include/object_store.inc"
%include "lib/crypto/uhash/sha256/sha256.inc"
bits 64
default rel

extern sha256_init,sha256_update,sha256_final,sha256_hash

section .rodata
object_magic: db 'UVCSOBJ3'
extent_magic: db 'UVCSEXT1'
hash_magic:   db 'UVCSHSH1'

section .text
global vcs_object_id,vcs_chunk_object_id,vcs_chunk_object_write
global vcs_chunk_object_read,vcs_chunk_object_verify

; EDI=object type, RSI=canonical payload, RDX=length, RCX=32-byte output.
; This hashes already-validated canonical bytes; type-specific codecs own
; canonical validation before accepting the resulting ID.
vcs_object_id:
 push rbx
 push r12
 push r13
 push r14
 sub rsp,136
 test edi,edi
 jz .usage
 cmp edi,10
 ja .usage
 test rdx,rdx
 jz .payload_ok
 test rsi,rsi
 jz .usage
.payload_ok:
 test rcx,rcx
 jz .usage
 mov ebx,edi
 mov r12,rsi
 mov r13,rdx
 mov r14,rcx
 lea rdi,[rsp+112]
 lea rsi,[hash_magic]
 mov ecx,8
 rep movsb
 mov word [rsp+120],1
 mov [rsp+122],bx
 mov dword [rsp+124],0
 mov [rsp+128],r13
 lea rdi,[rsp]
 call sha256_init
 lea rdi,[rsp]
 lea rsi,[rsp+112]
 mov edx,24
 call sha256_update
 lea rdi,[rsp]
 mov rsi,r12
 mov rdx,r13
 test rdx,rdx
 jz .final
 call sha256_update
.final:
 lea rdi,[rsp]
 mov rsi,r14
 call sha256_final
 xor eax,eax
 jmp .done
.usage:
 mov eax,VCS_ERR_USAGE
 jmp .done
.done:
 add rsp,136
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RDI=chunk bytes, RSI=length, RDX=32-byte output. RAX=VCS status.
vcs_chunk_object_id:
 test rdi,rdi
 jz .chunk_usage
 test rdx,rdx
 jz .chunk_usage
 test rsi,rsi
 jz .chunk_corrupt
 cmp rsi,VCS_CHUNK_OBJECT_MAX
 ja .chunk_corrupt
 mov rcx,rdx
 mov rdx,rsi
 mov rsi,rdi
 mov edi,VCS_OBJ_CHUNK
 jmp vcs_object_id
.chunk_usage:
 mov eax,VCS_ERR_USAGE
 ret
.chunk_corrupt:
 mov eax,VCS_ERR_CORRUPT
 ret

; RDI=vcs_chunk_io. Builds the envelope and contiguous extent images only
; after every pointer, capacity and locator has passed preflight.
vcs_chunk_object_write:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,40
 test rdi,rdi
 jz .usage
 mov rbx,rdi
 mov r12,[rbx+vcs_chunk_io.payload]
 mov r13,[rbx+vcs_chunk_io.payload_length]
 mov r14,[rbx+vcs_chunk_io.envelope]
 mov r15,[rbx+vcs_chunk_io.extents]
 mov rbp,[rbx+vcs_chunk_io.locators]
 test r12,r12
 jz .usage
 test r14,r14
 jz .usage
 test r15,r15
 jz .usage
 test rbp,rbp
 jz .usage
 mov rax,[rbx+vcs_chunk_io.object_id]
 test rax,rax
 jz .usage
 test r13,r13
 jz .corrupt
 cmp r13,VCS_CHUNK_OBJECT_MAX
 ja .corrupt
 mov rax,r13
 add rax,VCS_OBJECT_EXTENT_PAYLOAD-1
 xor edx,edx
 mov ecx,VCS_OBJECT_EXTENT_PAYLOAD
 div rcx
 mov r10,rax
 mov [rsp+32],rax
 cmp [rbx+vcs_chunk_io.extent_capacity],r10
 jb .space
 cmp qword [rbx+vcs_chunk_io.transaction],0
 je .corrupt
 xor ecx,ecx
.locator_outer:
 cmp rcx,r10
 jae .locator_ok
 mov rax,[rbp+rcx*8]
 test rax,rax
 jz .corrupt
 xor edx,edx
.locator_inner:
 cmp rdx,rcx
 jae .locator_next
 cmp rax,[rbp+rdx*8]
 je .corrupt
 inc rdx
 jmp .locator_inner
.locator_next:
 inc rcx
 jmp .locator_outer
.locator_ok:
 mov rdi,r12
 mov rsi,r13
 lea rdx,[rsp]
 call vcs_chunk_object_id
 test eax,eax
 jnz .done
 mov rdi,r14
 xor eax,eax
 mov ecx,VCS_OBJECT_ENVELOPE_BYTES
 rep stosb
 mov rdi,r15
 mov rax,r10
 shl rax,12
 mov rcx,rax
 xor eax,eax
 rep stosb
 mov rax,[object_magic]
 mov [r14],rax
 mov word [r14+8],1
 mov word [r14+10],VCS_OBJECT_ENVELOPE_BYTES
 mov word [r14+12],VCS_OBJ_CHUNK
 mov word [r14+14],1
 mov [r14+24],r13
 mov [r14+32],r10
 mov rdi,r14
 add rdi,40
 lea rsi,[rsp]
 mov ecx,VCS_OBJECT_HASH_BYTES
 rep movsb
 mov rax,[rbp]
 mov [r14+72],rax
 mov rax,[rbx+vcs_chunk_io.transaction]
 mov [r14+80],rax
 mov rdi,r14
 mov esi,88
 lea rdx,[r14+88]
 call sha256_hash
 mov r10,[rsp+32]
 xor r8d,r8d
 xor r9d,r9d
.extent_loop:
 cmp r8,r10
 jae .write_id
 mov rax,r8
 shl rax,12
 lea r11,[r15+rax]
 mov rax,[extent_magic]
 mov [r11],rax
 mov word [r11+8],1
 mov rax,r13
 sub rax,r9
 cmp rax,VCS_OBJECT_EXTENT_PAYLOAD
 jbe .extent_size
 mov eax,VCS_OBJECT_EXTENT_PAYLOAD
.extent_size:
 mov [r11+12],eax
 mov rdi,r11
 add rdi,16
 lea rsi,[rsp]
 mov ecx,VCS_OBJECT_HASH_BYTES
 rep movsb
 mov [r11+48],r8
 lea rdx,[r8+1]
 cmp rdx,r10
 jae .extent_final
 mov rax,[rbp+rdx*8]
 mov [r11+56],rax
 jmp .extent_copy
.extent_final:
 mov word [r11+10],1
.extent_copy:
 mov edx,[r11+12]
 lea rdi,[r11+64]
 lea rsi,[r12+r9]
 mov rcx,rdx
 rep movsb
 add r9,rdx
 inc r8
 jmp .extent_loop
.write_id:
 mov rdi,[rbx+vcs_chunk_io.object_id]
 lea rsi,[rsp]
 mov ecx,VCS_OBJECT_HASH_BYTES
 rep movsb
 mov [rbx+vcs_chunk_io.result_length],r13
 xor eax,eax
 jmp .done
.space:
 mov eax,VCS_ERR_NO_MEM
 jmp .done
.usage:
 mov eax,VCS_ERR_USAGE
 jmp .done
.corrupt:
 mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,40
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

vcs_chunk_object_read:
 mov esi,1
 jmp chunk_read_common

vcs_chunk_object_verify:
 xor esi,esi

; RDI=vcs_chunk_io, ESI=copy result when nonzero.
chunk_read_common:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,232
 test rdi,rdi
 jz .usage
 mov rbx,rdi
 mov ebp,esi
 mov r12,[rbx+vcs_chunk_io.envelope]
 mov r13,[rbx+vcs_chunk_io.extents]
 mov r14,[rbx+vcs_chunk_io.locators]
 mov r15,[rbx+vcs_chunk_io.object_id]
 test r12,r12
 jz .usage
 test r13,r13
 jz .usage
 test r14,r14
 jz .usage
 test r15,r15
 jz .usage
 test ebp,ebp
 jz .header
 mov rax,[rbx+vcs_chunk_io.output]
 test rax,rax
 jz .usage
.header:
 mov rax,[object_magic]
 cmp [r12],rax
 jne .corrupt
 cmp word [r12+8],1
 jne .corrupt
 cmp word [r12+10],VCS_OBJECT_ENVELOPE_BYTES
 jne .corrupt
 cmp word [r12+12],VCS_OBJ_CHUNK
 jne .corrupt
 cmp word [r12+14],1
 jne .corrupt
 cmp dword [r12+16],0
 jne .corrupt
 cmp dword [r12+20],0
 jne .corrupt
 cmp qword [r12+80],0
 je .corrupt
 cmp qword [r12+120],0
 jne .corrupt
 mov rax,[r12+24]
 test rax,rax
 jz .corrupt
 cmp rax,VCS_CHUNK_OBJECT_MAX
 ja .corrupt
 mov [rsp+200],rax
 add rax,VCS_OBJECT_EXTENT_PAYLOAD-1
 xor edx,edx
 mov ecx,VCS_OBJECT_EXTENT_PAYLOAD
 div rcx
 mov r10,rax
 mov [rsp+208],rax
 cmp [r12+32],r10
 jne .corrupt
 cmp [rbx+vcs_chunk_io.extent_capacity],r10
 jb .space
 xor ecx,ecx
.read_locator_outer:
 cmp rcx,r10
 jae .read_locators_ok
 mov rax,[r14+rcx*8]
 test rax,rax
 jz .corrupt
 xor edx,edx
.read_locator_inner:
 cmp rdx,rcx
 jae .read_locator_next
 cmp rax,[r14+rdx*8]
 je .corrupt
 inc rdx
 jmp .read_locator_inner
.read_locator_next:
 inc rcx
 jmp .read_locator_outer
.read_locators_ok:
 mov rax,[r14]
 test rax,rax
 jz .corrupt
 cmp [r12+72],rax
 jne .corrupt
 mov rdi,r12
 mov esi,88
 lea rdx,[rsp]
 call sha256_hash
 xor eax,eax
 mov rax,[rsp]
 xor rax,[r12+88]
 mov rcx,[rsp+8]
 xor rcx,[r12+96]
 or rax,rcx
 mov rcx,[rsp+16]
 xor rcx,[r12+104]
 or rax,rcx
 mov rcx,[rsp+24]
 xor rcx,[r12+112]
 or rax,rcx
 jnz .corrupt
 mov rax,[r12+40]
 xor rax,[r15]
 mov rcx,[r12+48]
 xor rcx,[r15+8]
 or rax,rcx
 mov rcx,[r12+56]
 xor rcx,[r15+16]
 or rax,rcx
 mov rcx,[r12+64]
 xor rcx,[r15+24]
 or rax,rcx
 jnz .corrupt
 lea rdi,[rsp+64]
 lea rsi,[hash_magic]
 mov ecx,8
 rep movsb
 mov word [rsp+72],1
 mov word [rsp+74],VCS_OBJ_CHUNK
 mov dword [rsp+76],0
 mov rax,[rsp+200]
 mov [rsp+80],rax
 lea rdi,[rsp+88]
 call sha256_init
 lea rdi,[rsp+88]
 lea rsi,[rsp+64]
 mov edx,24
 call sha256_update
 mov qword [rsp+216],0
 mov qword [rsp+224],0
.verify_extent:
 mov r8,[rsp+216]
 mov r9,[rsp+224]
 mov r10,[rsp+208]
 cmp r8,r10
 jae .finish_hash
 mov rax,r8
 shl rax,12
 lea r11,[r13+rax]
 mov rax,[extent_magic]
 cmp [r11],rax
 jne .corrupt
 cmp word [r11+8],1
 jne .corrupt
 movzx eax,word [r11+10]
 mov rdx,r8
 inc rdx
 cmp rdx,r10
 jne .not_final
 cmp eax,1
 jne .corrupt
 cmp qword [r11+56],0
 jne .corrupt
 jmp .flags_ok
.not_final:
 test eax,eax
 jne .corrupt
 mov rax,[r14+rdx*8]
 test rax,rax
 jz .corrupt
 cmp [r11+56],rax
 jne .corrupt
.flags_ok:
 mov eax,[r11+12]
 test eax,eax
 jz .corrupt
 cmp eax,VCS_OBJECT_EXTENT_PAYLOAD
 ja .corrupt
 mov rdx,[rsp+200]
 sub rdx,r9
 cmp rdx,VCS_OBJECT_EXTENT_PAYLOAD
 jbe .expected_size
 mov edx,VCS_OBJECT_EXTENT_PAYLOAD
.expected_size:
 cmp rax,rdx
 jne .corrupt
 mov rcx,[r11+16]
 xor rcx,[r15]
 mov rax,[r11+24]
 xor rax,[r15+8]
 or rcx,rax
 mov rax,[r11+32]
 xor rax,[r15+16]
 or rcx,rax
 mov rax,[r11+40]
 xor rax,[r15+24]
 or rcx,rax
 jnz .corrupt
 cmp [r11+48],r8
 jne .corrupt
 mov eax,[r11+12]
 lea rdi,[rsp+88]
 lea rsi,[r11+64]
 mov rdx,rax
 call sha256_update
 mov r8,[rsp+216]
 mov r9,[rsp+224]
 mov rax,r8
 shl rax,12
 lea r11,[r13+rax]
 mov eax,[r11+12]
 mov ecx,VCS_OBJECT_EXTENT_PAYLOAD
 sub ecx,eax
 lea rdi,[r11+64+rax]
 xor eax,eax
.padding:
 test ecx,ecx
 jz .extent_done
 or al,[rdi]
 inc rdi
 dec ecx
 jmp .padding
.extent_done:
 test al,al
 jnz .corrupt
 mov eax,[r11+12]
 add r9,rax
 inc r8
 mov [rsp+216],r8
 mov [rsp+224],r9
 jmp .verify_extent
.finish_hash:
 mov r9,[rsp+224]
 cmp r9,[rsp+200]
 jne .corrupt
 lea rdi,[rsp+88]
 lea rsi,[rsp+32]
 call sha256_final
 mov rax,[rsp+32]
 xor rax,[r15]
 mov rcx,[rsp+40]
 xor rcx,[r15+8]
 or rax,rcx
 mov rcx,[rsp+48]
 xor rcx,[r15+16]
 or rax,rcx
 mov rcx,[rsp+56]
 xor rcx,[r15+24]
 or rax,rcx
 jnz .corrupt
 test ebp,ebp
 jz .success
 mov rax,[rsp+200]
 cmp [rbx+vcs_chunk_io.output_capacity],rax
 jb .space
 mov qword [rsp+216],0
 mov qword [rsp+224],0
 mov rdi,[rbx+vcs_chunk_io.output]
.copy_extent:
 mov r8,[rsp+216]
 mov r9,[rsp+224]
 mov r10,[rsp+208]
 cmp r8,r10
 jae .copy_done
 mov rax,r8
 shl rax,12
 lea r11,[r13+rax]
 mov ecx,[r11+12]
 lea rsi,[r11+64]
 rep movsb
 mov eax,[r11+12]
 add r9,rax
 inc r8
 mov [rsp+216],r8
 mov [rsp+224],r9
 jmp .copy_extent
.copy_done:
 mov r9,[rsp+224]
 mov [rbx+vcs_chunk_io.result_length],r9
.success:
 xor eax,eax
 jmp .done
.space:
 mov eax,VCS_ERR_NO_MEM
 jmp .done
.usage:
 mov eax,VCS_ERR_USAGE
 jmp .done
.corrupt:
 mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,232
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
