; Portable calculator session. Caller owns state and buffers (see session.inc).
; calc_session_init(rdi=context): initialize all state.
; calc_session(rdi=context,rsi=NUL line,rdx=output>=8192) -> eax=status.
; Inputs limited to 255 bytes. Output always NUL terminated, newline when nonempty.
; No I/O or allocation. Different contexts are independent; same context serialized.
%include "src/session.inc"
bits 64
default rel
extern calc_scientific,calc_float_format,calc_eval_context,calc_format
section .rodata
session_help: db 'Utkarsha Calculator',10
 db 'Scientific: decimals, 1e-3, pi, e, tau, ans, mem, + - * / % ** and !',10
 db 'Functions: sqrt cbrt sin cos tan asin acos atan ln log log10 log2 exp',10
 db '           abs floor ceil round trunc fact pow hypot atan2 min max',10
 db 'Two-argument functions use commas. Trig uses rad/deg; atan2(y,x).',10
 db 'Scientific variables: x y z a b c; assign with x = expression.',10
 db 'Programmer: 64-bit decimal/0x/0b, ans, mem, + - * / % << >> & ^ | ~',10
 db 'Commands: sci prog rad deg dec hex bin precision N (1..15)',10
 db 'Memory: ms mr mc m+ m-    Session: history clear reset help quit exit',10
 db 'Quote expressions in one-shot use. Unary - binds below ** in sci mode.',10,0
session_sci: db 'Scientific mode',10,0
session_prog: db 'Programmer mode (64-bit wrapping integers)',10,0
session_rad: db 'Radians',10,0
session_deg: db 'Degrees',10,0
session_base: db 'Programmer output base updated',10,0
session_precision: db 'Precision updated',10,0
session_memory: db 'Memory updated',10,0
session_empty: db 'History is empty',10,0
session_clear: db 'History cleared',10,0
session_reset: db 'Session reset',10,0
session_quit: db 'Bye.',10,0
session_syntax: db 'calc: invalid expression or command (help lists supported syntax)',10,0
session_range: db 'calc: result/literal outside supported finite range',10,0
session_division: db 'calc: zero divisor or signed integer division overflow',10,0
session_shift: db 'calc: shift count must be 0..63',10,0
session_depth: db 'calc: expression nesting exceeds 64',10,0
session_io: db 'calc: invalid argument',10,0
session_domain: db 'calc: function argument outside its domain',10,0
session_long: db 'calc: input exceeds 255 bytes',10,0
session_commands:
 db 'sci',0,'prog',0,'rad',0,'deg',0,'dec',0,'hex',0,'bin',0
 db 'ms',0,'mr',0,'mc',0,'m+',0,'m-',0,'history',0,'clear',0,'help',0,'quit',0,'exit',0,'reset',0,0
precision_command: db 'precision ',0
session_variables: db 'xyzabc'
section .data.rel.ro
session_errors: dq 0,session_syntax,session_range,session_division,session_shift,session_depth,session_io,session_domain
section .text
global calc_session_init,calc_session
calc_session_init:
 mov r8,rdi
 mov ecx,CALC_CONTEXT_SIZE/8
 xor eax,eax
 rep stosq
 mov qword [r8+CALC_BASE],10
 mov qword [r8+CALC_PRECISION],12
 ret
calc_session:
 push rbx
 push rbp
 push r12
 push r13
 push r14
 push r15
 sub rsp,280
 mov r12,rdi
 mov r13,rdx
 xor r14d,r14d
 mov qword [rsp+256],0 ; optional scientific assignment target offset
 ; Caller must supply valid context/output. Reject NULL without writing.
 test rdi,rdi
 jz .null
 test rdx,rdx
 jz .null
 mov byte [r13],0
 test rsi,rsi
 jz .syntax
 xor ecx,ecx
.copy_line:
 mov al,[rsi+rcx]
 mov [rsp+rcx],al
 test al,al
 jz .trim
 inc ecx
 cmp ecx,CALC_LINE_SIZE
 jb .copy_line
 mov r14d,1
 lea rsi,[session_long]
 jmp .message
.trim:
 mov rbp,rsp
.trim_start:
 cmp byte [rbp],32
 je .advance
 cmp byte [rbp],9
 jb .trim_end
 cmp byte [rbp],13
 ja .trim_end
.advance:
 inc rbp
 jmp .trim_start
.trim_end:
 lea rbx,[rsp+rcx]
.trim_loop:
 cmp rbx,rbp
 jbe .blank
 mov al,[rbx-1]
 cmp al,32
 je .trim_one
 cmp al,9
 jb .commands
 cmp al,13
 ja .commands
.trim_one:
 dec rbx
 mov byte [rbx],0
 jmp .trim_loop
.blank:
 jmp .done
.commands:
 lea r8,[session_commands]
 xor r15d,r15d
.command:
 mov rsi,rbp
 mov rdi,r8
.compare:
 mov al,[rsi]
 cmp al,[rdi]
 jne .next
 inc rsi
 inc rdi
 test al,al
 jnz .compare
 jmp .dispatch
.next:
 cmp byte [r8],0
 lea r8,[r8+1]
 jne .next
 inc r15d
 cmp byte [r8],0
 jne .command
 ; precision N is the only command with a numeric argument.
 lea rdi,[precision_command]
 mov rsi,rbp
.precision_prefix:
 mov al,[rdi]
 test al,al
 jz .precision_number
 cmp al,[rsi]
 jne .expression
 inc rdi
 inc rsi
 jmp .precision_prefix
.precision_number:
 xor eax,eax
 xor ecx,ecx
.precision_digit:
 movzx edx,byte [rsi]
 test edx,edx
 jz .precision_set
 sub edx,'0'
 cmp edx,9
 ja .syntax
 imul eax,eax,10
 add eax,edx
 cmp eax,15
 ja .syntax
 inc ecx
 inc rsi
 jmp .precision_digit
.precision_set:
 test ecx,ecx
 jz .syntax
 test eax,eax
 jz .syntax
 mov [r12+CALC_PRECISION],rax
 lea rsi,[session_precision]
 jmp .message
.dispatch:
 cmp r15d,0
 je .science
 cmp r15d,1
 je .programmer
 cmp r15d,2
 je .radian
 cmp r15d,3
 je .degree
 cmp r15d,6
 jbe .base
 cmp r15d,11
 jbe .memory
 cmp r15d,12
 je .history
 cmp r15d,13
 je .clear
 cmp r15d,14
 je .help
 cmp r15d,17
 je .reset
 mov r14d,255
 lea rsi,[session_quit]
 jmp .message
.science:
 mov qword [r12+CALC_MODE],0
 lea rsi,[session_sci]
 jmp .message
.programmer:
 mov qword [r12+CALC_MODE],1
 lea rsi,[session_prog]
 jmp .message
.radian:
 mov qword [r12+CALC_DEGREES],0
 lea rsi,[session_rad]
 jmp .message
.degree:
 mov qword [r12+CALC_DEGREES],1
 lea rsi,[session_deg]
 jmp .message
.base:
 mov eax,10
 cmp r15d,4
 je .set_base
 mov eax,16
 cmp r15d,5
 je .set_base
 mov eax,2
.set_base:
 mov [r12+CALC_BASE],rax
 mov qword [r12+CALC_MODE],1
 lea rsi,[session_base]
 jmp .message
.memory:
 cmp qword [r12+CALC_MODE],0
 jne .integer_memory
 movsd xmm0,[r12+CALC_MEMORY]
 cmp r15d,8
 je .recall
 cmp r15d,9
 je .memory_clear
 cmp r15d,7
 je .memory_store
 cmp r15d,10
 je .memory_add
 subsd xmm0,[r12+CALC_ANS]
 jmp .memory_save
.memory_add:
 addsd xmm0,[r12+CALC_ANS]
 jmp .memory_save
.memory_store:
 movsd xmm0,[r12+CALC_ANS]
 jmp .memory_save
.memory_clear:
 xorpd xmm0,xmm0
.memory_save:
 movq rax,xmm0
 shr rax,52
 and eax,0x7ff
 cmp eax,0x7ff
 je .range
 movsd [r12+CALC_MEMORY],xmm0
 lea rsi,[session_memory]
 jmp .message
.recall:
 movsd [r12+CALC_ANS],xmm0
 call .format_science
 jmp .done
.integer_memory:
 mov rax,[r12+CALC_INT_MEMORY]
 cmp r15d,8
 je .integer_recall
 cmp r15d,9
 je .integer_clear
 cmp r15d,7
 je .integer_store
 cmp r15d,10
 je .integer_add
 sub rax,[r12+CALC_INT_ANS]
 jmp .integer_save
.integer_add:
 add rax,[r12+CALC_INT_ANS]
 jmp .integer_save
.integer_store:
 mov rax,[r12+CALC_INT_ANS]
 jmp .integer_save
.integer_clear:
 xor eax,eax
.integer_save:
 mov [r12+CALC_INT_MEMORY],rax
 lea rsi,[session_memory]
 jmp .message
.integer_recall:
 mov [r12+CALC_INT_ANS],rax
 call .format_integer
 jmp .done
.help:
 lea rsi,[session_help]
 jmp .message
.clear:
 mov qword [r12+CALC_COUNT],0
 mov qword [r12+CALC_NEXT],0
 lea rsi,[session_clear]
 jmp .message
.reset:
 mov rdi,r12
 call calc_session_init
 lea rsi,[session_reset]
 jmp .message
.history:
 mov rbx,[r12+CALC_COUNT]
 test rbx,rbx
 jz .empty
 xor r15d,r15d
 cmp rbx,16
 jb .history_start
 mov r15,[r12+CALC_NEXT]
.history_start:
 mov rdi,r13
.history_slot:
 imul rax,r15,CALC_SLOT
 lea rsi,[r12+CALC_HISTORY+rax]
.history_copy:
 lodsb
 test al,al
 jz .history_next
 stosb
 jmp .history_copy
.history_next:
 inc r15d
 and r15d,15
 dec rbx
 jnz .history_slot
 mov byte [rdi],0
 jmp .done
.empty:
 lea rsi,[session_empty]
 jmp .message
.expression:
 cmp qword [r12+CALC_MODE],0
 jne .integer_expression
 mov rdi,rbp
 ; A single variable followed by '=' is a session assignment, not an operator.
 mov al,[rdi]
 lea rsi,[session_variables]
 xor ecx,ecx
.variable_name:
 cmp al,[rsi+rcx]
 je .assignment_check
 inc ecx
 cmp ecx,6
 jb .variable_name
 jmp .science_evaluate
.assignment_check:
 inc rdi
.assignment_space:
 mov al,[rdi]
 cmp al,32
 je .assignment_advance
 cmp al,9
 jb .assignment_equal
 cmp al,13
 ja .assignment_equal
.assignment_advance:
 inc rdi
 jmp .assignment_space
.assignment_equal:
 cmp al,'='
 jne .variable_expression
 lea rax,[rcx*8+80]
 mov [rsp+256],rax
 inc rdi
 jmp .science_evaluate
.variable_expression:
 mov rdi,rbp
.science_evaluate:
 mov rsi,r12
 call calc_scientific
 mov r14d,edx
 test edx,edx
 jnz .error
 mov rax,[rsp+256]
 test rax,rax
 jz .science_result
 movsd [r12+rax],xmm0
.science_result:
 call .format_science
 jmp .record
.integer_expression:
 mov rdi,rbp
 lea rsi,[r12+CALC_INT_ANS]
 call calc_eval_context
 mov r14d,edx
 test edx,edx
 jnz .error
 mov [r12+CALC_INT_ANS],rax
 call .format_integer
 jmp .record
 ; Formatting helpers called internally AND jumped to by memory recall.
 ; The recall path must call them too, then return through the common epilogue.
.format_science:
 mov rdi,r13
 mov esi,[r12+CALC_PRECISION]
 sub rsp,8
 call calc_float_format
 add rsp,8
 jmp .newline
.format_integer:
 mov rdi,rax
 mov esi,[r12+CALC_BASE]
 mov rdx,r13
 sub rsp,8
 call calc_format
 add rsp,8
.newline:
 mov byte [r13+rdx],10
 mov byte [r13+rdx+1],0
 ret
.record:
 mov r15,[r12+CALC_NEXT]
 imul rax,r15,CALC_SLOT
 lea rdi,[r12+CALC_HISTORY+rax]
 mov rsi,rbp
.record_expression:
 lodsb
 test al,al
 jz .separator
 stosb
 jmp .record_expression
.separator:
 mov byte [rdi],' '
 mov byte [rdi+1],'='
 mov byte [rdi+2],' '
 add rdi,3
 mov rsi,r13
.record_result:
 lodsb
 stosb
 test al,al
 jnz .record_result
 inc r15d
 and r15d,15
 mov [r12+CALC_NEXT],r15
 cmp qword [r12+CALC_COUNT],16
 jae .done
 inc qword [r12+CALC_COUNT]
 jmp .done
.range:
 mov r14d,2
 jmp .error
.syntax:
 mov r14d,1
.error:
 lea rax,[session_errors]
 mov rsi,[rax+r14*8]
.message:
 mov rdi,r13
.message_copy:
 lodsb
 stosb
 test al,al
 jnz .message_copy
 jmp .done
.null:
 mov r14d,6
.done:
 mov eax,r14d
 add rsp,280
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbp
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
