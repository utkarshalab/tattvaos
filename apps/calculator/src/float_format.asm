; calc_float_format(xmm0=value, rdi=buffer>=64, esi=precision 1..15)
; -> rax=buffer, edx=length; invalid arguments/nonfinite -> both zero.
; General decimal format, rounded to requested significant digits with x87.
bits 64
default rel
section .rodata
ff_ten: dq 10.0
ff_powers: dq 1.0,1e1,1e2,1e3,1e4,1e5,1e6,1e7,1e8,1e9,1e10,1e11,1e12,1e13,1e14
ff_nearest: dw 0x037f
section .text
global calc_float_format
calc_float_format:
 test rdi,rdi
 jz .invalid
 cmp esi,1
 jb .invalid
 cmp esi,15
 ja .invalid
 movq rax,xmm0
 mov rcx,rax
 shr rcx,52
 and ecx,0x7ff
 cmp ecx,0x7ff
 je .invalid
 sub rsp,88
 mov r10,rdi
 mov r11,rdi
 mov r9d,esi
 btr rax,63
 mov [rsp],rax
 test rax,rax
 jz .zero
 movq rcx,xmm0
 test rcx,rcx
 jns .positive
 mov byte [r11],'-'
 inc r11
.positive:
 fnstcw [rsp+32]
 fldcw [ff_nearest]
 fld qword [rsp]
 xor r8d,r8d
.high:
 fld qword [ff_ten]
 fcomip st0,st1
 ja .low
 fdiv qword [ff_ten]
 inc r8d
 jmp .high
.low:
 fld1
 fcomip st0,st1
 jbe .normalized
 fmul qword [ff_ten]
 dec r8d
 jmp .low
.normalized:
 lea rdx,[ff_powers]
 lea ecx,[r9-1]
 fmul qword [rdx+rcx*8]
 fistp qword [rsp+8]
 fldcw [rsp+32]
 ; Handle a rounding carry into a new decade.
 mov rax,1
 mov ecx,r9d
.power:
 imul rax,rax,10
 loop .power
 mov rcx,rax
 mov rax,[rsp+8]
 cmp rax,rcx
 jb .digits
 xor edx,edx
 mov ecx,10
 div rcx
 inc r8d
.digits:
 mov ecx,r9d
 mov esi,10
.generate:
 xor edx,edx
 div rsi
 add dl,'0'
 dec ecx
 mov [rsp+48+rcx],dl
 test ecx,ecx
 jnz .generate
.trim:
 cmp r9d,1
 jbe .choose
 cmp byte [rsp+47+r9], '0'
 jne .choose
 dec r9d
 jmp .trim
.choose:
 cmp r8d,-4
 jl .scientific
 ; Fixed notation through 14 decimal places keeps integer results convenient.
 cmp r8d,15
 jge .scientific
 test r8d,r8d
 js .fraction
 lea esi,[r8+1] ; decimal point position
 xor ecx,ecx
.fixed:
 cmp ecx,esi
 jne .fixed_digit
 cmp ecx,r9d
 jae .finish
 mov byte [r11],'.'
 inc r11
.fixed_digit:
 mov al,'0'
 cmp ecx,r9d
 jae .pad
 mov al,[rsp+48+rcx]
.pad:
 mov [r11],al
 inc r11
 inc ecx
 cmp ecx,r9d
 jb .fixed
 cmp ecx,esi
 jb .fixed
 jmp .finish
.fraction:
 mov word [r11],'0.'
 add r11,2
 mov ecx,r8d
 neg ecx
 dec ecx
.zeros:
 test ecx,ecx
 jz .copy_digits
 mov byte [r11],'0'
 inc r11
 dec ecx
 jmp .zeros
.copy_digits:
 xor ecx,ecx
.copy:
 mov al,[rsp+48+rcx]
 mov [r11],al
 inc r11
 inc ecx
 cmp ecx,r9d
 jb .copy
 jmp .finish
.scientific:
 mov al,[rsp+48]
 mov [r11],al
 inc r11
 cmp r9d,1
 je .exponent
 mov byte [r11],'.'
 inc r11
 mov ecx,1
.sci_copy:
 mov al,[rsp+48+rcx]
 mov [r11],al
 inc r11
 inc ecx
 cmp ecx,r9d
 jb .sci_copy
.exponent:
 mov byte [r11],'e'
 inc r11
 mov al,'+'
 test r8d,r8d
 jns .sign
 mov al,'-'
 neg r8d
.sign:
 mov [r11],al
 inc r11
 mov eax,r8d
 mov esi,10
 xor ecx,ecx
.exp_digits:
 xor edx,edx
 div esi
 add dl,'0'
 mov [rsp+rcx],dl
 inc ecx
 test eax,eax
 jnz .exp_digits
.exp_copy:
 dec ecx
 mov al,[rsp+rcx]
 mov [r11],al
 inc r11
 test ecx,ecx
 jnz .exp_copy
 jmp .finish
.zero:
 mov byte [r11],'0'
 inc r11
.finish:
 mov byte [r11],0
 mov rax,r10
 mov rdx,r11
 sub rdx,r10
 add rsp,88
 ret
.invalid:
 xor eax,eax
 xor edx,edx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
