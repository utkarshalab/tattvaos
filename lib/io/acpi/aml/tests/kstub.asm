; =============================================================================
; lib/io/acpi/aml/tests/kstub.asm — the kernel symbols kernel.asm uses, for
; host tests: boot information, the physical allocator's state, console
; output (captured into a buffer), a page allocator handing out one region,
; and do-nothing clock and delay. Then the interpreter and its kernel glue.
; =============================================================================

%include "boot/boot_info.inc"
%include "lib/mem/mem.inc"

section .data
align 8
global boot_info_ptr
boot_info_ptr:      dq 0
global phys_state
phys_state:         times phys_state_t_size db 0
global kstub_pages              ; what phys_alloc_pages returns (0: none)
kstub_pages:        dq 0
global kstub_out_len
kstub_out_len:      dd 0
global kstub_delays
kstub_delays:       dq 0        ; microseconds asked of udelay

section .bss
global kstub_out
kstub_out:          resb 8192   ; console output
global kernel_text_start
kernel_text_start:  resb 64     ; stands for the kernel image
global kernel_bss_end
kernel_bss_end:

section .text

; append AL to the captured output; preserves every register
kstub_putc:
    push rcx
    push rdx
    mov ecx, [rel kstub_out_len]
    cmp ecx, 8191
    jae .full
    lea rdx, [rel kstub_out]
    mov [rdx + rcx], al
    inc dword [rel kstub_out_len]
.full:
    pop rdx
    pop rcx
    ret

; RSI = string; preserves every register
global uart_print_str
uart_print_str:
    push rax
    push rdx
    push rsi
.next:
    lodsb
    test al, al
    jz .done
    call kstub_putc
    jmp .next
.done:
    pop rsi
    pop rdx
    pop rax
    ret

; EAX = unsigned decimal; preserves every register
global uart_print_dec
uart_print_dec:
    push rax
    push rbx
    push rcx
    push rdx
    sub rsp, 16
    mov ebx, 10
    xor ecx, ecx
.div:
    xor edx, edx
    div ebx
    add dl, '0'
    mov [rsp + rcx], dl
    inc ecx
    test eax, eax
    jnz .div
.out:
    dec ecx
    mov al, [rsp + rcx]
    call kstub_putc
    test ecx, ecx
    jnz .out
    add rsp, 16
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; RAX = 64-bit hex, sixteen digits; preserves every register
global uart_print_hex64
uart_print_hex64:
    push rax
    push rcx
    push rdx
    mov rdx, rax
    mov ecx, 60
.digit:
    mov rax, rdx
    shr rax, cl
    and eax, 0x0F
    add al, '0'
    cmp al, '9'
    jbe .put
    add al, 'A' - '9' - 1
.put:
    call kstub_putc
    sub ecx, 4
    jns .digit
    pop rdx
    pop rcx
    pop rax
    ret

; RDI = pages; RAX = kstub_pages once, then 0
global phys_alloc_pages
phys_alloc_pages:
    mov rax, [rel kstub_pages]
    mov qword [rel kstub_pages], 0
    ret

global mono_get_nanos
mono_get_nanos:
    xor eax, eax
    ret

; RDI = microseconds
global udelay
udelay:
    add [rel kstub_delays], rdi
    ret

%include "lib/io/acpi/aml/aml.asm"
%include "lib/io/acpi/aml/kernel.asm"
