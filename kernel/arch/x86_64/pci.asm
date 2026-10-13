%ifndef KERNEL_ARCH_X86_64_PCI_ASM
%define KERNEL_ARCH_X86_64_PCI_ASM
; =============================================================================
; Kernel-owned PCI configuration mechanism #1 and conventional capabilities.
;
; CF8/CFC is a process-wide address/data pair. Every transaction disables local
; interrupts and holds one global lock so another CPU cannot redirect the data
; port between the address and data operations. Inputs are rejected rather than
; masked into a different BDF, register, or access width.
; Runtime callers must not bypass this API or invoke it from NMI context.
; =============================================================================

[BITS 64]

KPCI_CONFIG_ADDRESS_PORT       equ 0x0CF8
KPCI_CONFIG_DATA_PORT          equ 0x0CFC
KPCI_CONFIG_ENABLE             equ 0x80000000
KPCI_CONFIG_SPACE_BYTES        equ 256
KPCI_CAP_STATUS_BIT            equ 1 << 4
KPCI_CAP_POINTER_MIN           equ 0x40
KPCI_CAP_POINTER_MAX           equ 0xFC
KPCI_CAP_MAX_NODES             equ 48

%macro KPCI_CONFIG_LOCK 0
    pushfq
    pop r11
    cli
%%spin:
    mov eax, 1
    xchg eax, [rel kpci_config_lock]
    test eax, eax
    jz %%locked
    pause
    jmp %%spin
%%locked:
%endmacro

%macro KPCI_CONFIG_UNLOCK 0
    mov dword [rel kpci_config_lock], 0
    push r11
    popfq
%endmacro

section .text

; EDI=BDF (bus:15..8, device:7..3, function:2..0), ESI=offset, EDX=1/2/4.
; CF=0: EAX=CF8 address value, ECX=data port. CF=1: inputs invalid.
global kpci_cfg_compose
kpci_cfg_compose:
    test edi, 0xFFFF0000
    jnz .invalid
    cmp edx, 1
    je .byte
    cmp edx, 2
    je .word
    cmp edx, 4
    jne .invalid
    cmp esi, KPCI_CONFIG_SPACE_BYTES - 4
    ja .invalid
    test esi, 3
    jnz .invalid
    jmp .compose
.word:
    cmp esi, KPCI_CONFIG_SPACE_BYTES - 2
    ja .invalid
    test esi, 1
    jnz .invalid
    jmp .compose
.byte:
    cmp esi, KPCI_CONFIG_SPACE_BYTES - 1
    ja .invalid
.compose:
    mov eax, edi
    shl eax, 8
    mov ecx, esi
    and ecx, -4
    or eax, ecx
    or eax, KPCI_CONFIG_ENABLE
    mov ecx, esi
    and ecx, 3
    add ecx, KPCI_CONFIG_DATA_PORT
    clc
    ret
.invalid:
    xor eax, eax
    xor ecx, ecx
    stc
    ret

; EDI=BDF, ESI=offset, EDX=1/2/4. CF=0/EAX=value; CF=1/EAX=-1.
global kpci_cfg_read
kpci_cfg_read:
    push rbx
    mov ebx, edx
    call kpci_cfg_compose
    jc .invalid
    mov r8d, eax
    mov r9d, ecx

    KPCI_CONFIG_LOCK
    mov eax, r8d
    mov dx, KPCI_CONFIG_ADDRESS_PORT
    out dx, eax
    mov edx, r9d
    cmp ebx, 1
    je .read8
    cmp ebx, 2
    je .read16
    in eax, dx
    jmp .read_done
.read16:
    xor eax, eax
    in ax, dx
    jmp .read_done
.read8:
    xor eax, eax
    in al, dx
.read_done:
    mov r8d, eax
    KPCI_CONFIG_UNLOCK
    mov eax, r8d
    pop rbx
    clc
    ret
.invalid:
    mov eax, -1
    pop rbx
    stc
    ret

; EDI=BDF, ESI=offset, EDX=1/2/4, ECX=value. CF=0/EAX=1; CF=1/EAX=0.
global kpci_cfg_write
kpci_cfg_write:
    push rbx
    mov ebx, edx
    mov r10d, ecx
    call kpci_cfg_compose
    jc .invalid
    mov r8d, eax
    mov r9d, ecx

    KPCI_CONFIG_LOCK
    mov eax, r8d
    mov dx, KPCI_CONFIG_ADDRESS_PORT
    out dx, eax
    mov edx, r9d
    mov eax, r10d
    cmp ebx, 1
    je .write8
    cmp ebx, 2
    je .write16
    out dx, eax
    jmp .write_done
.write16:
    out dx, ax
    jmp .write_done
.write8:
    out dx, al
.write_done:
    KPCI_CONFIG_UNLOCK
    mov eax, 1
    pop rbx
    clc
    ret
.invalid:
    xor eax, eax
    pop rbx
    stc
    ret

; EDI=BDF, RSI=256-byte output. Reads one serialized conventional config image.
; CF=0/EAX=1 on success; CF=1/EAX=0 on invalid input.
global kpci_cfg_snapshot
kpci_cfg_snapshot:
    push rbx
    push r12
    push r13
    test edi, 0xFFFF0000
    jnz .invalid
    test rsi, rsi
    jz .invalid
    mov rax, rsi
    add rax, KPCI_CONFIG_SPACE_BYTES
    jc .invalid
    mov r12d, edi
    mov r13, rsi

    KPCI_CONFIG_LOCK
    xor ebx, ebx
.snapshot_loop:
    mov eax, r12d
    shl eax, 8
    or eax, ebx
    or eax, KPCI_CONFIG_ENABLE
    mov dx, KPCI_CONFIG_ADDRESS_PORT
    out dx, eax
    mov dx, KPCI_CONFIG_DATA_PORT
    in eax, dx
    mov [r13 + rbx], eax
    add ebx, 4
    cmp ebx, KPCI_CONFIG_SPACE_BYTES
    jb .snapshot_loop
    KPCI_CONFIG_UNLOCK
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    clc
    ret
.invalid:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    stc
    ret

; RDI=configuration snapshot, RSI=accessible bytes, EDX=capability ID.
; CF=0/RAX=capability offset (zero means absent); CF=1/RAX=0 malformed input.
global kpci_find_capability_snapshot
kpci_find_capability_snapshot:
    test rdi, rdi
    jz .invalid
    cmp rsi, KPCI_CONFIG_SPACE_BYTES
    jb .invalid
    mov rax, rdi
    add rax, KPCI_CONFIG_SPACE_BYTES
    jc .invalid
    test edx, edx
    jz .invalid
    cmp edx, 0xFF
    jae .invalid
    cmp word [rdi], 0xFFFF           ; no function responds at this BDF
    je .not_found
    test word [rdi + 0x06], KPCI_CAP_STATUS_BIT
    jz .not_found

    movzx eax, byte [rdi + 0x0E]
    and eax, 0x7F
    cmp eax, 1
    jbe .standard_header
    cmp eax, 2
    jne .invalid
    movzx r8d, byte [rdi + 0x14]
    jmp .walk_ready
.standard_header:
    movzx r8d, byte [rdi + 0x34]
.walk_ready:
    xor r9d, r9d                    ; visited bitmap for 48 aligned slots
    mov r10d, KPCI_CAP_MAX_NODES
    xor r11d, r11d                  ; first matching capability offset

.walk:
    test r8d, r8d
    jz .complete
    test r10d, r10d
    jz .invalid
    dec r10d
    cmp r8d, KPCI_CAP_POINTER_MIN
    jb .invalid
    cmp r8d, KPCI_CAP_POINTER_MAX
    ja .invalid
    test r8d, 3
    jnz .invalid
    mov eax, r8d
    sub eax, KPCI_CAP_POINTER_MIN
    shr eax, 2
    bt r9, rax
    jc .invalid
    bts r9, rax

    movzx eax, byte [rdi + r8]      ; ID 0 is the valid Null capability
    cmp eax, 0xFF
    je .invalid
    cmp eax, edx
    jne .advance
    test r11d, r11d
    jnz .advance
    mov r11d, r8d
.advance:
    movzx r8d, byte [rdi + r8 + 1]
    jmp .walk

.complete:
    mov eax, r11d
    clc
    ret
.not_found:
    xor eax, eax
    clc
    ret
.invalid:
    xor eax, eax
    stc
    ret

; EDI=BDF, ESI=capability ID. Uses the exact bounded snapshot parser above.
; CF=0/RAX=capability offset (zero means absent); CF=1 malformed/unreadable.
global kpci_find_capability
kpci_find_capability:
    push rbx
    sub rsp, KPCI_CONFIG_SPACE_BYTES
    mov ebx, esi
    mov rsi, rsp
    call kpci_cfg_snapshot
    jc .invalid
    mov rdi, rsp
    mov esi, KPCI_CONFIG_SPACE_BYTES
    mov edx, ebx
    call kpci_find_capability_snapshot
    jc .invalid
    lea rsp, [rsp + KPCI_CONFIG_SPACE_BYTES]
    pop rbx
    clc
    ret
.invalid:
    lea rsp, [rsp + KPCI_CONFIG_SPACE_BYTES]
    pop rbx
    xor eax, eax
    stc
    ret

section .bss
alignb 4
kpci_config_lock: resd 1

%unmacro KPCI_CONFIG_LOCK 0
%unmacro KPCI_CONFIG_UNLOCK 0

%endif ; KERNEL_ARCH_X86_64_PCI_ASM
