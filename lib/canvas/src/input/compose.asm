; Dead-key and Multi_key composition.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

extern arena_alloc

%define CS_ACTIVE 0
%define CS_LEN    1
%define CS_SEQ    8
%define CS_SIZE   24
%define XK_MULTI  0xFE03

section .text
; rdi=server (unused), rsi=arena -> rax=state
global compose_init
compose_init:
    mov rdi, rsi
    mov rsi, CS_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov byte [rax + CS_ACTIVE], 0
    mov byte [rax + CS_LEN], 0
    ret
.oom:
    mov rax, -(ENOMEM)
    ret

; rdi=state, rsi=keysym; zero means sequence remains pending.
global compose_process_key
compose_process_key:
    mov rdx, rsi
    cmp edx, XK_MULTI
    je .start_empty
    cmp edx, 0xFE50
    jb .ordinary
    cmp edx, 0xFE5D
    jbe .start_dead
.ordinary:
    cmp byte [rdi + CS_ACTIVE], 0
    je .passthrough
    movzx ecx, byte [rdi + CS_LEN]
    cmp ecx, 3
    jae .cancel
    mov [rdi + CS_SEQ + rcx * 4], edx
    inc ecx
    mov [rdi + CS_LEN], cl
    lea r8, [rel compose_table]
.scan:
    mov eax, [r8]
    test eax, eax
    jz .cancel_return_key
    cmp eax, [rdi + CS_SEQ]
    jne .next
    cmp ecx, 1
    je .prefix
    mov eax, [r8 + 4]
    cmp eax, [rdi + CS_SEQ + 4]
    jne .next
    mov eax, [r8 + 8]
    test eax, eax
    jz .match
    cmp ecx, 2
    je .prefix
    cmp eax, [rdi + CS_SEQ + 8]
    jne .next
.match:
    mov eax, [r8 + 12]
    mov byte [rdi + CS_ACTIVE], 0
    mov byte [rdi + CS_LEN], 0
    ret
.prefix:
    xor eax, eax
    ret
.next:
    add r8, 16
    jmp .scan
.start_empty:
    mov byte [rdi + CS_ACTIVE], 1
    mov byte [rdi + CS_LEN], 1
    mov dword [rdi + CS_SEQ], XK_MULTI
    xor eax, eax
    ret
.start_dead:
    mov byte [rdi + CS_ACTIVE], 1
    mov byte [rdi + CS_LEN], 1
    mov [rdi + CS_SEQ], edx
    xor eax, eax
    ret
.cancel_return_key:
    mov byte [rdi + CS_ACTIVE], 0
    mov byte [rdi + CS_LEN], 0
.passthrough:
    mov eax, edx
    ret
.cancel:
    mov byte [rdi + CS_ACTIVE], 0
    mov byte [rdi + CS_LEN], 0
    xor eax, eax
    ret

global compose_reset
compose_reset:
    mov byte [rdi + CS_ACTIVE], 0
    mov byte [rdi + CS_LEN], 0
    xor eax, eax
    ret

section .rodata
; key1, key2, optional key3, Unicode scalar
compose_table:
    dd 0xFE50,'a',0,0x00E0, 0xFE50,'e',0,0x00E8, 0xFE50,'i',0,0x00EC, 0xFE50,'o',0,0x00F2, 0xFE50,'u',0,0x00F9
    dd 0xFE51,'a',0,0x00E1, 0xFE51,'e',0,0x00E9, 0xFE51,'i',0,0x00ED, 0xFE51,'o',0,0x00F3, 0xFE51,'u',0,0x00FA
    dd 0xFE52,'a',0,0x00E2, 0xFE52,'e',0,0x00EA, 0xFE52,'i',0,0x00EE, 0xFE52,'o',0,0x00F4, 0xFE52,'u',0,0x00FB
    dd 0xFE53,'a',0,0x00E3, 0xFE53,'n',0,0x00F1, 0xFE53,'o',0,0x00F5
    dd 0xFE54,'a',0,0x00E4, 0xFE54,'e',0,0x00EB, 0xFE54,'i',0,0x00EF, 0xFE54,'o',0,0x00F6, 0xFE54,'u',0,0x00FC
    dd 0xFE55,'c',0,0x00E7
    dd XK_MULTI,'o','c',0x00A9, XK_MULTI,'o','r',0x00AE, XK_MULTI,'T','M',0x2122
    dd XK_MULTI,'1','2',0x00BD, XK_MULTI,'1','4',0x00BC, XK_MULTI,'3','4',0x00BE
    dd XK_MULTI,'-','-',0x2014, XK_MULTI,'.','.',0x2026
    dd 0,0,0,0

section .data
global compose_version
compose_version: dq 0x010000
