; Native userspace harness for the firmware-independent ULF v2 validator.
; Exit status 0 means every metadata and full-image trust-boundary case passed.

[BITS 64]
default rel

%include "boot/uefi/ulf.asm"

TEST_FILE_SIZE equ 4096
TEST_MEMORY_SIZE equ 8192

section .text
global _start
_start:
    ; A complete, checksummed v2 image publishes its exact footprint and entry.
    call reset_fixture
    call validate_header
    jc .fail_1
    cmp rax, TEST_MEMORY_SIZE
    jne .fail_1
    cmp r8, KERNEL_LOAD + ULF_HEADER_SIZE
    jne .fail_1
    call validate_image
    jc .fail_1

    ; The metadata-only pass must never read a truncated scratch header.
    call reset_fixture
    lea rdi, [rel fixture]
    mov esi, ULF_HEADER_SIZE - 1
    mov edx, TEST_FILE_SIZE
    mov ecx, KERNEL_LOAD
    call uefi_ulf_validate_header
    jnc .fail_2

    call reset_fixture
    xor dword [rel fixture + ULF_MAGIC_OFF], 1
    call validate_header
    jnc .fail_3

    call reset_fixture
    mov dword [rel fixture + ULF_VERSION_OFF], ULF_VERSION - 1
    call validate_header
    jnc .fail_4

    call reset_fixture
    mov dword [rel fixture + ULF_IMAGE_SIZE_OFF], TEST_FILE_SIZE - 8
    call validate_header
    jnc .fail_5

    call reset_fixture
    mov dword [rel fixture + ULF_EXEC_SIZE_OFF], ULF_HEADER_SIZE
    call validate_header
    jnc .fail_6

    call reset_fixture
    mov qword [rel fixture + ULF_ENTRY_OFF], KERNEL_LOAD + TEST_FILE_SIZE
    call validate_header
    jnc .fail_7

    call reset_fixture
    mov qword [rel fixture + ULF_MEMORY_SIZE_OFF], TEST_FILE_SIZE - 8
    call validate_header
    jnc .fail_8

    call reset_fixture
    mov qword [rel fixture + ULF_MEMORY_SIZE_OFF], ULF_MAX_MEMORY_BYTES + 8
    call validate_header
    jnc .fail_9

    call reset_fixture
    mov qword [rel fixture + ULF_MEMORY_SIZE_OFF], TEST_MEMORY_SIZE + 1
    call validate_header
    jnc .fail_10

    ; Page alignment is part of AllocateAddress's trusted input contract.
    call reset_fixture
    lea rdi, [rel fixture]
    mov esi, ULF_HEADER_SIZE
    mov edx, TEST_FILE_SIZE
    mov ecx, KERNEL_LOAD + 1
    call uefi_ulf_validate_header
    jnc .fail_11

    ; A page-aligned base whose complete footprint crosses 4 GiB is invalid.
    call reset_fixture
    mov qword [rel fixture + ULF_MEMORY_SIZE_OFF], ULF_MAX_MEMORY_BYTES
    mov eax, 0xFFF00000 + ULF_HEADER_SIZE
    mov [rel fixture + ULF_ENTRY_OFF], rax
    lea rdi, [rel fixture]
    mov esi, ULF_HEADER_SIZE
    mov edx, TEST_FILE_SIZE
    mov rcx, 0x00000000FFF00000
    call uefi_ulf_validate_header
    jnc .fail_12

    ; The full pass covers every initialized byte, not only the header.
    call reset_fixture
    xor byte [rel fixture + 128], 1
    call validate_image
    jnc .fail_13

    ; Reject invalid caller-provided bounds before dereferencing metadata.
    call reset_fixture
    xor edi, edi
    mov esi, ULF_HEADER_SIZE
    mov edx, TEST_FILE_SIZE
    mov ecx, KERNEL_LOAD
    call uefi_ulf_validate_header
    jnc .fail_14

    call reset_fixture
    lea rdi, [rel fixture]
    mov esi, ULF_HEADER_SIZE
    mov edx, ULF_HEADER_SIZE - 8
    mov ecx, KERNEL_LOAD
    call uefi_ulf_validate_header
    jnc .fail_15

    call reset_fixture
    lea rdi, [rel fixture]
    mov esi, ULF_HEADER_SIZE
    mov edx, ULF_MAX_IMAGE_BYTES + 8
    mov ecx, KERNEL_LOAD
    call uefi_ulf_validate_header
    jnc .fail_16

    call reset_fixture
    lea rdi, [rel fixture]
    mov esi, ULF_HEADER_SIZE
    mov edx, TEST_FILE_SIZE + 1
    mov ecx, KERNEL_LOAD
    call uefi_ulf_validate_header
    jnc .fail_17

    ; Exercise each executable-prefix bound independently.
    call reset_fixture
    mov dword [rel fixture + ULF_EXEC_SIZE_OFF], 0
    call validate_header
    jnc .fail_18

    call reset_fixture
    mov dword [rel fixture + ULF_EXEC_SIZE_OFF], TEST_FILE_SIZE * 2
    call validate_header
    jnc .fail_19

    call reset_fixture
    mov dword [rel fixture + ULF_IMAGE_SIZE_OFF], ULF_MAX_EXEC_BYTES + ULF_EXEC_ALIGN
    mov dword [rel fixture + ULF_EXEC_SIZE_OFF], ULF_MAX_EXEC_BYTES + ULF_EXEC_ALIGN
    mov qword [rel fixture + ULF_MEMORY_SIZE_OFF], ULF_MAX_EXEC_BYTES + ULF_EXEC_ALIGN
    lea rdi, [rel fixture]
    mov esi, ULF_HEADER_SIZE
    mov edx, ULF_MAX_EXEC_BYTES + ULF_EXEC_ALIGN
    mov ecx, KERNEL_LOAD
    call uefi_ulf_validate_header
    jnc .fail_20

    call reset_fixture
    mov qword [rel fixture + ULF_ENTRY_OFF], KERNEL_LOAD + ULF_HEADER_SIZE - 1
    call validate_header
    jnc .fail_21

    call reset_fixture
    mov rax, 0x0000000100100028
    mov [rel fixture + ULF_ENTRY_OFF], rax
    call validate_header
    jnc .fail_22

    ; An exclusive footprint end exactly at 4 GiB is still representable by
    ; the current bootstrap mapping contract; crossing it is tested above.
    call reset_fixture
    mov rax, 0x00000000FFFFE000 + ULF_HEADER_SIZE
    mov [rel fixture + ULF_ENTRY_OFF], rax
    lea rdi, [rel fixture]
    mov esi, ULF_HEADER_SIZE
    mov edx, TEST_FILE_SIZE
    mov rcx, 0x00000000FFFFE000
    call uefi_ulf_validate_header
    jc .fail_23
    cmp rax, TEST_MEMORY_SIZE
    jne .fail_23
    mov rdx, 0x00000000FFFFE000 + ULF_HEADER_SIZE
    cmp r8, rdx
    jne .fail_23

    call reset_fixture
    xor qword [rel fixture + ULF_CHECKSUM_OFF], 1
    call validate_image
    jnc .fail_24

    xor edi, edi
    jmp .exit

.fail_1:
    mov edi, 1
    jmp .exit
.fail_2:
    mov edi, 2
    jmp .exit
.fail_3:
    mov edi, 3
    jmp .exit
.fail_4:
    mov edi, 4
    jmp .exit
.fail_5:
    mov edi, 5
    jmp .exit
.fail_6:
    mov edi, 6
    jmp .exit
.fail_7:
    mov edi, 7
    jmp .exit
.fail_8:
    mov edi, 8
    jmp .exit
.fail_9:
    mov edi, 9
    jmp .exit
.fail_10:
    mov edi, 10
    jmp .exit
.fail_11:
    mov edi, 11
    jmp .exit
.fail_12:
    mov edi, 12
    jmp .exit
.fail_13:
    mov edi, 13
    jmp .exit
.fail_14:
    mov edi, 14
    jmp .exit
.fail_15:
    mov edi, 15
    jmp .exit
.fail_16:
    mov edi, 16
    jmp .exit
.fail_17:
    mov edi, 17
    jmp .exit
.fail_18:
    mov edi, 18
    jmp .exit
.fail_19:
    mov edi, 19
    jmp .exit
.fail_20:
    mov edi, 20
    jmp .exit
.fail_21:
    mov edi, 21
    jmp .exit
.fail_22:
    mov edi, 22
    jmp .exit
.fail_23:
    mov edi, 23
    jmp .exit
.fail_24:
    mov edi, 24

.exit:
    mov eax, 60
    syscall

validate_header:
    lea rdi, [rel fixture]
    mov esi, ULF_HEADER_SIZE
    mov edx, TEST_FILE_SIZE
    mov ecx, KERNEL_LOAD
    jmp uefi_ulf_validate_header

validate_image:
    lea rdi, [rel fixture]
    mov esi, TEST_FILE_SIZE
    mov edx, KERNEL_LOAD
    jmp uefi_ulf_validate_image

; Rebuild a deterministic valid image and stamp its additive checksum.
reset_fixture:
    lea rdi, [rel fixture]
    mov ecx, TEST_FILE_SIZE / 8
    xor eax, eax
    cld
    rep stosq

    mov dword [rel fixture + ULF_MAGIC_OFF], ULF_MAGIC
    mov dword [rel fixture + ULF_IMAGE_SIZE_OFF], TEST_FILE_SIZE
    mov qword [rel fixture + ULF_ENTRY_OFF], KERNEL_LOAD + ULF_HEADER_SIZE
    mov dword [rel fixture + ULF_EXEC_SIZE_OFF], TEST_FILE_SIZE
    mov dword [rel fixture + ULF_VERSION_OFF], ULF_VERSION
    mov qword [rel fixture + ULF_MEMORY_SIZE_OFF], TEST_MEMORY_SIZE

    lea rdi, [rel fixture]
    xor eax, eax
    xor edx, edx
.sum:
    cmp edx, ULF_CHECKSUM_OFF
    je .skip_checksum
    add rax, [rdi + rdx]
.skip_checksum:
    add edx, 8
    cmp edx, TEST_FILE_SIZE
    jb .sum
    mov [rel fixture + ULF_CHECKSUM_OFF], rax
    ret

section .bss align=16
fixture: resb TEST_FILE_SIZE
