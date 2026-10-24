; Link the separately assembled shell into the existing flat ULF kernel.
; build/kernel/*.bin are placeholders until kernel_bundle.py links them at
; the exact NASM-assigned addresses. The final ULF is stamped only afterward.
%include "apps/ush/build/kernel/layout.inc"
section .text
kernel_ush_spawn:
    sub rsp,8
    mov rdi,kernel_ush_fiber
    xor esi,esi
    mov edx,PRIO_NORMAL
    mov ecx,FIBER_RESTART_NEVER
    xor r8d,r8d                    ; initial BSP logical CPU
    mov r9,1                       ; BSP affinity: console is serialized
    call fiber_create_on_cpu
    test rax,rax
    jnz .done
    mov rsi,kernel_ush_failed
    call uart_print_str
.done:
    add rsp,8
    ret
kernel_ush_fiber:
    sub rsp,8
    ; Idle UART polls yield to scheduler/heartbeat/network fibers.
    mov rax,kernel_ush_yield
    mov [kernel_ush_bss+KERNEL_USH_IDLE_HOOK_OFFSET],rax
    mov rax,mono_get_nanos
    mov [kernel_ush_bss+KERNEL_USH_CLOCK_HOOK_OFFSET],rax
    mov rax,kernel_ush_sleep
    mov [kernel_ush_bss+KERNEL_USH_SLEEP_HOOK_OFFSET],rax
    mov rax,kernel_ush_power
    mov [kernel_ush_bss+KERNEL_USH_POWER_HOOK_OFFSET],rax
    mov rsi,kernel_ush_started
    call uart_print_str
    mov rdi,kernel_ush_data+KERNEL_USH_UART_OFFSET
    mov esi,1                       ; interactive shell
    call kernel_ush_text+KERNEL_USH_MAIN_OFFSET
    mov rsi,kernel_ush_exited
    call uart_print_str
    add rsp,8
    ret                             ; restart policy NEVER
kernel_ush_yield:
    sub rsp,8
    call fiber_yield
    add rsp,8
    ret
; Seconds -> monotonic deadline. Yield rather than hold up the console's BSP.
kernel_ush_sleep:
    push rbx
    imul rbx,rdi,1000000000
    call mono_get_nanos
    add rbx,rax
    jc .failed
.wait:
    call mono_get_nanos
    cmp rax,rbx
    jae .done
    call fiber_yield
    jmp .wait
.done:
    xor eax,eax
    pop rbx
    ret
.failed:
    mov rax,-1
    pop rbx
    ret
; QEMU i440fx/PIIX4 and q35/ICH9 power control. Discover the firmware-configured
; PMBASE via the existing locked PCI config API; no guessed FADT/AML S5 values
; and no debug-exit device masquerading as a power-off. Other chipsets fail.
; The S5 type-zero and CF9 reset contract is qualified on these QEMU chipsets.
kernel_ush_power:
    push rbx
    push r12
    push r13
    mov r13,rdi
    xor ebx,ebx
.scan:
    mov edi,ebx                 ; root bus BDF, device/function 0..255
    xor esi,esi
    mov edx,4
    call kpci_cfg_read
    jc .next
    cmp eax,0x71138086          ; PIIX4 PM
    je .found
    cmp eax,0x29188086          ; ICH9 LPC
    je .found
.next:
    inc ebx
    cmp ebx,256
    jb .scan
    jmp .failed
.found:
    mov r12d,eax
    test r13,r13
    jnz .reset
    mov edi,ebx
    mov esi,0x40
    mov edx,4
    call kpci_cfg_read
    jc .failed
    test eax,1
    jz .failed
    cmp r12d,0x71138086
    jne .ich9
    and eax,0xffc0
    jmp .base
.ich9:
    and eax,0xff80
.base:
    test eax,eax
    jz .failed
    lea edx,[eax+4]             ; PM1 control
    in ax,dx
    and ax,0xc3ff              ; clear SLP_TYP and SLP_EN, preserve SCI_EN
    or ax,0x2000               ; QEMU PIIX4/ICH9 S5
    out dx,ax
    jmp .failed                ; a working power-off does not return
.reset:
    mov dx,0xcf9
    mov al,2                   ; system reset selection
    out dx,al
    mov al,6                   ; assert reset
    out dx,al
.failed:
    mov rax,-1
    pop r13
    pop r12
    pop rbx
    ret
; Background writers pair these around a complete diagnostic line. Serialized
; BSP console ownership lets the editor restore text/cursor without cross-CPU
; output races. Fatal exception diagnostics intentionally bypass this path.
kernel_ush_log_begin:
    jmp kernel_ush_text+KERNEL_USH_LOG_BEGIN_OFFSET
kernel_ush_log_end:
    jmp kernel_ush_text+KERNEL_USH_LOG_END_OFFSET
align 64,db 0x90
kernel_ush_text:
    incbin "apps/ush/build/kernel/text.bin"
section .rodata
align 64
kernel_ush_rodata:
    incbin "apps/ush/build/kernel/rodata.bin"
kernel_ush_layout:
    db 'UTKUSH_LAYOUT_V1',0
    dq kernel_ush_text,kernel_ush_rodata,kernel_ush_data,kernel_ush_bss
    dq KERNEL_USH_TEXT_SIZE,KERNEL_USH_RODATA_SIZE,KERNEL_USH_DATA_SIZE,KERNEL_USH_BSS_SIZE
kernel_ush_started: db '[ush] kernel console starting',13,10,0
kernel_ush_exited: db '[ush] exited; kernel scheduler continues',13,10,0
kernel_ush_failed: db 'ERROR: Ush console fiber allocation failed',13,10,0
section .data
align 64
kernel_ush_data:
    incbin "apps/ush/build/kernel/data.bin"
section .bss
align 64
kernel_ush_bss:
    resb KERNEL_USH_BSS_SIZE
