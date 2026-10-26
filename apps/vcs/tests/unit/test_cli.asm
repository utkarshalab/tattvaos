; Linux syscalls exist only in this host test harness, never in the app.
%include "src/cli/cli.asm"
section .rodata
program: db 'vcs',0
help: db '--help',0
version: db 'version',0
commit: db 'commit',0
unknown: db 'comm',0
extra: db 'extra',0
args_help: dq program,help
args_version: dq program,version
args_commit: dq program,commit
args_unknown: dq program,unknown
args_extra: dq program,help,extra
args_null: dq program,0
; argc, argv, expected status, first response byte
cases:
 dq 1,args_help,VCS_OK,'U'
 dq 2,args_help,VCS_OK,'U'
 dq 2,args_version,VCS_OK,'U'
 dq 2,args_commit,VCS_ERR_UNSUPPORTED,'R'
 dq 2,args_unknown,VCS_ERR_USAGE,'I'
 dq 3,args_extra,VCS_ERR_USAGE,'I'
 dq 2,args_null,VCS_ERR_USAGE,'I'
 dq 0,0,VCS_ERR_USAGE,'I'
 dq -1,0,VCS_ERR_USAGE,'I'
 dq 2,0,VCS_ERR_USAGE,'I'
cases_end:
section .text
global _start
_start:
 lea r12,[cases]
 mov rbx,12345
 mov rbp,23456
 mov r13,34567
 mov r14,45678
 mov r15,56789
.loop:
 mov rdi,[r12]
 mov rsi,[r12+8]
 call cli_main
 cmp rax,[r12+16]
 jne .fail
 test rdx,rdx
 jz .fail
 mov al,[rdx]
 cmp al,[r12+24]
 jne .fail
 cmp rbx,12345
 jne .fail
 cmp rbp,23456
 jne .fail
 cmp r13,34567
 jne .fail
 cmp r14,45678
 jne .fail
 cmp r15,56789
 jne .fail
 add r12,32
 lea rax,[cases_end]
 cmp r12,rax
 jb .loop
 call cli_cmd_clone
 cmp eax,VCS_ERR_UNSUPPORTED
 jne .fail
 call cli_cmd_commit
 cmp eax,VCS_ERR_UNSUPPORTED
 jne .fail
 xor edi,edi
 jmp .exit
.fail:
 mov edi,1
.exit:
 mov eax,60
 syscall
section .note.GNU-stack noalloc noexec nowrite progbits
