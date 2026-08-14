; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/iso9660.asm
; =============================================================================
; ISO 9660 / ECMA-119 Optical & Cloud-Init Image Driver.
;
; Implements:
;   - Volume descriptor scan from sector 16 (`iso9660_mount`)
;   - Directory record walking (`iso9660_next_record`)
;   - Name matching with version-suffix handling (`iso9660_match_name`)
;   - Extent reads (`iso9660_read_file`)
;   - Joliet escape-sequence detection (`iso9660_is_joliet`)
;
; ISO 9660 stores every multi-byte number TWICE — once little-endian, once
; big-endian, back to back. The "both-endian" fields are 8 or 4 bytes wide and
; only the first half is useful on x86. Reading the full width as a single
; value yields nonsense, which is the classic first bug in an ISO driver.
;
; The volume descriptor set begins at sector 16 (byte 32768) and is a list
; terminated by a type-255 descriptor. The Primary Volume Descriptor is type 1
; and carries "CD001" as its identifier.
;
; Filenames are upper-case and carry a ";1" version suffix that must be
; stripped before comparison. Joliet extensions store UCS-2 names in a
; Supplementary Volume Descriptor instead, identified by an escape sequence.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define ISO9660_SECTOR_SIZE         2048
%define ISO9660_VD_START_SECTOR     16          ; Descriptor set begins here
%define ISO9660_MAX_VD_SCAN         32          ; Bound the descriptor walk

; Volume descriptor types.
%define ISO9660_VD_BOOT             0
%define ISO9660_VD_PRIMARY          1
%define ISO9660_VD_SUPPLEMENTARY    2           ; Joliet lives here
%define ISO9660_VD_PARTITION        3
%define ISO9660_VD_TERMINATOR       255

; Directory record flag bits.
%define ISO9660_FLAG_HIDDEN         0x01
%define ISO9660_FLAG_DIRECTORY      0x02
%define ISO9660_FLAG_ASSOCIATED     0x04
%define ISO9660_FLAG_MULTI_EXTENT   0x80

struc iso9660_pvd_t
    .type:              resb 1      ; ISO9660_VD_*
    .id:                resb 5      ; "CD001"
    .version:           resb 1      ; 1
    .reserved1:         resb 1
    .system_id:         resb 32
    .volume_id:         resb 32
    .reserved2:         resb 8
    .volume_space_size: resd 2      ; Both-endian: LE first, BE second
    .escape_seq:        resb 32     ; Joliet escape sequence in an SVD
    .volume_set_size:   resw 2      ; Both-endian
    .volume_seq_num:    resw 2      ; Both-endian
    .logical_block_sz:  resw 2      ; Both-endian; 2048
    .path_table_size:   resd 2      ; Both-endian
    .path_table_lba:    resd 1      ; Little-endian only
endstruc

; A directory record. The name is variable length and follows this header.
struc iso9660_dirrec_t
    .length:            resb 1      ; Total record length; 0 ends the sector
    .ext_attr_len:      resb 1
    .extent_lba:        resd 2      ; Both-endian extent start
    .data_len:          resd 2      ; Both-endian extent length
    .datetime:          resb 7
    .flags:             resb 1      ; ISO9660_FLAG_*
    .unit_size:         resb 1
    .gap_size:          resb 1
    .vol_seq_num:       resw 2      ; Both-endian
    .name_len:          resb 1      ; Length of the name that follows
endstruc

section .data
align 64

global iso9660_root_lba
iso9660_root_lba:       dd 0
iso9660_root_size:      dd 0
iso9660_block_size:     dd ISO9660_SECTOR_SIZE
iso9660_joliet:         dd 0
iso9660_mounted:        dd 0
iso9660_reads:          dq 0

section .rodata
iso9660_id_string:      db "CD001"

section .text

global iso9660_init
global iso9660_mount
global iso9660_read_file
global iso9660_next_record
global iso9660_match_name
global iso9660_is_joliet

; -----------------------------------------------------------------------------
; iso9660_init
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
iso9660_init:
    mov dword [iso9660_root_lba], 0
    mov dword [iso9660_root_size], 0
    mov dword [iso9660_joliet], 0
    mov dword [iso9660_mounted], 0
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; iso9660_is_joliet
;
; Detects a Joliet Supplementary Volume Descriptor by its escape sequence.
; Joliet uses %/@, %/C or %/E to select a UCS-2 level.
;
; Inputs:
;   RDI = Pointer to a volume descriptor
;
; Returns:
;   EAX = 1 when the descriptor is Joliet, 0 otherwise
; -----------------------------------------------------------------------------
align 32
iso9660_is_joliet:
    cmp byte [rdi + iso9660_pvd_t.type], ISO9660_VD_SUPPLEMENTARY
    jne .ij_no

    cmp byte [rdi + iso9660_pvd_t.escape_seq], '%'
    jne .ij_no
    cmp byte [rdi + iso9660_pvd_t.escape_seq + 1], '/'
    jne .ij_no

    movzx eax, byte [rdi + iso9660_pvd_t.escape_seq + 2]
    cmp eax, '@'
    je .ij_yes
    cmp eax, 'C'
    je .ij_yes
    cmp eax, 'E'
    je .ij_yes

.ij_no:
    xor eax, eax
    ret

.ij_yes:
    mov eax, 1
    ret

; -----------------------------------------------------------------------------
; iso9660_mount
;
; Walks the volume descriptor set and captures the root directory extent.
;
; A Joliet SVD is preferred when present, because its UCS-2 names preserve
; case and length that the primary descriptor's 8.3-style names destroy.
;
; Inputs:
;   RDI = Pointer to a buffer holding the descriptor set, starting at sector 16
;
; Returns:
;   EAX = 0 on success, POSIX_EIO when no valid PVD is found
; -----------------------------------------------------------------------------
align 32
iso9660_mount:
    push rbx
    push r12
    push r13
    push r14

    test rdi, rdi
    jz .im_inval

    mov rbx, rdi                    ; Descriptor cursor
    xor r12d, r12d                  ; Descriptors scanned
    xor r13d, r13d                  ; Non-zero once a PVD was accepted

.im_scan:
    cmp r12d, ISO9660_MAX_VD_SCAN
    jae .im_finish

    ; Every descriptor must carry the "CD001" identifier.
    lea rdi, [rbx + iso9660_pvd_t.id]
    lea rsi, [iso9660_id_string]
    mov rcx, 5
    repe cmpsb
    jne .im_finish                  ; Not a descriptor: the set has ended

    movzx eax, byte [rbx + iso9660_pvd_t.type]

    cmp eax, ISO9660_VD_TERMINATOR
    je .im_finish

    cmp eax, ISO9660_VD_PRIMARY
    je .im_take
    cmp eax, ISO9660_VD_SUPPLEMENTARY
    je .im_maybe_joliet
    jmp .im_next

.im_maybe_joliet:
    mov rdi, rbx
    call iso9660_is_joliet
    test eax, eax
    jz .im_next
    mov dword [iso9660_joliet], 1
    ; Fall through: a Joliet SVD supersedes the primary descriptor.

.im_take:
    ; The root directory record is embedded at offset 156 of the descriptor.
    lea r14, [rbx + 156]

    ; Both-endian: take only the little-endian half.
    mov eax, dword [r14 + iso9660_dirrec_t.extent_lba]
    mov dword [iso9660_root_lba], eax

    mov eax, dword [r14 + iso9660_dirrec_t.data_len]
    mov dword [iso9660_root_size], eax

    ; Logical block size, little-endian half only.
    movzx eax, word [rbx + iso9660_pvd_t.logical_block_sz]
    test eax, eax
    jz .im_next
    mov dword [iso9660_block_size], eax

    mov r13d, 1

.im_next:
    add rbx, ISO9660_SECTOR_SIZE
    inc r12d
    jmp .im_scan

.im_finish:
    test r13d, r13d
    jz .im_badvol

    mov dword [iso9660_mounted], 1
    xor eax, eax
    jmp .im_return

.im_badvol:
    mov eax, POSIX_EIO
    jmp .im_return

.im_inval:
    mov eax, POSIX_EINVAL

.im_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; iso9660_next_record
;
; Steps to the next directory record within a directory extent.
;
; A record length of zero means the remainder of the current 2048-byte sector
; is padding — records never straddle a sector boundary — so the walk must
; jump to the next sector rather than stop.
;
; Inputs:
;   RDI = Pointer to the current record
;   RSI = Byte offset of that record within the extent
;   RDX = Total extent length in bytes
;
; Returns:
;   RAX = Pointer to the next record, or 0 at the end of the extent
;   RDX = Byte offset of the returned record
; -----------------------------------------------------------------------------
align 32
iso9660_next_record:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    movzx eax, byte [rbx + iso9660_dirrec_t.length]
    test eax, eax
    jz .nr_pad

    ; Advance past this record.
    add r12, rax
    add rbx, rax
    jmp .nr_check

.nr_pad:
    ; Zero length: skip to the start of the next sector.
    mov rax, r12
    add rax, ISO9660_SECTOR_SIZE - 1
    and rax, ~(ISO9660_SECTOR_SIZE - 1)
    sub rax, r12                    ; Bytes of padding remaining
    add rbx, rax
    add r12, rax

.nr_check:
    cmp r12, rdx
    jae .nr_end

    ; A zero length at a sector start means no further records.
    movzx eax, byte [rbx + iso9660_dirrec_t.length]
    test eax, eax
    jz .nr_end

    mov rax, rbx
    mov rdx, r12
    pop r12
    pop rbx
    ret

.nr_end:
    xor rax, rax
    mov rdx, r12
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; iso9660_match_name
;
; Compares a directory record's name against a candidate, ignoring the ";1"
; version suffix and a trailing "." that ISO 9660 appends to extension-less
; names.
;
; Inputs:
;   RDI = Pointer to a directory record
;   RSI = Candidate NUL-terminated name
;
; Returns:
;   EAX = 1 on match, 0 otherwise
; -----------------------------------------------------------------------------
align 32
iso9660_match_name:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi

    movzx r13d, byte [rbx + iso9660_dirrec_t.name_len]
    test r13d, r13d
    jz .mn_no

    ; The name begins immediately after the fixed header.
    lea r14, [rbx + iso9660_dirrec_t_size]

    ; Trim a ";N" version suffix.
    mov ecx, r13d
.mn_trim:
    test ecx, ecx
    jz .mn_trimmed
    mov al, byte [r14 + rcx - 1]
    cmp al, ';'
    je .mn_found_semi
    dec ecx
    jmp .mn_trim

.mn_found_semi:
    dec ecx
    mov r13d, ecx

.mn_trimmed:
    ; Trim a single trailing '.' left by an empty extension.
    test r13d, r13d
    jz .mn_compare
    mov al, byte [r14 + r13 - 1]
    cmp al, '.'
    jne .mn_compare
    dec r13d

.mn_compare:
    xor ecx, ecx
.mn_loop:
    cmp ecx, r13d
    jae .mn_end_of_record

    mov al, byte [r12 + rcx]
    test al, al
    jz .mn_no                       ; Candidate ended early

    mov dl, byte [r14 + rcx]

    ; ISO 9660 names are stored upper-case; fold the candidate to match.
    cmp al, 'a'
    jb .mn_cmp
    cmp al, 'z'
    ja .mn_cmp
    sub al, 32

.mn_cmp:
    cmp al, dl
    jne .mn_no

    inc ecx
    jmp .mn_loop

.mn_end_of_record:
    ; Both must end together.
    cmp byte [r12 + rcx], 0
    jne .mn_no

    mov eax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.mn_no:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; iso9660_read_file
;
; Copies a file extent out of a mounted image.
;
; Inputs:
;   RDI = Pointer to the image base
;   RSI = Pointer to the file's directory record
;   RDX = Destination buffer
;   ECX = Destination capacity in bytes
;
; Returns:
;   RAX = Bytes copied, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
iso9660_read_file:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Image base
    mov r12, rsi                    ; Directory record
    mov r13, rdx                    ; Destination
    mov r14d, ecx                   ; Capacity

    test rbx, rbx
    jz .rf_inval
    test r12, r12
    jz .rf_inval
    test r13, r13
    jz .rf_inval
    cmp dword [iso9660_mounted], 0
    je .rf_inval

    ; Multi-extent files need the continuation records chained; refuse rather
    ; than silently return only the first piece.
    test byte [r12 + iso9660_dirrec_t.flags], ISO9660_FLAG_MULTI_EXTENT
    jnz .rf_unsupported

    ; Little-endian halves only.
    mov eax, dword [r12 + iso9660_dirrec_t.extent_lba]
    mov ecx, dword [iso9660_block_size]
    imul rax, rcx                   ; Extent byte offset
    add rax, rbx                    ; Absolute source address

    mov ecx, dword [r12 + iso9660_dirrec_t.data_len]
    cmp ecx, r14d
    jbe .rf_copy
    mov ecx, r14d                   ; Clamp to the caller's buffer

.rf_copy:
    mov rdi, r13
    mov rsi, rax
    mov r14d, ecx                   ; Remember the count for the return
    rep movsb

    inc qword [iso9660_reads]
    mov rax, r14
    jmp .rf_return

.rf_unsupported:
    mov rax, POSIX_EINVAL
    jmp .rf_return

.rf_inval:
    mov rax, POSIX_EINVAL

.rf_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
