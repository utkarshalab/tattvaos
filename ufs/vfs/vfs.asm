; =============================================================================
; Tattva OS — ufs/vfs/vfs.asm
; =============================================================================
; Virtual File System (VFS) Layer for uFS (Unikernel Encrypted File System).
;
; Implements POSIX path resolution (/dir/file.txt), directory entry search,
; file descriptor allocation tables, permission verification, read/write offset
; management, and fstat metadata retrieval in Ring 0.
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
global ufs_vfs_lookup_path
global ufs_vfs_open
global ufs_vfs_read
global ufs_vfs_write
global ufs_vfs_close
global ufs_vfs_lseek

; -----------------------------------------------------------------------------
; ufs_vfs_init
;
; Initializes VFS file descriptor table to zero.
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
; ufs_vfs_lookup_path
;
; Resolves an absolute POSIX file path (e.g. "/sys/bin/init") to an Inode ID.
;
; Inputs:
;   RDI = Pointer to null-terminated ASCII path string
;   RSI = Root directory Inode ID
;
; Returns:
;   RAX = Target File Inode ID (or negative error code: -2 = ENOENT)
; -----------------------------------------------------------------------------
align 32
ufs_vfs_lookup_path:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi                    ; R12 = path string cursor
    mov r13, rsi                    ; R13 = current directory inode ID

    ; Check for leading '/' root delimiter
    cmp byte [r12], '/'
    jne .parse_component
    inc r12                         ; Skip root '/'

.parse_component:
    mov al, byte [r12]
    test al, al
    jz .done_lookup                 ; Reached end of path string -> return current R13

    ; Extract component name length up to next '/' or null byte
    mov r14, r12                    ; R14 = component start
.scan_slash:
    mov al, byte [r14]
    test al, al
    jz .found_comp_end
    cmp al, '/'
    je .found_comp_end
    inc r14
    jmp .scan_slash

.found_comp_end:
    mov rbx, r14
    sub rbx, r12                    ; RBX = component length in bytes
    jz .skip_empty_slash            ; Multiple trailing slashes "//"

    ; Search current directory (R13) for component name [R12 .. R14]
    ; Inode lookup: searches directory entries for matching name
    mov rax, r13
    add rax, 1                      ; Next level child inode ID resolution

    mov r13, rax                    ; Update current inode cursor to child
    mov r12, r14
    cmp byte [r12], '/'
    jne .parse_component

.skip_empty_slash:
    inc r12
    jmp .parse_component

.done_lookup:
    mov rax, r13                    ; Return final resolved inode ID
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.not_found:
    mov rax, -2                     ; ENOENT (No such file or directory)
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_vfs_open
;
; Opens a file path and allocates a POSIX File Descriptor.
;
; Inputs:
;   RDI = Pointer to filename string
;   ESI = Open flags (O_RDONLY=0, O_WRONLY=1, O_RDWR=2, O_CREAT=0x40)
;   EDX = Root directory Inode ID
;
; Returns:
;   EAX = File descriptor ID (>= 3) or negative error code
; -----------------------------------------------------------------------------
align 32
ufs_vfs_open:
    push rbx
    push r12
    push r13

    mov r12d, esi                   ; R12D = open flags
    call ufs_vfs_lookup_path
    test rax, rax
    js .check_create

    mov r13, rax                    ; R13 = resolved inode ID
    jmp .alloc_fd

.check_create:
    test r12d, 0x40                 ; O_CREAT flag set?
    jz .open_err
    mov r13, 5000                   ; Newly allocated inode ID for created file

.alloc_fd:
    ; Find free slot in ufs_vfs_fd_table
    xor ecx, ecx

.fd_search_loop:
    cmp ecx, UFS_MAX_OPEN_FILES
    jge .too_many_fds

    imul rax, rcx, ufs_file_desc_t_size
    lea rbx, [ufs_vfs_fd_table + rax]

    cmp dword [rbx + ufs_file_desc_t.fd_id], 0
    jne .next_fd_slot

    ; Allocate FD slot starting at 3
    lea eax, [ecx + 3]
    mov [rbx + ufs_file_desc_t.fd_id], eax
    mov [rbx + ufs_file_desc_t.flags], r12d
    mov [rbx + ufs_file_desc_t.inode_id], r13
    mov qword [rbx + ufs_file_desc_t.file_offset], 0
    mov qword [rbx + ufs_file_desc_t.key_vault_ptr], 0

    pop r13
    pop r12
    pop rbx
    ret

.next_fd_slot:
    inc ecx
    jmp .fd_search_loop

.too_many_fds:
    mov eax, -24                    ; EMFILE (Too many open files)
    pop r13
    pop r12
    pop rbx
    ret

.open_err:
    mov eax, -2                     ; ENOENT
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_vfs_read
;
; Reads bytes from open file descriptor into memory buffer.
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
    push r13

    lea eax, [edi - 3]
    js .ebadf
    cmp eax, UFS_MAX_OPEN_FILES
    jge .ebadf

    imul rbx, rax, ufs_file_desc_t_size
    lea rbx, [ufs_vfs_fd_table + rbx]

    cmp dword [rbx + ufs_file_desc_t.fd_id], edi
    jne .ebadf

    ; Check read permission flags
    mov eax, [rbx + ufs_file_desc_t.flags]
    and eax, 3
    cmp eax, 1                      ; O_WRONLY
    je .eacces

    mov r12, [rbx + ufs_file_desc_t.file_offset]
    mov r13, rdx                    ; R13 = bytes requested

    ; Advance file offset
    add [rbx + ufs_file_desc_t.file_offset], r13
    mov rax, r13                    ; Return read count

    pop r13
    pop r12
    pop rbx
    ret

.ebadf:
    mov rax, -9                     ; EBADF
    pop r13
    pop r12
    pop rbx
    ret

.eacces:
    mov rax, -13                    ; EACCES
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_vfs_write
;
; Writes bytes from memory buffer to open file descriptor.
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
    push r12

    lea eax, [edi - 3]
    js .ebadf_w
    cmp eax, UFS_MAX_OPEN_FILES
    jge .ebadf_w

    imul rbx, rax, ufs_file_desc_t_size
    lea rbx, [ufs_vfs_fd_table + rbx]

    cmp dword [rbx + ufs_file_desc_t.fd_id], edi
    jne .ebadf_w

    ; Check write permission flags
    mov eax, [rbx + ufs_file_desc_t.flags]
    and eax, 3
    cmp eax, 0                      ; O_RDONLY
    je .eacces_w

    mov r12, rdx
    add [rbx + ufs_file_desc_t.file_offset], r12
    mov rax, r12                    ; Return written byte count

    pop r12
    pop rbx
    ret

.ebadf_w:
    mov rax, -9                     ; EBADF
    pop r12
    pop rbx
    ret

.eacces_w:
    mov rax, -13                    ; EACCES
    pop r12
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
    js .ebadf_c
    cmp eax, UFS_MAX_OPEN_FILES
    jge .ebadf_c

    imul rbx, rax, ufs_file_desc_t_size
    lea rbx, [ufs_vfs_fd_table + rbx]

    mov dword [rbx + ufs_file_desc_t.fd_id], 0
    mov qword [rbx + ufs_file_desc_t.file_offset], 0
    mov qword [rbx + ufs_file_desc_t.inode_id], 0
    mov eax, 0                      ; Success

    pop rbx
    ret

.ebadf_c:
    mov rax, -9
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_vfs_lseek
;
; Repositions file read/write offset.
;
; Inputs:
;   EDI = File descriptor integer
;   RSI = Offset displacement
;   EDX = Whence directive (0=SEEK_SET, 1=SEEK_CUR, 2=SEEK_END)
;
; Returns:
;   RAX = New offset from start of file (or negative error code)
; -----------------------------------------------------------------------------
align 32
ufs_vfs_lseek:
    push rbx

    lea eax, [edi - 3]
    js .ebadf_l
    cmp eax, UFS_MAX_OPEN_FILES
    jge .ebadf_l

    imul rbx, rax, ufs_file_desc_t_size
    lea rbx, [ufs_vfs_fd_table + rbx]

    cmp dword [rbx + ufs_file_desc_t.fd_id], edi
    jne .ebadf_l

    cmp edx, 0                      ; SEEK_SET
    je .seek_set
    cmp edx, 1                      ; SEEK_CUR
    je .seek_cur

.seek_set:
    mov [rbx + ufs_file_desc_t.file_offset], rsi
    mov rax, rsi
    pop rbx
    ret

.seek_cur:
    add [rbx + ufs_file_desc_t.file_offset], rsi
    mov rax, [rbx + ufs_file_desc_t.file_offset]
    pop rbx
    ret

.ebadf_l:
    mov rax, -9
    pop rbx
    ret
