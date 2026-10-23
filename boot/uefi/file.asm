; =============================================================================
; Utkarsha OS — boot/uefi/file.asm
; =============================================================================
; Owned, size-checked UEFI payload loading.  Files are opened from the same
; device that loaded this EFI image, sized with EFI_FILE_INFO, and copied only
; into pages allocated from firmware.  Every protocol call follows the
; Microsoft x64 ABI and all pre-handoff failures unwind their page ownership.
; =============================================================================

%ifndef UEFI_FILE_ASM
%define UEFI_FILE_ASM

%include "protocol.asm"
%include "ulf.asm"

[BITS 64]

SFS_OPEN_VOLUME                 equ 8

FILE_OPEN                       equ 8
FILE_CLOSE                      equ 16
FILE_READ                       equ 32
FILE_SET_POSITION               equ 56
FILE_GET_INFO                   equ 64

FILE_MODE_READ                  equ 0x0000000000000001
EFI_FILE_INFO_MIN_SIZE          equ 80
EFI_FILE_INFO_FILE_SIZE         equ 8
EFI_FILE_INFO_ATTRIBUTE         equ 72
EFI_FILE_DIRECTORY              equ 0x10
EFI_FILE_INFO_MAX_SIZE          equ 65536
LOADED_IMAGE_DEVICE_HANDLE      equ 24

section .data
align 8
uefi_kernel_addr:        dq 0
uefi_kernel_size:        dq 0
uefi_kernel_pages:       dq 0
uefi_kernel_memory_size: dq 0
uefi_kernel_exec_size:   dq 0
uefi_kernel_entry:       dq 0

uefi_initrd_addr:        dq 0
uefi_initrd_size:        dq 0
uefi_initrd_pages:       dq 0

section .bss align=16
uefi_ulf_header_scratch: resb ULF_HEADER_SIZE

section .text

; -----------------------------------------------------------------------------
; uefi_open_boot_volume
; RCX = SystemTable, RDX = ImageHandle
; RAX = EFI_STATUS, RDX = root EFI_FILE_PROTOCOL on success
; -----------------------------------------------------------------------------
uefi_open_boot_volume:
    push rbp
    mov rbp, rsp
    sub rsp, 96                     ; bottom 32 bytes are firmware home space

    mov [rbp - 8], rcx
    mov [rbp - 16], rdx
    mov qword [rbp - 24], 0         ; LoadedImage
    mov qword [rbp - 32], 0         ; SimpleFileSystem
    mov qword [rbp - 40], 0         ; root

    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES]
    test rax, rax
    jz .unsupported
    mov [rbp - 48], rax

    mov rcx, [rbp - 16]
    lea rdx, [rel loaded_image_guid]
    lea r8, [rbp - 24]
    mov rax, [rax + BS_HANDLE_PROTOCOL]
    call rax
    test rax, rax
    jnz .failed

    mov rax, [rbp - 24]
    test rax, rax
    jz .load_error
    mov rcx, [rax + LOADED_IMAGE_DEVICE_HANDLE]
    test rcx, rcx
    jz .load_error

    lea rdx, [rel sfs_guid]
    lea r8, [rbp - 32]
    mov rax, [rbp - 48]
    mov rax, [rax + BS_HANDLE_PROTOCOL]
    call rax
    test rax, rax
    jnz .failed

    mov rcx, [rbp - 32]
    test rcx, rcx
    jz .load_error
    lea rdx, [rbp - 40]
    mov rax, [rcx + SFS_OPEN_VOLUME]
    call rax
    test rax, rax
    jnz .failed

    mov rdx, [rbp - 40]
    test rdx, rdx
    jz .load_error
    xor eax, eax
    jmp .done

.unsupported:
    mov rax, EFI_UNSUPPORTED
    jmp .failed
.load_error:
    mov rax, EFI_LOAD_ERROR
.failed:
    xor edx, edx
.done:
    mov rsp, rbp
    pop rbp
    ret

; -----------------------------------------------------------------------------
; uefi_file_get_size
; RCX = SystemTable, RDX = open file, R8 = UINT64 output pointer
; RAX = EFI_STATUS
; -----------------------------------------------------------------------------
uefi_file_get_size:
    push rbp
    mov rbp, rsp
    sub rsp, 128                    ; bottom 32 bytes are firmware home space

    mov [rbp - 8], rcx
    mov [rbp - 16], rdx
    mov [rbp - 24], r8
    mov qword [rbp - 32], 0         ; EFI_FILE_INFO buffer size
    mov qword [rbp - 40], 0         ; EFI_FILE_INFO buffer
    mov qword [rbp - 48], 0         ; allocated buffer size

    test rdx, rdx
    jz .load_error
    test r8, r8
    jz .load_error
    mov qword [r8], 0

    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES]
    test rax, rax
    jz .unsupported
    mov [rbp - 56], rax

    ; First query obtains the complete variable-length EFI_FILE_INFO size.
    mov rcx, [rbp - 16]
    lea rdx, [rel file_info_guid]
    lea r8, [rbp - 32]
    xor r9d, r9d
    mov rax, [rcx + FILE_GET_INFO]
    call rax
    mov r10, EFI_BUFFER_TOO_SMALL
    cmp rax, r10
    jne .unexpected_probe_status

    mov rax, [rbp - 32]
    cmp rax, EFI_FILE_INFO_MIN_SIZE
    jb .load_error
    cmp rax, EFI_FILE_INFO_MAX_SIZE
    ja .load_error
    mov [rbp - 48], rax

    mov ecx, EFI_LOADER_DATA
    mov rdx, rax
    lea r8, [rbp - 40]
    mov rax, [rbp - 56]
    mov rax, [rax + BS_ALLOCATE_POOL]
    call rax
    test rax, rax
    jnz .done
    cmp qword [rbp - 40], 0
    je .load_error

    mov rcx, [rbp - 16]
    lea rdx, [rel file_info_guid]
    lea r8, [rbp - 32]
    mov r9, [rbp - 40]
    mov rax, [rcx + FILE_GET_INFO]
    call rax
    test rax, rax
    jnz .free_with_status

    mov rax, [rbp - 32]
    cmp rax, EFI_FILE_INFO_MIN_SIZE
    jb .invalid_info
    cmp rax, [rbp - 48]
    ja .invalid_info
    mov rdx, [rbp - 40]
    mov rcx, [rdx]
    cmp rcx, EFI_FILE_INFO_MIN_SIZE
    jb .invalid_info
    cmp rcx, rax
    ja .invalid_info
    test qword [rdx + EFI_FILE_INFO_ATTRIBUTE], EFI_FILE_DIRECTORY
    jnz .invalid_info

    mov rax, [rdx + EFI_FILE_INFO_FILE_SIZE]
    mov rcx, [rbp - 24]
    mov [rcx], rax
    xor eax, eax
    jmp .free_with_status

.unexpected_probe_status:
    test rax, rax
    jnz .done
.invalid_info:
.load_error:
    mov rax, EFI_LOAD_ERROR
    jmp .maybe_free_with_status
.unsupported:
    mov rax, EFI_UNSUPPORTED
    jmp .done

.free_with_status:
.maybe_free_with_status:
    mov [rbp - 64], rax
    mov rcx, [rbp - 40]
    test rcx, rcx
    jz .return_saved
    mov rax, [rbp - 56]
    mov rax, [rax + BS_FREE_POOL]
    call rax
    mov rcx, [rbp - 64]
    test rcx, rcx
    jnz .return_saved
    mov [rbp - 64], rax             ; surface cleanup failure after success
.return_saved:
    mov rax, [rbp - 64]
.done:
    mov rsp, rbp
    pop rbp
    ret

; -----------------------------------------------------------------------------
; uefi_file_read_exact
; RCX = open file, RDX = destination, R8 = exact byte count
; RAX = EFI_STATUS.  Short successful transfers are retried; zero progress
; before the expected end is treated as truncation.
; -----------------------------------------------------------------------------
uefi_file_read_exact:
    push rbp
    mov rbp, rsp
    sub rsp, 80                     ; bottom 32 bytes are firmware home space

    mov [rbp - 8], rcx
    mov [rbp - 16], rdx
    mov [rbp - 24], r8
    test rcx, rcx
    jz .bad
    test rdx, rdx
    jz .bad

.next:
    mov rax, [rbp - 24]
    test rax, rax
    jz .success
    mov [rbp - 32], rax

    mov rcx, [rbp - 8]
    lea rdx, [rbp - 32]
    mov r8, [rbp - 16]
    mov rax, [rcx + FILE_READ]
    call rax
    test rax, rax
    jnz .done

    mov rax, [rbp - 32]
    test rax, rax
    jz .eof
    cmp rax, [rbp - 24]
    ja .bad
    add [rbp - 16], rax
    jc .bad
    sub [rbp - 24], rax
    jmp .next

.success:
    xor eax, eax
    jmp .done
.eof:
    mov rax, EFI_END_OF_FILE
    jmp .done
.bad:
    mov rax, EFI_COMPROMISED_DATA
.done:
    mov rsp, rbp
    pop rbp
    ret

; -----------------------------------------------------------------------------
; uefi_load_kernel
; RCX = SystemTable, RDX = root file handle, R8 = UTF-16 filename
; RAX = EFI_STATUS.  Results are published only after close and full checksum.
; -----------------------------------------------------------------------------
uefi_load_kernel:
    push rbp
    mov rbp, rsp
    sub rsp, 160                    ; bottom 32 bytes are firmware home space

    mov [rbp - 8], rcx
    mov [rbp - 16], rdx
    mov [rbp - 24], r8
    mov qword [rbp - 32], 0         ; file handle
    mov qword [rbp - 40], 0         ; file size
    mov qword [rbp - 48], 0         ; allocation address
    mov qword [rbp - 56], 0         ; page count
    mov qword [rbp - 64], 0         ; memory footprint
    mov qword [rbp - 72], 0         ; validated entry
    mov qword [rbp - 80], 0         ; saved status
    mov qword [rbp - 88], 0         ; allocation-owned flag
    mov qword [rbp - 120], 0        ; validated executable-prefix size
    mov [rbp - 96], rdi
    mov [rbp - 104], rsi

    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES]
    test rax, rax
    jz .unsupported
    mov [rbp - 112], rax

    mov rcx, [rbp - 16]
    lea rdx, [rbp - 32]
    mov r8, [rbp - 24]
    mov r9, FILE_MODE_READ
    mov qword [rsp + 32], 0
    mov rax, [rcx + FILE_OPEN]
    call rax
    test rax, rax
    jnz .fail

    mov rcx, [rbp - 8]
    mov rdx, [rbp - 32]
    lea r8, [rbp - 40]
    call uefi_file_get_size
    test rax, rax
    jnz .fail

    mov rax, [rbp - 40]
    cmp rax, ULF_HEADER_SIZE
    jb .load_error
    cmp rax, ULF_MAX_IMAGE_BYTES
    ja .load_error
    test rax, 7
    jnz .load_error

    mov rcx, [rbp - 32]
    xor edx, edx
    mov rax, [rcx + FILE_SET_POSITION]
    call rax
    test rax, rax
    jnz .fail

    mov rcx, [rbp - 32]
    lea rdx, [rel uefi_ulf_header_scratch]
    mov r8d, ULF_HEADER_SIZE
    call uefi_file_read_exact
    test rax, rax
    jnz .fail

    lea rdi, [rel uefi_ulf_header_scratch]
    mov esi, ULF_HEADER_SIZE
    mov rdx, [rbp - 40]
    mov ecx, KERNEL_LOAD
    call uefi_ulf_validate_header
    jc .load_error
    mov [rbp - 64], rax
    mov [rbp - 72], r8
    mov eax, [rel uefi_ulf_header_scratch + ULF_EXEC_SIZE_OFF]
    mov [rbp - 120], rax

    mov rax, [rbp - 64]            ; pages cover the complete memory footprint
    add rax, 4095
    jc .load_error
    shr rax, 12
    test rax, rax
    jz .load_error
    mov [rbp - 56], rax
    mov eax, 0xFFFFFFFF
    mov [rbp - 48], rax             ; highest acceptable backing address

    ; The flat image remains linked at virtual KERNEL_LOAD, but OVMF is not
    ; required to expose that entire physical span as conventional memory.
    ; Acquire any contiguous firmware-owned backing below 4 GiB; the owned
    ; transition CR3 maps it at the linked virtual addresses.
    mov ecx, EFI_ALLOCATE_MAX_ADDRESS
    mov edx, EFI_LOADER_DATA
    mov r8, [rbp - 56]
    lea r9, [rbp - 48]
    mov rax, [rbp - 112]
    mov rax, [rax + BS_ALLOCATE_PAGES]
    call rax
    test rax, rax
    jnz .allocation_failed
    mov qword [rbp - 88], 1
    mov rax, [rbp - 48]
    test rax, rax
    jz .load_error
    test rax, 0xFFF
    jnz .load_error
    mov rcx, [rbp - 56]
    shl rcx, 12
    add rax, rcx
    jc .load_error
    mov rdx, 0x0000000100000000
    cmp rax, rdx
    ja .load_error

    cld
    mov rdi, [rbp - 48]
    mov rcx, [rbp - 56]
    shl rcx, 9                     ; 512 qwords per 4 KiB page
    xor eax, eax
    rep stosq

    mov rcx, [rbp - 32]
    xor edx, edx
    mov rax, [rcx + FILE_SET_POSITION]
    call rax
    test rax, rax
    jnz .fail

    mov rcx, [rbp - 32]
    mov rdx, [rbp - 48]
    mov r8, [rbp - 40]
    call uefi_file_read_exact
    test rax, rax
    jnz .fail

    mov rdi, [rbp - 48]
    mov rsi, [rbp - 40]
    mov edx, KERNEL_LOAD
    call uefi_ulf_validate_image
    jc .load_error
    cmp rax, [rbp - 64]
    jne .load_error
    cmp r8, [rbp - 72]
    jne .load_error
    mov eax, [rdi + ULF_EXEC_SIZE_OFF]
    cmp rax, [rbp - 120]
    jne .load_error

    mov rcx, [rbp - 32]
    mov rax, [rcx + FILE_CLOSE]
    call rax
    mov qword [rbp - 32], 0
    test rax, rax
    jnz .fail

    mov rax, [rbp - 48]
    mov [rel uefi_kernel_addr], rax
    mov rax, [rbp - 40]
    mov [rel uefi_kernel_size], rax
    mov rax, [rbp - 56]
    mov [rel uefi_kernel_pages], rax
    mov rax, [rbp - 64]
    mov [rel uefi_kernel_memory_size], rax
    mov rax, [rbp - 120]
    mov [rel uefi_kernel_exec_size], rax
    mov rax, [rbp - 72]
    mov [rel uefi_kernel_entry], rax
    xor eax, eax
    jmp .return

.unsupported:
    mov rax, EFI_UNSUPPORTED
    jmp .fail
.allocation_failed:
    mov qword [rbp - 48], 0         ; input address was not acquired
    jmp .fail
.load_error:
    mov rax, EFI_LOAD_ERROR
.fail:
    mov [rbp - 80], rax
    mov rcx, [rbp - 32]
    test rcx, rcx
    jz .free_pages
    mov rax, [rcx + FILE_CLOSE]
    call rax
    mov qword [rbp - 32], 0
.free_pages:
    cmp qword [rbp - 88], 0
    je .return_saved
    mov rcx, [rbp - 48]
    mov rdx, [rbp - 56]
    mov rax, [rbp - 112]
    mov rax, [rax + BS_FREE_PAGES]
    call rax
.return_saved:
    mov rax, [rbp - 80]
.return:
    mov rdi, [rbp - 96]
    mov rsi, [rbp - 104]
    mov rsp, rbp
    pop rbp
    ret

; -----------------------------------------------------------------------------
; uefi_load_initrd
; RCX = SystemTable, RDX = root file handle, R8 = UTF-16 filename
; RAX = EFI_STATUS.  EFI_NOT_FOUND is intentionally preserved for the caller.
; -----------------------------------------------------------------------------
uefi_load_initrd:
    push rbp
    mov rbp, rsp
    sub rsp, 160

    mov [rbp - 8], rcx
    mov [rbp - 16], rdx
    mov [rbp - 24], r8
    mov qword [rbp - 32], 0         ; file handle
    mov qword [rbp - 40], 0         ; file size
    mov qword [rbp - 48], 0         ; allocation address
    mov qword [rbp - 56], 0         ; page count
    mov qword [rbp - 64], 0         ; saved status
    mov qword [rbp - 72], 0         ; allocation-owned flag
    mov [rbp - 80], rdi

    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES]
    test rax, rax
    jz .unsupported
    mov [rbp - 88], rax

    mov rcx, [rbp - 16]
    lea rdx, [rbp - 32]
    mov r8, [rbp - 24]
    mov r9, FILE_MODE_READ
    mov qword [rsp + 32], 0
    mov rax, [rcx + FILE_OPEN]
    call rax
    test rax, rax
    jnz .fail

    mov rcx, [rbp - 8]
    mov rdx, [rbp - 32]
    lea r8, [rbp - 40]
    call uefi_file_get_size
    test rax, rax
    jnz .fail

    mov rax, [rbp - 40]
    test rax, rax
    jz .load_error
    cmp rax, ULF_MAX_INITRD_BYTES
    ja .load_error
    add rax, 4095
    jc .load_error
    shr rax, 12
    test rax, rax
    jz .load_error
    mov [rbp - 56], rax
    mov eax, 0xFFFFFFFF
    mov [rbp - 48], rax             ; highest address accepted by bootstrap map

    mov ecx, EFI_ALLOCATE_MAX_ADDRESS
    mov edx, EFI_LOADER_DATA
    mov r8, [rbp - 56]
    lea r9, [rbp - 48]
    mov rax, [rbp - 88]
    mov rax, [rax + BS_ALLOCATE_PAGES]
    call rax
    test rax, rax
    jnz .allocation_failed
    mov qword [rbp - 72], 1

    mov rax, [rbp - 48]
    test rax, rax
    jz .load_error
    test rax, 0xFFF
    jnz .load_error
    mov rcx, [rbp - 56]
    shl rcx, 12
    add rax, rcx
    jc .load_error
    mov rdx, 0x0000000100000000
    cmp rax, rdx
    ja .load_error

    cld
    mov rdi, [rbp - 48]
    mov rcx, [rbp - 56]
    shl rcx, 9
    xor eax, eax
    rep stosq

    mov rcx, [rbp - 32]
    xor edx, edx
    mov rax, [rcx + FILE_SET_POSITION]
    call rax
    test rax, rax
    jnz .fail

    mov rcx, [rbp - 32]
    mov rdx, [rbp - 48]
    mov r8, [rbp - 40]
    call uefi_file_read_exact
    test rax, rax
    jnz .fail

    mov rcx, [rbp - 32]
    mov rax, [rcx + FILE_CLOSE]
    call rax
    mov qword [rbp - 32], 0
    test rax, rax
    jnz .fail

    mov rax, [rbp - 48]
    mov [rel uefi_initrd_addr], rax
    mov rax, [rbp - 40]
    mov [rel uefi_initrd_size], rax
    mov rax, [rbp - 56]
    mov [rel uefi_initrd_pages], rax
    xor eax, eax
    jmp .return

.unsupported:
    mov rax, EFI_UNSUPPORTED
    jmp .fail
.allocation_failed:
    mov qword [rbp - 48], 0
    jmp .fail
.load_error:
    mov rax, EFI_LOAD_ERROR
.fail:
    mov [rbp - 64], rax
    mov rcx, [rbp - 32]
    test rcx, rcx
    jz .free_pages
    mov rax, [rcx + FILE_CLOSE]
    call rax
    mov qword [rbp - 32], 0
.free_pages:
    cmp qword [rbp - 72], 0
    je .return_saved
    mov rcx, [rbp - 48]
    mov rdx, [rbp - 56]
    mov rax, [rbp - 88]
    mov rax, [rax + BS_FREE_PAGES]
    call rax
.return_saved:
    mov rax, [rbp - 64]
.return:
    mov rdi, [rbp - 80]
    mov rsp, rbp
    pop rbp
    ret

; -----------------------------------------------------------------------------
; uefi_release_payloads
; RCX = SystemTable.  Frees successfully published payload allocations during
; a pre-ExitBootServices failure.  Returns the first FreePages status.
; -----------------------------------------------------------------------------
uefi_release_payloads:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov [rbp - 8], rcx
    mov qword [rbp - 16], 0
    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES]
    test rax, rax
    jz .unsupported
    mov [rbp - 24], rax

    mov rcx, [rel uefi_initrd_addr]
    mov rdx, [rel uefi_initrd_pages]
    test rcx, rcx
    jz .free_kernel
    test rdx, rdx
    jz .free_kernel
    mov rax, [rbp - 24]
    mov rax, [rax + BS_FREE_PAGES]
    call rax
    test rax, rax
    jz .clear_initrd
    mov [rbp - 16], rax
.clear_initrd:
    mov qword [rel uefi_initrd_addr], 0
    mov qword [rel uefi_initrd_size], 0
    mov qword [rel uefi_initrd_pages], 0

.free_kernel:
    mov rcx, [rel uefi_kernel_addr]
    mov rdx, [rel uefi_kernel_pages]
    test rcx, rcx
    jz .done
    test rdx, rdx
    jz .done
    mov rax, [rbp - 24]
    mov rax, [rax + BS_FREE_PAGES]
    call rax
    test rax, rax
    jz .clear_kernel
    cmp qword [rbp - 16], 0
    jne .clear_kernel
    mov [rbp - 16], rax
.clear_kernel:
    mov qword [rel uefi_kernel_addr], 0
    mov qword [rel uefi_kernel_size], 0
    mov qword [rel uefi_kernel_pages], 0
    mov qword [rel uefi_kernel_memory_size], 0
    mov qword [rel uefi_kernel_exec_size], 0
    mov qword [rel uefi_kernel_entry], 0
.done:
    mov rax, [rbp - 16]
    jmp .return
.unsupported:
    mov rax, EFI_UNSUPPORTED
.return:
    mov rsp, rbp
    pop rbp
    ret

%endif ; UEFI_FILE_ASM
