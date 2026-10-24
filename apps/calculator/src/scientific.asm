; Scientific evaluator. System V AMD64, no I/O, heap or OS calls.
; calc_scientific(rdi=NUL input, rsi=context) -> xmm0=value, edx=status.
; Context: session.inc layout; at least 128 bytes, zero-initialize first.
; Only ans is changed, and only on success. Input readable through NUL.
; Status: 1 syntax, 2 range/nonfinite, 3 division, 5 nesting, 7 domain.
bits 64
default rel
extern umath_sqrt_f64,umath_cbrt_f64,umath_sin_f64,umath_cos_f64,umath_tan_f64
extern umath_asin_f64,umath_acos_f64,umath_atan_f64,umath_log_f64,umath_log10_f64
extern umath_log2_f64,umath_exp_f64,umath_pow_f64,umath_hypot_f64,umath_atan2_f64
extern umath_floor_f64,umath_ceil_f64,umath_round_f64,umath_trunc_f64
section .rodata
sci_one: dq 1.0
sci_ten: dq 10.0
sci_pi: dq 3.141592653589793
sci_e: dq 2.718281828459045
sci_tau: dq 6.283185307179586
sci_deg: dq 0.017453292519943295
sci_rad: dq 57.29577951308232
sci_170: dq 170.0
sci_trig_limit: dq 6.5e9
align 16
sci_sign: dq 0x8000000000000000,0
sci_abs: dq 0x7fffffffffffffff,0xffffffffffffffff
%macro SF 4
 %%name: db %1,0
 times 16-($-%%name) db 0
 dq %2
 dd %3,%4
%endmacro
section .data.rel.ro
sci_functions:
 SF 'sqrt',umath_sqrt_f64,1,0
 SF 'cbrt',umath_cbrt_f64,1,0
 SF 'sin',umath_sin_f64,1,1
 SF 'cos',umath_cos_f64,1,1
 SF 'tan',umath_tan_f64,1,1
 SF 'asin',umath_asin_f64,1,2
 SF 'acos',umath_acos_f64,1,2
 SF 'atan',umath_atan_f64,1,2
 SF 'ln',umath_log_f64,1,0
 SF 'log',umath_log10_f64,1,0
 SF 'log10',umath_log10_f64,1,0
 SF 'log2',umath_log2_f64,1,0
 SF 'exp',umath_exp_f64,1,0
 SF 'abs',sci_absolute,1,0
 SF 'floor',umath_floor_f64,1,0
 SF 'ceil',umath_ceil_f64,1,0
 SF 'round',umath_round_f64,1,0
 SF 'trunc',umath_trunc_f64,1,0
 SF 'fact',sci_factorial,1,0
 SF 'pow',sci_power,2,0
 SF 'hypot',umath_hypot_f64,2,0
 SF 'atan2',umath_atan2_f64,2,2
 SF 'min',sci_minimum,2,0
 SF 'max',sci_maximum,2,0
sci_functions_end:
sci_constants:
 SF 'pi',sci_pi,0,0
 SF 'e',sci_e,0,0
 SF 'tau',sci_tau,0,0
 SF 'ans',0,0,0
 SF 'mem',8,0,0
 SF 'x',80,0,0
 SF 'y',88,0,0
 SF 'z',96,0,0
 SF 'a',104,0,0
 SF 'b',112,0,0
 SF 'c',120,0,0
sci_constants_end:
section .text
global calc_scientific
calc_scientific:
 push rbx
 push rbp
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov r12,rdi
 mov r15,rsi
 xor r13d,r13d
 xor r14d,r14d
 test rdi,rdi
 jz .invalid
 test rsi,rsi
 jz .invalid
 ; Limit accepted input to 4096 bytes before recursive parsing.
 xor ecx,ecx
.scan:
 cmp byte [r12+rcx],0
 je .parse
 inc ecx
 cmp ecx,4096
 jb .scan
 jmp .invalid
.parse:
 mov edi,1
 call sci_expr
 call sci_space
 cmp byte [r12],0
 jne .invalid
 test r14d,r14d
 jnz .finish
 call sci_finite
 test r14d,r14d
 jnz .finish
 movsd [r15],xmm0
 jmp .finish
.invalid:
 test r14d,r14d
 jnz .finish
 mov r14d,1
.finish:
 mov edx,r14d
 test edx,edx
 jz .return
 xorpd xmm0,xmm0
.return:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbp
 pop rbx
 ret
sci_space:
 cmp byte [r12],32
 je .advance
 cmp byte [r12],9
 jb .done
 cmp byte [r12],13
 ja .done
.advance:
 inc r12
 jmp sci_space
.done: ret
sci_finite:
 movq rax,xmm0
 shr rax,52
 and eax,0x7ff
 cmp eax,0x7ff
 jne .done
 mov r14d,2
.done: ret

sci_expr:
 push rbx
 push rbp
 sub rsp,24
 mov ebp,edi
 inc r13d
 cmp r13d,64
 ja .depth
 call sci_atom
 movsd [rsp],xmm0
.loop:
 test r14d,r14d
 jnz .done
 call sci_space
 movzx ebx,byte [r12]
 mov edi,1
 cmp bl,'+'
 je .operator
 cmp bl,'-'
 je .operator
 mov edi,2
 cmp bl,'/'
 je .operator
 cmp bl,'%'
 je .operator
 cmp bl,'*'
 jne .done
 cmp byte [r12+1],'*'
 jne .operator
 mov ebx,'p'
 mov edi,4
.operator:
 cmp edi,ebp
 jb .done
 inc r12
 cmp bl,'p'
 jne .left
 inc r12
 jmp .rhs
.left:
 inc edi
.rhs:
 call sci_expr
 test r14d,r14d
 jnz .done
 movapd xmm1,xmm0
 movsd xmm0,[rsp]
 cmp bl,'+'
 je .add
 cmp bl,'-'
 je .sub
 cmp bl,'*'
 je .mul
 cmp bl,'p'
 je .power
 xorpd xmm2,xmm2
 ucomisd xmm1,xmm2
 je .zero
 cmp bl,'%'
 je .remainder
 divsd xmm0,xmm1
 jmp .store
.remainder:
 ; x87 fprem is bounded by binary64 exponent range; loop until C2 clears.
 movsd [rsp+8],xmm1
 fld qword [rsp+8]
 fld qword [rsp]
.rem_loop:
 fprem
 fnstsw ax
 test ah,4
 jnz .rem_loop
 fstp qword [rsp+8]
 fstp st0
 movsd xmm0,[rsp+8]
 jmp .store
.power:
 call sci_power
 ucomisd xmm0,xmm0
 jnp .store
 mov r14d,7
 jmp .store
.add: addsd xmm0,xmm1
 jmp .store
.sub: subsd xmm0,xmm1
 jmp .store
.mul: mulsd xmm0,xmm1
.store:
 test r14d,r14d
 jnz .save
 call sci_finite
.save:
 movsd [rsp],xmm0
 jmp .loop
.zero:
 mov r14d,3
 jmp .done
.depth:
 mov r14d,5
 xorpd xmm0,xmm0
 movsd [rsp],xmm0
.done:
 movsd xmm0,[rsp]
 dec r13d
 add rsp,24
 pop rbp
 pop rbx
 ret

sci_atom:
 push rbx
 push rbp
 sub rsp,24
 call sci_space
 movzx ebx,byte [r12]
 cmp bl,'+'
 je .unary
 cmp bl,'-'
 je .unary
 cmp bl,'('
 je .paren
 cmp bl,'a'
 jb .number
 cmp bl,'z'
 ja .number
 ; Find a complete name; prefixes never match (e.g. sine != sin).
 mov rbp,r12
.name_scan:
 mov al,[r12]
 cmp al,'a'
 jb .digit_name
 cmp al,'z'
 jbe .advance
.digit_name:
 cmp al,'0'
 jb .name_end
 cmp al,'9'
 ja .name_end
.advance:
 inc r12
 jmp .name_scan
.name_end:
 mov rbx,r12
 sub rbx,rbp
 cmp rbx,15
 ja .syntax
 lea r8,[sci_functions]
.find:
 xor ecx,ecx
.match:
 cmp rcx,rbx
 je .matched
 mov al,[rbp+rcx]
 cmp al,[r8+rcx]
 jne .next
 inc rcx
 jmp .match
.matched:
 cmp byte [r8+rbx],0
 je .found
.next:
 add r8,32
 lea rax,[sci_constants_end]
 cmp r8,rax
 jb .find
 jmp .syntax
.found:
 lea rax,[sci_functions_end]
 cmp r8,rax
 jae .constant
 mov rbp,r8
 call sci_space
 cmp byte [r12],'('
 jne .syntax
 inc r12
 mov edi,1
 call sci_expr
 test r14d,r14d
 jnz .return
 call sci_space
 cmp dword [rbp+24],2
 jne .close_function
 movsd [rsp],xmm0
 cmp byte [r12],','
 jne .syntax
 inc r12
 mov edi,1
 call sci_expr
 movapd xmm1,xmm0
 movsd xmm0,[rsp]
 test r14d,r14d
 jnz .return
 call sci_space
.close_function:
 cmp byte [r12],')'
 jne .syntax
 inc r12
 ; Convert direct trig input in degree mode. Inverse outputs converted below.
 cmp dword [rbp+28],1
 jne .call
 cmp qword [r15+16],0
 je .call
 mulsd xmm0,[sci_deg]
.call:
 ; Limit trig input to the library's documented accurate range.
 cmp dword [rbp+28],1
 jne .invoke
 movapd xmm2,xmm0
 andpd xmm2,[sci_abs]
 ucomisd xmm2,[sci_trig_limit]
 ja .range
.invoke:
 call qword [rbp+16]
 cmp dword [rbp+28],2
 jne .function_done
 cmp qword [r15+16],0
 je .function_done
 mulsd xmm0,[sci_rad]
.function_done:
 ; NaN from a function is a domain error; infinity is a range error.
 ucomisd xmm0,xmm0
 jp .domain
 call sci_finite
 jmp .post
.constant:
 mov rax,[r8+16]
 cmp rax,120
 jbe .context_constant
 movsd xmm0,[rax]
 jmp .post
.context_constant:
 movsd xmm0,[r15+rax]
 jmp .post
.unary:
 inc r12
 mov edi,3
 call sci_expr
 cmp bl,'-'
 jne .return
 xorpd xmm0,[sci_sign]
 jmp .return
.paren:
 inc r12
 mov edi,1
 call sci_expr
 test r14d,r14d
 jnz .return
 call sci_space
 cmp byte [r12],')'
 jne .syntax
 inc r12
 jmp .post
.number:
 call sci_number
.post:
 test r14d,r14d
 jnz .return
 call sci_space
 cmp byte [r12],'!'
 jne .return
 inc r12
 call sci_factorial
 test r14d,r14d
 jnz .return
 jmp .post
.syntax:
 mov r14d,1
 jmp .error
.range:
 mov r14d,2
 jmp .error
.domain:
 mov r14d,7
.error:
 xorpd xmm0,xmm0
.return:
 add rsp,24
 pop rbp
 pop rbx
 ret

; Up to 18 significant decimal digits, scaled in x87 extended precision.
; Deliberately not a correctly-rounded arbitrary-length decimal conversion.
sci_number:
 sub rsp,24
 xor eax,eax
 xor r8d,r8d ; decimal exponent
 xor r9d,r9d ; significant digits retained
 xor r10d,r10d ; fractional flag
 xor r11d,r11d ; total digits
.digit:
 movzx ecx,byte [r12]
 sub ecx,'0'
 cmp ecx,9
 ja .point
 inc r11d
 sub r8d,r10d
 inc r12
 test rax,rax
 jnz .retain
 test ecx,ecx
 jz .digit
.retain:
 cmp r9d,18
 jae .skip
 imul rax,rax,10
 add rax,rcx
 inc r9d
 jmp .digit
.skip:
 inc r8d
 jmp .digit
.point:
 cmp byte [r12],'.'
 jne .exponent
 test r10d,r10d
 jnz .exponent
 mov r10d,1
 inc r12
 jmp .digit
.exponent:
 test r11d,r11d
 jz .syntax
 mov [rsp],rax
 mov cl,[r12]
 or cl,32
 cmp cl,'e'
 jne .scale
 inc r12
 mov r10d,1
 cmp byte [r12],'-'
 jne .positive
 mov r10d,-1
 inc r12
 jmp .exp_digits
.positive:
 cmp byte [r12],'+'
 jne .exp_digits
 inc r12
.exp_digits:
 xor r9d,r9d
 xor r11d,r11d
.exp_loop:
 movzx ecx,byte [r12]
 sub ecx,'0'
 cmp ecx,9
 ja .exp_end
 inc r12
 inc r11d
 cmp r9d,10000
 ja .exp_loop
 imul r9d,r9d,10
 add r9d,ecx
 jmp .exp_loop
.exp_end:
 test r11d,r11d
 jz .syntax
 imul r9d,r10d
 add r8d,r9d
.scale:
 cmp r8d,4000
 jg .range
 cmp r8d,-4000
 jl .range
 fild qword [rsp]
 test r8d,r8d
 jz .convert
 js .down
.up:
 fmul qword [sci_ten]
 dec r8d
 jnz .up
 jmp .convert
.down:
 fdiv qword [sci_ten]
 inc r8d
 jnz .down
.convert:
 fstp qword [rsp+8]
 movsd xmm0,[rsp+8]
 call sci_finite
 ; Reject nonzero decimal literals that underflow to zero.
 xorpd xmm1,xmm1
 ucomisd xmm0,xmm1
 jne .done
 cmp qword [rsp],0
 je .done
.range:
 mov r14d,2
 jmp .zero
.syntax:
 mov r14d,1
.zero:
 xorpd xmm0,xmm0
.done:
 add rsp,24
 ret
sci_absolute:
 andpd xmm0,[sci_abs]
 ret
sci_minimum:
 minsd xmm0,xmm1
 ret
sci_maximum:
 maxsd xmm0,xmm1
 ret
sci_power:
 ; Integral exponents use squaring, avoiding exp/log error for 2**3 etc.
 cvttsd2si rax,xmm1
 cvtsi2sd xmm2,rax
 ucomisd xmm1,xmm2
 jne .general
 mov rcx,0x8000000000000000
 cmp rax,rcx
 je .general
 movapd xmm2,xmm0
 movsd xmm0,[sci_one]
 test rax,rax
 jns .loop
 divsd xmm0,xmm2
 movapd xmm2,xmm0
 movsd xmm0,[sci_one]
 neg rax
.loop:
 test rax,rax
 jz .done
 test al,1
 jz .square
 mulsd xmm0,xmm2
.square:
 shr rax,1
 jz .done
 mulsd xmm2,xmm2
 jmp .loop
.done: ret
.general:
 jmp umath_pow_f64
sci_factorial:
 xorpd xmm1,xmm1
 ucomisd xmm0,xmm1
 jb .domain
 ucomisd xmm0,[sci_170]
 ja .domain
 cvttsd2si rcx,xmm0
 cvtsi2sd xmm1,rcx
 ucomisd xmm0,xmm1
 jne .domain
 movsd xmm0,[sci_one]
.loop:
 cmp rcx,1
 jbe .done
 cvtsi2sd xmm1,rcx
 mulsd xmm0,xmm1
 dec rcx
 jmp .loop
.domain:
 mov r14d,7
 xorpd xmm0,xmm0
.done: ret
section .note.GNU-stack noalloc noexec nowrite progbits
