bits 64
default rel

extern vcs_sync_request_decode,vcs_sync_response_decode
global protocol_request_decode_probe,protocol_response_decode_probe

section .text
; RDI=payload, RSI=length, RDX=six-qword result buffer.
protocol_request_decode_probe:
 push rbx
 mov rbx,rdx
 call vcs_sync_request_decode
 mov [rbx],rax
 mov [rbx+8],rdx
 mov [rbx+16],rcx
 mov [rbx+24],r8
 mov [rbx+32],r9
 mov [rbx+40],r11
 pop rbx
 ret

; RDI=payload, RSI=length, RDX=four-qword result buffer.
protocol_response_decode_probe:
 push rbx
 mov rbx,rdx
 call vcs_sync_response_decode
 mov [rbx],rax
 mov [rbx+8],rdx
 mov [rbx+16],rcx
 mov [rbx+24],r8
 pop rbx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
