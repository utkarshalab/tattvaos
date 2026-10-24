; Bounded PIO on SECONDARY MASTER only (ports 170/376). Never probes/writes
; the primary boot device. QEMU IDE test backend; not an AHCI/NVMe driver.
%include "storage/uxfs/volume.inc"
bits 64
default rel
extern uxv_read,uxv_write,uxv_flush
section .bss
identify: resb 512
section .text
global uxv_ata_init
uxv_ata_init:
 push rbx
 mov dx,0x376
 mov al,2                       ; no IRQ: synchronous polling owns the channel
 out dx,al
 mov dx,0x176
 mov al,0xa0
 out dx,al
 call delay
 mov dx,0x172
 xor eax,eax
 out dx,al
 inc dx
 out dx,al
 inc dx
 out dx,al
 inc dx
 out dx,al
 mov dx,0x177
 mov al,0xec
 out dx,al
 call wait_data
 test eax,eax
 js .done
 lea rdi,[identify]
 mov ecx,256
 mov dx,0x170
 cld
 rep insw
 test word [identify+98],0x200 ; LBA supported
 jz .done
 mov eax,[identify+120]
 cmp eax,UV_BANK*2
 jb .done
 lea rax,[read]
 mov [uxv_read],rax
 lea rax,[write]
 mov [uxv_write],rax
 lea rax,[flush]
 mov [uxv_flush],rax
.done:
 pop rbx
 ret
delay:
 mov dx,0x376
 in al,dx
 in al,dx
 in al,dx
 in al,dx
 ret
wait_data:
 mov r9d,1000000
 mov dx,0x177
.poll:
 in al,dx
 cmp al,0xff
 je error
 test al,al
 jz error
 test al,0x80
 jnz .again
 test al,0x21                  ; ERR or DF
 jnz error
 test al,8
 jnz success
.again:
 pause
 dec r9d
 jnz .poll
 jmp error
wait_idle:
 mov r9d,1000000
 mov dx,0x177
.poll:
 in al,dx
 cmp al,0xff
 je error
 test al,al
 jz error
 test al,0x80
 jnz .again
 test al,0x21
 jnz error
 test al,8
 jz success
.again:
 pause
 dec r9d
 jnz .poll
 jmp error
success: xor eax,eax
 ret
error: mov rax,-5
 ret
read:
 mov r8d,0x20
 jmp transfer
write:
 mov r8d,0x30
transfer:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdi
 mov r13,rsi
 mov r14,rdx
 mov r15,r8
 test r13,r13
 jz .fail
 lea rax,[r12+r13]
 cmp rax,UV_BANK*2
 ja .fail
.sector:
 call wait_idle
 test eax,eax
 js .done
 mov dx,0x176
 mov al,0xe0
 out dx,al
 call delay
 mov dx,0x172
 mov al,1
 out dx,al
 inc dx
 mov eax,r12d
 out dx,al
 inc dx
 shr eax,8
 out dx,al
 inc dx
 shr eax,8
 out dx,al
 mov dx,0x177
 mov eax,r15d
 out dx,al
 call delay
 call wait_data
 test eax,eax
 js .done
 mov dx,0x170
 mov ecx,256
 cmp r15d,0x30
 je .out
 mov rdi,r14
 rep insw
 jmp .complete
.out:
 mov rsi,r14
 rep outsw
.complete:
 call delay
 call wait_idle
 test eax,eax
 js .done
 inc r12
 add r14,512
 dec r13
 jnz .sector
 xor eax,eax
 jmp .done
.fail: mov rax,-5
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
flush:
 sub rsp,8
 call wait_idle
 test eax,eax
 js .done
 mov dx,0x177
 mov al,0xe7
 out dx,al
 call delay
 call wait_idle
.done:
 add rsp,8
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
