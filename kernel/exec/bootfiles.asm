; =============================================================================
; Utkarsha OS — kernel/exec/bootfiles.asm — files that come with the kernel
; =============================================================================
; The boot loaders (BIOS and UEFI) load initrd.img beside the kernel and say
; where it is in the boot information. Here it is a UPK package
; (docs/UPK_SPEC.md) of files the kernel needs before any disk is mounted:
; configuration (conf/usb/usb.conf) and firmware for devices.
;
;   boot_files_init     open and check it once, at start-up; one console
;                       line. Never stops the boot.
;   boot_file(path)     a file's bytes and size, by its package path
;                       ("conf/usb/usb.conf"); RAX = 0 when there is none
;
; Trust: the package is checked as any package is (every file's SHA-256,
; the manifest). A signed one must be signed by a key in
; boot_trusted_keys, built into the kernel; an unsigned one is accepted,
; since nothing checks the kernel image beside it either. Nothing in it
; runs.
; =============================================================================

%ifndef KERNEL_EXEC_BOOTFILES_ASM
%define KERNEL_EXEC_BOOTFILES_ASM

section .rodata
align 8
; Ed25519 public keys trusted to sign boot packages (32 bytes each). None
; yet: a build that signs its boot packages adds its key here.
boot_trusted_keys:
BOOT_TRUSTED_KEYS   equ 0
msg_boot_none:      db "BOOT: no boot files (no initrd.img)", 0x0D, 0x0A, 0
msg_boot_far:       db "BOOT: boot files out of reach; not used", 0x0D, 0x0A, 0
msg_boot_bad:       db "BOOT: boot files refused, error ", 0
msg_boot_ok:        db "BOOT: boot files ", 0
msg_boot_files:     db " files, ", 0
msg_boot_signed:    db "signed", 0x0D, 0x0A, 0
msg_boot_unsigned:  db "unsigned", 0x0D, 0x0A, 0
msg_boot_space:     db " ", 0
msg_boot_comma:     db ", ", 0
msg_boot_crlf:      db 0x0D, 0x0A, 0

section .bss
alignb 8
global boot_files_ready
boot_files_ready:   resd 1
boot_files_name:    resb UPK_MAX_NAME + 1
alignb 8
global boot_files_pkg
boot_files_pkg:     resb upk_pkg_t_size

section .text

; -----------------------------------------------------------------------------
; boot_files_init
; -----------------------------------------------------------------------------
global boot_files_init
boot_files_init:
    push rbx
    push r12
    push r13
    mov dword [rel boot_files_ready], 0
    mov rax, [rel boot_info_ptr]
    test rax, rax
    jz .none
    mov r12, [rax + BOOT_INFO_INITRD_ADDR_OFF]
    mov r13, [rax + BOOT_INFO_INITRD_SIZE_OFF]
    test r12, r12
    jz .none
    test r13, r13
    jz .none
    ; it must lie inside the direct map to be read where it is
    mov rax, r12
    add rax, r13
    jc .far
    cmp rax, [rel phys_state + phys_state_t.direct_map_limit]
    ja .far
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rel boot_trusted_keys]
    mov ecx, BOOT_TRUSTED_KEYS
    lea r8, [rel boot_files_pkg]
    mov r9d, 1                          ; unsigned is accepted (see the top)
    call upk_open
    test eax, eax
    jnz .bad
    mov dword [rel boot_files_ready], 1
    ; BOOT: boot files <name> <version>, <n> files, signed|unsigned
    lea rsi, [rel msg_boot_ok]
    call uart_print_str
    lea rbx, [rel boot_files_pkg]
    mov rsi, [rbx + upk_pkg_t.name]
    mov rcx, [rbx + upk_pkg_t.name_len]
    call boot_files_print_n
    lea rsi, [rel msg_boot_space]
    call uart_print_str
    mov rsi, [rbx + upk_pkg_t.version]
    mov rcx, [rbx + upk_pkg_t.version_len]
    call boot_files_print_n
    lea rsi, [rel msg_boot_comma]
    call uart_print_str
    mov rax, [rbx + upk_pkg_t.count]
    call uart_print_dec
    lea rsi, [rel msg_boot_files]
    call uart_print_str
    lea rsi, [rel msg_boot_unsigned]
    cmp dword [rbx + upk_pkg_t.signed], 0
    je .say
    lea rsi, [rel msg_boot_signed]
.say:
    call uart_print_str
    jmp .out
.bad:
    mov ebx, eax
    lea rsi, [rel msg_boot_bad]
    call uart_print_str
    mov eax, ebx
    neg eax
    call uart_print_dec
    lea rsi, [rel msg_boot_crlf]
    call uart_print_str
    jmp .out
.far:
    lea rsi, [rel msg_boot_far]
    call uart_print_str
    jmp .out
.none:
    lea rsi, [rel msg_boot_none]
    call uart_print_str
.out:
    pop r13
    pop r12
    pop rbx
    ret

; boot_files_print_n — RSI, RCX = text that is not NUL-terminated (at most
; UPK_MAX_NAME bytes are printed)
boot_files_print_n:
    push rdi
    cmp rcx, UPK_MAX_NAME
    jbe .len
    mov ecx, UPK_MAX_NAME
.len:
    lea rdi, [rel boot_files_name]
    mov byte [rdi + rcx], 0
    rep movsb
    lea rsi, [rel boot_files_name]
    call uart_print_str
    pop rdi
    ret

; -----------------------------------------------------------------------------
; boot_file — RDI = package path (NUL-terminated) → RAX = bytes, RDX = size;
;             RAX = 0 when there are no boot files or no such file
; -----------------------------------------------------------------------------
global boot_file
boot_file:
    xor eax, eax
    xor edx, edx
    cmp dword [rel boot_files_ready], 0
    je .out
    mov rsi, rdi
    lea rdi, [rel boot_files_pkg]
    jmp upk_file
.out:
    ret

%endif ; KERNEL_EXEC_BOOTFILES_ASM
