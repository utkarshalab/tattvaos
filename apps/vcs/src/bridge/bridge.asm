; Minimal, allocation-free Git packet-line compatibility boundary.
; Repository conversion remains explicitly unsupported until pack/index
; codecs exist; callers must never receive false success.
%include "include/vcs.inc"
%include "include/wire.inc"
bits 64
default rel

section .rodata
hex: db '0123456789abcdef'

section .text
global bridge_pkt_encode,bridge_pkt_decode
global bridge_git_import,bridge_git_export,bridge_git_serve

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

; Pack/index mapping and smart-protocol negotiation are intentionally not
; claimed yet. These entry points now fail safely instead of returning OK.
bridge_git_import:
bridge_git_export:
bridge_git_serve:
 mov eax,VCS_ERR_UNSUPPORTED
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
