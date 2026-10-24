; Utkarsha calculator: reentrant System V AMD64, no OS calls or allocation.
; calc_eval(rdi=NUL expression) -> rax=64-bit value, edx=status.
; Status: 0 OK, 1 syntax, 2 literal overflow, 3 division, 4 shift, 5 depth.
; Arithmetic wraps modulo 2^64. Division/remainder signed, shifts logical.
; Readable NUL-terminated input required. NULL is rejected.
bits 64
default rel
section .rodata
; token (little endian), length, precedence, operation
ops:
 dw '|'
 db 1,1,0
 dw '^'
 db 1,2,1
 dw '&'
 db 1,3,2
 dw '<<'
 db 2,4,3
 dw '>>'
 db 2,4,4
 dw '+'
 db 1,5,5
 dw '-'
 db 1,5,6
 dw '*'
 db 1,6,7
 dw '/'
 db 1,6,8
 dw '%'
 db 1,6,9
ops_end:
section .text
global calc_eval
calc_eval:
 xor r11d,r11d
 jmp calc_eval_start
; Optional exact integer ans/mem: rsi points to two qwords, read-only.
global calc_eval_context
calc_eval_context:
 mov r11,rsi
calc_eval_start:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdi
 xor r13d,r13d
 xor r14d,r14d
 test rdi,rdi
 jz .invalid
 mov edi,1
 call expr
 call whitespace
 cmp byte [r12],0
 je .done
.invalid:
 test r14d,r14d
 jnz .done
 mov r14d,1
.done:
 mov edx,r14d
 test edx,edx
 jz .restore
 xor eax,eax
.restore:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

whitespace:
 cmp byte [r12],32
 je .advance
 cmp byte [r12],9
 jb .done
 cmp byte [r12],13
 ja .done
.advance:
 inc r12
 jmp whitespace
.done:
 ret

; Precedence climbing: edi=min precedence. Recursion bounded at 64 frames.
expr:
 push rbx
 push r15
 push rbp
 mov ebp,edi
 inc r13d
 cmp r13d,64
 ja .depth
 call atom
 mov rbx,rax
.loop:
 test r14d,r14d
 jnz .done
 call whitespace
 lea rsi,[ops]
.find:
 mov al,[r12]
 cmp al,[rsi]
 jne .next
 cmp byte [rsi+2],2
 jne .found
 mov al,[r12+1]
 cmp al,[rsi+1]
 je .found
.next:
 add rsi,5
 lea rax,[ops_end]
 cmp rsi,rax
 jb .find
 jmp .done
.found:
 movzx edi,byte [rsi+3]
 cmp edi,ebp
 jb .done
 movzx r15d,byte [rsi+4]
 movzx ecx,byte [rsi+2]
 add r12,rcx
 inc edi
 call expr
 test r14d,r14d
 jnz .done
 cmp r15d,0
 je .or
 cmp r15d,1
 je .xor
 cmp r15d,2
 je .and
 cmp r15d,4
 jbe .shift
 cmp r15d,5
 je .add
 cmp r15d,6
 je .sub
 cmp r15d,7
 je .mul
 ; Signed idiv would trap on zero or INT64_MIN / -1.
 test rax,rax
 jz .division
 mov rcx,rax
 mov rax,0x8000000000000000
 cmp rbx,rax
 jne .divide
 cmp rcx,-1
 je .division
.divide:
 mov rax,rbx
 cqo
 idiv rcx
 cmp r15d,9
 cmove rax,rdx
 mov rbx,rax
 jmp .loop
.or: or rbx,rax
 jmp .loop
.xor: xor rbx,rax
 jmp .loop
.and: and rbx,rax
 jmp .loop
.add: add rbx,rax
 jmp .loop
.sub: sub rbx,rax
 jmp .loop
.mul: imul rbx,rax
 jmp .loop
.shift:
 cmp rax,63
 ja .badshift
 mov ecx,eax
 cmp r15d,3
 jne .right
 shl rbx,cl
 jmp .loop
.right:
 shr rbx,cl
 jmp .loop
.division:
 mov r14d,3
 jmp .done
.badshift:
 mov r14d,4
 jmp .done
.depth:
 mov r14d,5
 xor ebx,ebx
.done:
 mov rax,rbx
 dec r13d
 pop rbp
 pop r15
 pop rbx
 ret

atom:
 push rbx
 call whitespace
 mov bl,[r12]
 cmp bl,'('
 je .paren
 cmp bl,'+'
 je .unary
 cmp bl,'-'
 je .unary
 cmp bl,'~'
 je .unary
 cmp bl,'a'
 je .variable
 cmp bl,'m'
 je .variable
 ; Literal: decimal, 0x hex or 0b binary. Reject overflow, including hex.
 mov r8d,10
 cmp byte [r12],'0'
 jne .digits
 mov al,[r12+1]
 or al,32
 cmp al,'x'
 je .hex
 cmp al,'b'
 jne .digits
 mov r8d,2
 jmp .prefix
.hex:
 mov r8d,16
.prefix:
 add r12,2
.digits:
 xor eax,eax
 xor r9d,r9d
.digit:
 movzx ecx,byte [r12]
 sub ecx,'0'
 cmp ecx,9
 jbe .check
 movzx ecx,byte [r12]
 or ecx,32
 sub ecx,'a'
 cmp ecx,5
 ja .end
 add ecx,10
.check:
 cmp ecx,r8d
 jae .end
 mul r8
 test rdx,rdx
 jnz .overflow
 add rax,rcx
 jc .overflow
 inc r12
 inc r9d
 jmp .digit
.end:
 test r9d,r9d
 jz .syntax
 pop rbx
 ret
.variable:
 test r11,r11
 jz .syntax
 cmp bl,'a'
 jne .memory
 cmp byte [r12+1],'n'
 jne .syntax
 cmp byte [r12+2],'s'
 jne .syntax
 mov rax,[r11]
 jmp .variable_done
.memory:
 cmp byte [r12+1],'e'
 jne .syntax
 cmp byte [r12+2],'m'
 jne .syntax
 mov rax,[r11+8]
.variable_done:
 add r12,3
 pop rbx
 ret
.unary:
 inc r12
 mov edi,7
 call expr
 cmp bl,'-'
 je .neg
 cmp bl,'~'
 jne .return
 not rax
 jmp .return
.neg:
 neg rax
 jmp .return
.paren:
 inc r12
 mov edi,1
 call expr
 test r14d,r14d
 jnz .return
 call whitespace
 cmp byte [r12],')'
 jne .syntax
 inc r12
.return:
 pop rbx
 ret
.overflow:
 mov r14d,2
 jmp .zero
.syntax:
 mov r14d,1
.zero:
 xor eax,eax
 pop rbx
 ret

; calc_format(rdi=value, esi=base 2/10/16, rdx=buffer >=67 bytes)
; -> rax=buffer, edx=length excluding NUL; invalid base -> rax=0, edx=0.
; Decimal is signed; hex/binary display unsigned bit patterns, no prefix.
global calc_format
calc_format:
 cmp esi,2
 je .valid
 cmp esi,10
 je .valid
 cmp esi,16
 jne .invalid
.valid:
 mov r8,rdx
 mov r9,rdx
 mov rax,rdi
 xor r10d,r10d
 cmp esi,10
 jne .digits
 test rax,rax
 jns .digits
 mov byte [r9],'-'
 inc r9
 neg rax
.digits:
 mov r11,r9
 mov ecx,esi
.loop:
 xor edx,edx
 div rcx
 add dl,'0'
 cmp dl,'9'
 jbe .store
 add dl,39
.store:
 mov [r9],dl
 inc r9
 test rax,rax
 jnz .loop
 mov byte [r9],0
 mov rdx,r9
 sub rdx,r8
 dec r9
.reverse:
 cmp r11,r9
 jae .done
 mov al,[r11]
 mov cl,[r9]
 mov [r11],cl
 mov [r9],al
 inc r11
 dec r9
 jmp .reverse
.done:
 mov rax,r8
 ret
.invalid:
 xor eax,eax
 xor edx,edx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
