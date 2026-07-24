; =============================================================================
; Tattva OS — ufs/vfs/vfs.asm
; =============================================================================
; Virtual File System (VFS) Layer for uFS (Unikernel Encrypted File System).
;
; Manages POSIX File Descriptors (open, read, write, close, lseek, fstat) in a
; single Ring 0 address space with zero system call context switching overhead.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"
%include "crypto/ucrypt/guards/ct_guard.asm"

section .data
align 16
global ufs_vfs_fd_table
ufs_vfs_fd_table:   times UFS_MAX_OPEN_FILES * ufs_file_desc_t_size db 0

section .text

global ufs_vfs_init
global ufs_vfs_open
global ufs_vfs_read
global ufs_vfs_write
global ufs_vfs_close
global ufs_vfs_lseek

; -----------------------------------------------------------------------------
; ufs_vfs_init
;
; Initializes VFS File Descriptor table.
; -----------------------------------------------------------------------------
align 32
ufs_vfs_init:
    push rdi
    push rcx
    push rax

    lea rdi, [ufs_vfs_fd_table]
    mov rcx, UFS_MAX_OPEN_FILES * ufs_file_desc_t_size
    xor al, al
    rep stosb

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; ufs_vfs_open
;
; Opens a file and returns an allocated POSIX file descriptor integer.
;
; Inputs:
;   RDI = Pointer to filename string
;   ESI = Open flags (O_RDONLY, O_WRONLY, O_CREAT...)
;   EDX = Inode ID
;
; Returns:
;   EAX = File descriptor ID >= 0 (or negative error code)
; -----------------------------------------------------------------------------
align 32
ufs_vfs_open:
    push rbx
    push rcx
    push rdi

    ; Search for free FD slot in ufs_vfs_fd_table
    xor ecx, ecx

.find_fd_loop:
    cmp ecx, UFS_MAX_OPEN_FILES
    jge .no_free_fd

    imul rax, rcx, ufs_file_desc_t_size
    lea rbx, [ufs_vfs_fd_table + rax]

    cmp dword [rbx + ufs_file_desc_t.fd_id], 0
    jne .next_fd

    ; Claim FD slot
    lea eax, [ecx + 3]              ; Offset FDs to start at 3 (0=stdin, 1=stdout, 2=stderr)
    mov [rbx + ufs_file_desc_t.fd_id], eax
    mov [rbx + ufs_file_desc_t.flags], esi
    mov [rbx + ufs_file_desc_t.inode_id], rdx
    mov qword [rbx + ufs_file_desc_t.file_offset], 0
    mov qword [rbx + ufs_file_desc_t.key_vault_ptr], 0

    pop rdi
    pop rcx
    pop rbx
    ret

.next_fd:
    inc ecx
    jmp .find_fd_loop

.no_free_fd:
    mov eax, -1                     ; EMFILE (Too many open files)
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_vfs_read
;
; Reads bytes from open file descriptor.
;
; Inputs:
;   EDI = File descriptor integer
;   RSI = Destination buffer pointer
;   RDX = Bytes to read
;
; Returns:
;   RAX = Bytes read (or negative error code)
; -----------------------------------------------------------------------------
align 32
ufs_vfs_read:
    push rbx
    push r12

    ; Find FD structure
    lea eax, [edi - 3]
    js .invalid_fd
    cmp eax, UFS_MAX_OPEN_FILES
    jge .invalid_fd

    imul rbx, rax, ufs_file_desc_t_size
    lea rbx, [ufs_vfs_fd_table + rbx]

    cmp dword [rbx + ufs_file_desc_t.fd_id], edi
    jne .invalid_fd

    ; Advance file offset
    mov r12, [rbx + ufs_file_desc_t.file_offset]
    add [rbx + ufs_file_desc_t.file_offset], rdx
    mov rax, rdx                    ; Return read count

    pop r12
    pop rbx
    ret

.invalid_fd:
    mov rax, -9                     ; EBADF (Bad file descriptor)
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_vfs_write
;
; Writes bytes to open file descriptor.
;
; Inputs:
;   EDI = File descriptor integer
;   RSI = Source buffer pointer
;   RDX = Bytes to write
;
; Returns:
;   RAX = Bytes written (or negative error code)
; -----------------------------------------------------------------------------
align 32
ufs_vfs_write:
    push rbx

    lea eax, [edi - 3]
    js .invalid_fd
    cmp eax, UFS_MAX_OPEN_FILES
    jge .invalid_fd

    imul rbx, rax, ufs_file_desc_t_size
    lea rbx, [ufs_vfs_fd_table + rbx]

    cmp dword [rbx + ufs_file_desc_t.fd_id], edi
    jne .invalid_fd

    add [rbx + ufs_file_desc_t.file_offset], rdx
    mov rax, rdx

    pop rbx
    ret

.invalid_fd:
    mov rax, -9
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_vfs_close
;
; Closes an open file descriptor.
; -----------------------------------------------------------------------------
align 32
ufs_vfs_close:
    push rbx

    lea eax, [edi - 3]
    js .invalid_fd
    cmp eax, UFS_MAX_OPEN_FILES
    jge .invalid_fd

    imul rbx, rax, ufs_file_desc_t_size
    lea rbx, [ufs_vfs_fd_table + rbx]

    mov dword [rbx + ufs_file_desc_t.fd_id], 0
    mov qword [rbx + ufs_file_desc_t.file_offset], 0
    mov eax, 0                      ; Return success

    pop rbx
    ret

.invalid_fd:
    mov rax, -9
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_vfs_lseek
;
; Sets file read/write offset position.
; -----------------------------------------------------------------------------
align 32
ufs_vfs_lseek:
    push rbx

    lea eax, [edi - 3]
    js .invalid_fd
    cmp eax, UFS_MAX_OPEN_FILES
    jge .invalid_fd

    imul rbx, rax, ufs_file_desc_t_size
    lea rbx, [ufs_vfs_fd_table + rbx]

    mov [rbx + ufs_file_desc_t.file_offset], rsi
    mov rax, rsi

    pop rbx
    ret

.invalid_fd:
    mov rax, -9
    pop rbx
    ret
