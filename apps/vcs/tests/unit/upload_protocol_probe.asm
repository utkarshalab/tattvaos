bits 64
default rel
extern git_protocol_v2_advertise,git_protocol_v2_ls_refs
extern git_protocol_v2_object_info,git_protocol_v2_acknowledge
extern git_protocol_v2_fetch
global advertise_probe,ls_refs_probe,object_info_probe,acknowledge_probe,fetch_probe
global bridge_pkt_encode,git_history_shallow,git_history_unshallow
global probe_status,probe_length,mock_shallow,mock_unshallow

section .bss
probe_status: resq 1
probe_length: resq 1
mock_shallow: resq 1
mock_unshallow: resq 1

section .rodata
hex: db '0123456789abcdef'

section .text
advertise_probe:
 call git_protocol_v2_advertise
 jmp capture
ls_refs_probe:
 call git_protocol_v2_ls_refs
 jmp capture
object_info_probe:
 call git_protocol_v2_object_info
 jmp capture
acknowledge_probe:
 call git_protocol_v2_acknowledge
 jmp capture
fetch_probe:
 call git_protocol_v2_fetch
capture:
 mov [probe_status],rax
 mov [probe_length],rdx
 ret

git_history_shallow:
 mov rax,[mock_shallow]
 ret
git_history_unshallow:
 mov rax,[mock_unshallow]
 ret

bridge_pkt_encode:
 test rdi,rdi
 jz .usage
 test rdx,rdx
 jz .usage
 cmp rsi,65515
 ja .usage
 lea r8,[rsi+4]
 cmp rcx,r8
 jb .space
 mov r9,rdi
 mov r10,rdx
 mov rax,r8
 lea r11,[hex]
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
.space:
 mov eax,3
 ret
.usage:
 mov eax,8
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
