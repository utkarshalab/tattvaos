bits 64
default rel
extern git_protocol_v2_parse_request,git_protocol_v2_haves
global upload_request_probe,upload_haves_probe,bridge_pkt_decode
global probe_status,probe_operation,probe_pointer,probe_flags,probe_count

section .bss
probe_status: resq 1
probe_operation: resq 1
probe_pointer: resq 1
probe_flags: resq 1
probe_count: resq 1

section .text
upload_request_probe:
 call git_protocol_v2_parse_request
 mov [probe_status],rax
 mov [probe_operation],rdx
 mov [probe_pointer],rcx
 mov [probe_flags],r8
 ret

upload_haves_probe:
 call git_protocol_v2_haves
 mov [probe_pointer],rax
 mov [probe_count],rdx
 ret

; Strict packet-line decoder used by the production parser.
bridge_pkt_decode:
 test rdi,rdi
 jz .usage
 cmp rsi,4
 jb .again
 xor eax,eax
 xor ecx,ecx
.nibble:
 movzx edx,byte [rdi+rcx]
 cmp dl,'0'
 jb .corrupt
 cmp dl,'9'
 jbe .number
 or dl,32
 cmp dl,'a'
 jb .corrupt
 cmp dl,'f'
 ja .corrupt
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
 jb .corrupt
 cmp rax,rsi
 ja .again
 mov r8,rax
 lea rdx,[rdi+4]
 lea rcx,[rax-4]
 xor r9d,r9d
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
.again:
 mov eax,1
 ret
.corrupt:
 mov eax,5
 ret
.usage:
 mov eax,8
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
