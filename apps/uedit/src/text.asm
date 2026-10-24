; Strict UTF-8 scalars; CRLF is one newline. No overlong/surrogate/control input.
bits 64
default rel
section .text
global ue_decode,ue_validate,ue_prev,ue_width
; (bytes,remaining) -> eax=scalar, edx=byte count; eax=-1 invalid.
extern str_utf8_decode
extern _ucd_cat_stage1,_ucd_cat_stage2,_ucd_eaw_stage1,_ucd_eaw_stage2
ue_decode:
 test rdi,rdi
 jz .empty
 test rsi,rsi
 jz .empty
 ; Preserve scan registers used by the renderer across the library call.
 push r10
 push r11
 sub rsp,24
 lea rdx,[rsp]
 lea rcx,[rsp+8]
 call str_utf8_decode
 test rax,rax
 js .bad
 mov eax,[rsp]
 mov rdx,[rsp+8]
 cmp eax,13
 je .cr
 cmp eax,9
 je .done
 cmp eax,10
 je .done
 cmp eax,32
 jb .bad
 cmp eax,127
 jb .done
 cmp eax,159
 jbe .bad
 jmp .done
.cr:
 cmp rsi,2
 jb .bad
 cmp byte [rdi+1],10
 jne .bad
 mov eax,10
 mov edx,2
 jmp .done
.bad: mov eax,-1
 xor edx,edx
.done:
 add rsp,24
 pop r11
 pop r10
 ret
.empty:
 mov eax,-1
 xor edx,edx
 ret
; (bytes,length) -> 0 / -1
ue_validate:
 push rbx
 push r12
 push r13
 mov rbx,rdi
 mov r12,rsi
 xor r13d,r13d
.loop:
 cmp r13,r12
 jae .ok
 lea rdi,[rbx+r13]
 mov rsi,r12
 sub rsi,r13
 call ue_decode
 test eax,eax
 js .bad
 add r13,rdx
 jmp .loop
.ok: xor eax,eax
 jmp .done
.bad: mov rax,-1
.done: pop r13
 pop r12
 pop rbx
 ret
; (data,offset) -> preceding scalar/CRLF boundary. Input already valid.
ue_prev:
 mov rax,rsi
 test rax,rax
 jz .done
 dec rax
 cmp byte [rdi+rax],10
 jne .utf
 test rax,rax
 jz .done
 cmp byte [rdi+rax-1],13
 jne .done
 dec rax
 ret
.utf:
 mov cl,[rdi+rax]
 and cl,0xc0
 cmp cl,0x80
 jne .done
 dec rax
 jmp .utf
.done: ret
; eax=scalar -> eax=terminal cells. Reuse lib/str's generated UCD tries.
ue_width:
 mov ecx,eax
 shr ecx,8
 lea rdi,[_ucd_cat_stage1]
 movzx ecx,word [rdi+rcx*2]
 shl ecx,8
 movzx r8d,al
 add ecx,r8d
 lea rdi,[_ucd_cat_stage2]
 movzx ecx,byte [rdi+rcx]
 cmp ecx,5                         ; Mn
 je .zero
 cmp ecx,7                         ; Me
 je .zero
 cmp ecx,26                        ; Cf
 je .zero
 mov ecx,eax
 shr ecx,8
 lea rdi,[_ucd_eaw_stage1]
 movzx ecx,word [rdi+rcx*2]
 shl ecx,8
 add ecx,r8d
 lea rdi,[_ucd_eaw_stage2]
 movzx ecx,byte [rdi+rcx]
 mov eax,1
 cmp ecx,3                         ; W
 je .wide
 cmp ecx,4                         ; F
 jne .done
.wide: inc eax
.done: ret
.zero: xor eax,eax
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
