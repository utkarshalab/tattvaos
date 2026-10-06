; =============================================================================
; Tattva OS — boot/uefi/memory.asm
; =============================================================================
; Retrieve UEFI memory map using BootServices->GetMemoryMap.
;
; Author:  Utkarsha Labs
; Target:  x86-64, UEFI PE32+
; =============================================================================

%ifndef UEFI_MEMORY_ASM
%define UEFI_MEMORY_ASM

%include "protocol.asm"

[BITS 64]

UEFI_MEMORY_MAP_MIN_DESC_SIZE   equ 40
UEFI_MEMORY_MAP_MAX_DESC_SIZE   equ 4096
UEFI_MEMORY_MAP_MAX_BYTES       equ 1024 * 1024
UEFI_MEMORY_MAP_SLACK_DESCS     equ 16
UEFI_MEMORY_MAP_MAX_ATTEMPTS    equ 4

; =============================================================================
; uefi_get_memory_map — query GetMemoryMap
; Input:  RCX = pointer to System Table
;         RDX = pointer to destination memory map buffer
;         R8  = pointer to MemoryMapSize variable
; Output: RAX = status code (0 on success)
;         RDX = MapKey value
; =============================================================================
uefi_get_memory_map:
    push rbp
    mov rbp, rsp
    sub rsp, 48                     ; shadow space + local storage

    mov r10, rcx                    ; R10 = System Table
    mov r11, rdx                    ; R11 = MemoryMap buffer pointer

    ; Get BootServices: SystemTable->BootServices (offset 96)
    test r10, r10
    jz .unsupported
    mov rdx, [r10 + SYS_TABLE_BOOT_SERVICES]
    test rdx, rdx
    jz .unsupported
    mov [rbp - 8], rdx              ; store BootServices

    ; Call GetMemoryMap(MemoryMapSize, MemoryMap, MapKey, DescriptorSize, DescriptorVersion)
    ; Microsoft x64 Calling Convention:
    ;   RCX = &MemoryMapSize (passed in R8)
    ;   RDX = MemoryMap buffer (passed in R11)
    ;   R8  = &MapKey (local address &uefi_map_key)
    ;   R9  = &DescriptorSize (local address &uefi_desc_size)
    ;   Stack [ESP + 32] = &DescriptorVersion (local address &uefi_desc_version)
    
    mov rcx, r8                     ; RCX = &MemoryMapSize
    mov rdx, r11                    ; RDX = MemoryMap buffer
    lea r8, [rel uefi_map_key]      ; R8 = &MapKey
    lea r9, [rel uefi_desc_size]    ; R9 = &DescriptorSize
    
    lea rax, [rel uefi_desc_version]
    mov [rsp + 32], rax             ; 5th argument at stack offset 32

    mov rax, [rbp - 8]              ; RAX = BootServices
    mov rax, [rax + BS_GET_MEMORY_MAP]
    test rax, rax
    jz .unsupported
    call rax                        ; execute GetMemoryMap

    mov rdx, [rel uefi_map_key]     ; return MapKey value in RDX
    jmp .done

.unsupported:
    mov rax, EFI_UNSUPPORTED
.done:
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; uefi_memory_map_refresh — fill the already-owned raw map buffer
; Input: RCX = SystemTable
; Output: RAX = EFI_STATUS
; No allocation is performed, so this is safe for the bounded stale-key retry.
; =============================================================================
uefi_memory_map_refresh:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov [rbp - 8], rcx
    mov rax, [rel uefi_mem_map_capacity]
    test rax, rax
    jz .refresh_invalid
    cmp rax, UEFI_MEMORY_MAP_MAX_BYTES
    ja .refresh_invalid
    mov rdx, [rel uefi_mem_map_buf]
    test rdx, rdx
    jz .refresh_invalid

    mov [rel uefi_map_size], rax
    mov rcx, [rbp - 8]
    lea r8, [rel uefi_map_size]
    call uefi_get_memory_map
    test rax, rax
    jnz .refresh_done

    mov rax, [rel uefi_map_size]
    test rax, rax
    jz .refresh_compromised
    cmp rax, [rel uefi_mem_map_capacity]
    ja .refresh_compromised
    mov rcx, [rel uefi_desc_size]
    cmp rcx, UEFI_MEMORY_MAP_MIN_DESC_SIZE
    jb .refresh_compromised
    cmp rcx, UEFI_MEMORY_MAP_MAX_DESC_SIZE
    ja .refresh_compromised
    xor edx, edx
    div rcx
    test rdx, rdx
    jnz .refresh_compromised
    test rax, rax
    jz .refresh_compromised
    xor eax, eax
    jmp .refresh_done

.refresh_invalid:
    mov rax, EFI_LOAD_ERROR
    jmp .refresh_done
.refresh_compromised:
    mov rax, EFI_COMPROMISED_DATA
.refresh_done:
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; uefi_memory_map_acquire — probe, allocate, and fill an owned raw map buffer
; Input: RCX = SystemTable
; Output: RAX = EFI_STATUS
; Allocation is bounded to 1 MiB and retried at most four times. Each
; allocation includes descriptor slack because AllocatePool changes the map.
; =============================================================================
uefi_memory_map_acquire:
    push rbp
    mov rbp, rsp
    sub rsp, 128

    mov [rbp - 8], rbx
    mov [rbp - 16], rsi
    mov [rbp - 24], rdi
    mov rbx, rcx

    cmp qword [rel uefi_mem_map_buf], 0
    jne .acquire_load_error
    cmp qword [rel uefi_mem_map_capacity], 0
    jne .acquire_load_error
    test rbx, rbx
    jz .acquire_unsupported
    mov rsi, [rbx + SYS_TABLE_BOOT_SERVICES]
    test rsi, rsi
    jz .acquire_unsupported
    mov rax, [rsi + BS_ALLOCATE_POOL]
    test rax, rax
    jz .acquire_unsupported
    mov rax, [rsi + BS_FREE_POOL]
    test rax, rax
    jz .acquire_unsupported

    mov edi, UEFI_MEMORY_MAP_MAX_ATTEMPTS
.probe:
    mov qword [rel uefi_map_size], 0
    mov rcx, rbx
    xor edx, edx
    lea r8, [rel uefi_map_size]
    call uefi_get_memory_map
    mov r10, EFI_BUFFER_TOO_SMALL
    cmp rax, r10
    jne .acquire_return_status

    mov rcx, [rel uefi_desc_size]
    cmp rcx, UEFI_MEMORY_MAP_MIN_DESC_SIZE
    jb .acquire_compromised
    cmp rcx, UEFI_MEMORY_MAP_MAX_DESC_SIZE
    ja .acquire_compromised
    mov rax, [rel uefi_map_size]
    test rax, rax
    jz .acquire_compromised
    mov rdx, rcx
    shl rdx, 4                     ; room for 16 additional descriptors
    add rax, rdx
    jc .acquire_compromised
    add rax, 4095
    jc .acquire_compromised
    and rax, -4096
    test rax, rax
    jz .acquire_compromised
    cmp rax, UEFI_MEMORY_MAP_MAX_BYTES
    ja .acquire_compromised
    mov [rel uefi_mem_map_capacity], rax
    mov qword [rel uefi_mem_map_buf], 0

    mov ecx, EFI_LOADER_DATA
    mov rdx, rax
    lea r8, [rel uefi_mem_map_buf]
    mov rax, [rsi + BS_ALLOCATE_POOL]
    call rax
    test rax, rax
    jnz .allocation_failed
    cmp qword [rel uefi_mem_map_buf], 0
    je .allocated_null

    mov rcx, rbx
    call uefi_memory_map_refresh
    test rax, rax
    jz .acquire_success
    mov [rbp - 32], rax

    mov rcx, [rel uefi_mem_map_buf]
    mov rax, [rsi + BS_FREE_POOL]
    call rax
    mov qword [rel uefi_mem_map_buf], 0
    mov qword [rel uefi_mem_map_capacity], 0
    mov rax, [rbp - 32]
    mov r10, EFI_BUFFER_TOO_SMALL
    cmp rax, r10
    jne .acquire_done
    dec edi
    jnz .probe
    jmp .acquire_done

.allocated_null:
    mov qword [rel uefi_mem_map_capacity], 0
    mov rax, EFI_COMPROMISED_DATA
    jmp .acquire_done
.allocation_failed:
    mov qword [rel uefi_mem_map_buf], 0
    mov qword [rel uefi_mem_map_capacity], 0
    jmp .acquire_done
.acquire_compromised:
    mov rax, EFI_COMPROMISED_DATA
    jmp .acquire_done
.acquire_load_error:
    mov rax, EFI_LOAD_ERROR
    jmp .acquire_done
.acquire_unsupported:
    mov rax, EFI_UNSUPPORTED
    jmp .acquire_done
.acquire_return_status:
    ; Preserve the firmware's precise probe failure.
.acquire_done:
    mov qword [rel uefi_map_size], 0
    jmp .acquire_return
.acquire_success:
    xor eax, eax
.acquire_return:
    mov rdi, [rbp - 24]
    mov rsi, [rbp - 16]
    mov rbx, [rbp - 8]
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; uefi_memory_map_release — free the raw map on a pre-EBS failure
; Input: RCX = SystemTable
; Output: RAX = EFI_STATUS
; =============================================================================
uefi_memory_map_release:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov qword [rbp - 8], 0
    mov rdx, [rel uefi_mem_map_buf]
    test rdx, rdx
    jz .release_clear
    test rcx, rcx
    jz .release_unsupported
    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES]
    test rax, rax
    jz .release_unsupported
    mov rax, [rax + BS_FREE_POOL]
    test rax, rax
    jz .release_unsupported
    mov rcx, rdx
    call rax
    mov [rbp - 8], rax
    jmp .release_clear

.release_unsupported:
    mov rax, EFI_UNSUPPORTED
    mov [rbp - 8], rax
.release_clear:
    mov qword [rel uefi_mem_map_buf], 0
    mov qword [rel uefi_mem_map_capacity], 0
    mov qword [rel uefi_map_size], 0
    mov qword [rel uefi_map_key], 0
    mov qword [rel uefi_desc_size], 0
    mov dword [rel uefi_desc_version], 0
    mov rax, [rbp - 8]
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; Data variables to store memory map parameters
; =============================================================================
section .data
align 8
uefi_mem_map_buf:    dq 0
uefi_mem_map_capacity:dq 0
uefi_map_size:       dq 0
uefi_map_key:       dq 0
uefi_desc_size:     dq 0
uefi_desc_version:  dd 0

%endif ; UEFI_MEMORY_ASM
