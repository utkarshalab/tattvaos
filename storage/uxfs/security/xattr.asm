%ifndef GUARD_STORAGE_UXFS_SECURITY_XATTR_ASM
%define GUARD_STORAGE_UXFS_SECURITY_XATTR_ASM
; =============================================================================
; Tattva OS — storage/uxfs/security/xattr.asm
; =============================================================================
; Extended Attribute Store (namespaced inode metadata).
;
; Implements:
;   - Attribute block initialisation (`uxfs_xattr_init_block`)
;   - Set, get, remove and enumerate (`uxfs_xattr_set/get/remove/list`)
;   - Namespace parsing and access policy (`uxfs_xattr_parse_ns`,
;     `uxfs_xattr_may_access`)
;
; Extended attributes are the mechanism everything above plain mode bits is
; built on: POSIX ACLs, security labels, capabilities and per-file encryption
; policies are all stored here rather than in the inode, because the inode is
; fixed size and these are not.
;
; The namespace prefix is not decoration — it is the access policy:
;
;   user.*      Unprivileged. Readable and writable by anyone who can read and
;               write the file itself.
;   trusted.*   Privileged. Invisible to unprivileged processes entirely, so a
;               user cannot even learn that an attribute exists.
;   security.*  Owned by the security subsystem (labels, capabilities). Read is
;               generally permitted; write is not.
;   system.*    Owned by the filesystem (ACLs live here). Writable only through
;               the interfaces that understand the contents.
;
; Collapsing these into one flat namespace would let an unprivileged process
; overwrite the ACL that governs it, so the prefix check happens before any
; mutation.
;
; Storage is a single 4KB block per inode holding variable-length records. That
; caps total attribute bytes per file, which is deliberate: unbounded metadata
; on a fixed-size inode is how attribute storage turns into a second allocator.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_XATTR_MAGIC            0x58415454      ; "XATT"
%define UXFS_XATTR_BLOCK_SIZE       UXFS_BLOCK_SIZE
%define UXFS_XATTR_MAX_NAME         255
%define UXFS_XATTR_MAX_VALUE        1024
%define UXFS_XATTR_MAX_ENTRIES      64

; Namespace identifiers.
%define UXFS_XATTR_NS_USER          1
%define UXFS_XATTR_NS_TRUSTED       2
%define UXFS_XATTR_NS_SECURITY      3
%define UXFS_XATTR_NS_SYSTEM        4

; Access intents for uxfs_xattr_may_access.
%define UXFS_XATTR_ACCESS_READ      1
%define UXFS_XATTR_ACCESS_WRITE     2

struc uxfs_xattr_header_t
    .magic:             resd 1      ; UXFS_XATTR_MAGIC
    .count:             resd 1      ; Live entry count
    .used:              resd 1      ; Bytes consumed, including this header
    .reserved:          resd 1
endstruc

; One attribute record. The name follows the header, then the value.
struc uxfs_xattr_entry_t
    .rec_len:           resd 1      ; Total record length, 8-byte aligned
    .name_len:          resb 1      ; Name length, excluding the namespace
    .namespace:         resb 1      ; UXFS_XATTR_NS_*
    .value_len:         resw 1      ; Value length in bytes
endstruc

section .rodata
align 8
uxfs_xattr_ns_user:     db "user.", 0
uxfs_xattr_ns_trusted:  db "trusted.", 0
uxfs_xattr_ns_security: db "security.", 0
uxfs_xattr_ns_system:   db "system.", 0

section .data
align 8
uxfs_xattr_sets:        dq 0
uxfs_xattr_gets:        dq 0
uxfs_xattr_denied:      dq 0

section .text

global uxfs_xattr_init_block
global uxfs_xattr_parse_ns
global uxfs_xattr_may_access
global uxfs_xattr_set
global uxfs_xattr_get
global uxfs_xattr_remove
global uxfs_xattr_list
global uxfs_xattr_find

; -----------------------------------------------------------------------------
; uxfs_xattr_strlen
;
; Inputs:
;   RDI = NUL-terminated string
;
; Returns:
;   RAX = Length, capped at UXFS_XATTR_MAX_NAME
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_strlen:
    xor rax, rax
    test rdi, rdi
    jz .sl_done
.sl_loop:
    cmp rax, UXFS_XATTR_MAX_NAME
    jae .sl_done
    cmp byte [rdi + rax], 0
    je .sl_done
    inc rax
    jmp .sl_loop
.sl_done:
    ret

; -----------------------------------------------------------------------------
; uxfs_xattr_prefix_match
;
; Inputs:
;   RDI = Candidate string
;   RSI = NUL-terminated prefix
;
; Returns:
;   RAX = Prefix length on match, 0 otherwise
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_prefix_match:
    xor rax, rax
.pm_loop:
    mov cl, byte [rsi + rax]
    test cl, cl
    jz .pm_match                    ; Prefix exhausted: it matched
    mov dl, byte [rdi + rax]
    cmp cl, dl
    jne .pm_no
    inc rax
    jmp .pm_loop
.pm_match:
    ret
.pm_no:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; uxfs_xattr_parse_ns
;
; Splits a fully-qualified attribute name into namespace and suffix.
;
; Inputs:
;   RDI = Full name, e.g. "user.mime_type"
;   RSI = Pointer to a dword receiving the namespace id
;
; Returns:
;   RAX = Pointer to the suffix, or 0 when the namespace is unrecognised
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_parse_ns:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    test rbx, rbx
    jz .pn_bad
    test r12, r12
    jz .pn_bad

    mov rdi, rbx
    lea rsi, [uxfs_xattr_ns_user]
    call uxfs_xattr_prefix_match
    test rax, rax
    jnz .pn_user

    mov rdi, rbx
    lea rsi, [uxfs_xattr_ns_trusted]
    call uxfs_xattr_prefix_match
    test rax, rax
    jnz .pn_trusted

    mov rdi, rbx
    lea rsi, [uxfs_xattr_ns_security]
    call uxfs_xattr_prefix_match
    test rax, rax
    jnz .pn_security

    mov rdi, rbx
    lea rsi, [uxfs_xattr_ns_system]
    call uxfs_xattr_prefix_match
    test rax, rax
    jnz .pn_system

.pn_bad:
    ; An unprefixed name is rejected rather than defaulted. Defaulting to
    ; "user." would let a caller reach privileged namespaces by omission.
    xor rax, rax
    pop r12
    pop rbx
    ret

.pn_user:
    mov dword [r12], UXFS_XATTR_NS_USER
    add rax, rbx
    pop r12
    pop rbx
    ret

.pn_trusted:
    mov dword [r12], UXFS_XATTR_NS_TRUSTED
    add rax, rbx
    pop r12
    pop rbx
    ret

.pn_security:
    mov dword [r12], UXFS_XATTR_NS_SECURITY
    add rax, rbx
    pop r12
    pop rbx
    ret

.pn_system:
    mov dword [r12], UXFS_XATTR_NS_SYSTEM
    add rax, rbx
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_xattr_may_access
;
; Applies the namespace access policy.
;
; Inputs:
;   EDI = Namespace id
;   ESI = UXFS_XATTR_ACCESS_READ or _WRITE
;   EDX = Non-zero when the caller is privileged
;
; Returns:
;   EAX = 0 when permitted, POSIX_EACCES otherwise
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_may_access:
    cmp edi, UXFS_XATTR_NS_USER
    je .ma_allow                    ; Governed by file permissions alone

    ; Everything else requires privilege to write.
    cmp edi, UXFS_XATTR_NS_TRUSTED
    je .ma_priv_both
    cmp edi, UXFS_XATTR_NS_SECURITY
    je .ma_priv_write
    cmp edi, UXFS_XATTR_NS_SYSTEM
    je .ma_priv_write

    mov eax, POSIX_EINVAL
    ret

.ma_priv_both:
    ; trusted.* is invisible without privilege, so even reads are refused.
    test edx, edx
    jz .ma_deny
    jmp .ma_allow

.ma_priv_write:
    cmp esi, UXFS_XATTR_ACCESS_WRITE
    jne .ma_allow                   ; Reads are permitted
    test edx, edx
    jz .ma_deny

.ma_allow:
    xor eax, eax
    ret

.ma_deny:
    inc qword [uxfs_xattr_denied]
    mov eax, POSIX_EACCES
    ret

; -----------------------------------------------------------------------------
; uxfs_xattr_init_block
;
; Prepares an empty attribute block.
;
; Inputs:
;   RDI = Pointer to a 4KB block
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on a null argument
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_init_block:
    test rdi, rdi
    jz .ib_inval

    mov dword [rdi + uxfs_xattr_header_t.magic], UXFS_XATTR_MAGIC
    mov dword [rdi + uxfs_xattr_header_t.count], 0
    mov dword [rdi + uxfs_xattr_header_t.used], uxfs_xattr_header_t_size
    mov dword [rdi + uxfs_xattr_header_t.reserved], 0

    xor eax, eax
    ret

.ib_inval:
    mov eax, POSIX_EINVAL
    ret

; -----------------------------------------------------------------------------
; uxfs_xattr_find
;
; Locates an attribute record by namespace and suffix.
;
; Inputs:
;   RDI = Attribute block
;   ESI = Namespace id
;   RDX = Suffix name
;
; Returns:
;   RAX = Record pointer, or 0 when absent
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_find:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Block
    mov r12d, esi                   ; Namespace
    mov r13, rdx                    ; Suffix

    test rbx, rbx
    jz .xf_missing
    cmp dword [rbx + uxfs_xattr_header_t.magic], UXFS_XATTR_MAGIC
    jne .xf_missing

    mov rdi, r13
    call uxfs_xattr_strlen
    mov r14, rax                    ; Suffix length

    mov r15d, dword [rbx + uxfs_xattr_header_t.count]
    lea rdi, [rbx + uxfs_xattr_header_t_size]

.xf_loop:
    test r15d, r15d
    jz .xf_missing

    ; Never step outside the block.
    mov rax, rdi
    sub rax, rbx
    add rax, uxfs_xattr_entry_t_size
    cmp rax, UXFS_XATTR_BLOCK_SIZE
    ja .xf_missing

    mov ecx, dword [rdi + uxfs_xattr_entry_t.rec_len]
    test ecx, ecx
    jz .xf_missing                  ; Zero length would loop forever

    movzx eax, byte [rdi + uxfs_xattr_entry_t.namespace]
    cmp eax, r12d
    jne .xf_next

    movzx eax, byte [rdi + uxfs_xattr_entry_t.name_len]
    cmp rax, r14
    jne .xf_next

    ; Compare the name bytes that follow the record header.
    push rdi
    push rcx
    lea rsi, [rdi + uxfs_xattr_entry_t_size]
    mov rdi, r13
    mov rcx, r14
    repe cmpsb
    pop rcx
    pop rdi
    je .xf_found

.xf_next:
    add rdi, rcx
    dec r15d
    jmp .xf_loop

.xf_found:
    mov rax, rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.xf_missing:
    xor rax, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_xattr_set
;
; Creates or replaces an attribute.
;
; A replacement is implemented as remove-then-append rather than in-place
; overwrite, because the new value may be a different length and shifting the
; tail of a record region is where off-by-one corruption lives.
;
; Inputs:
;   RDI = Attribute block
;   RSI = Fully-qualified name
;   RDX = Value pointer
;   ECX = Value length
;   R8D = Non-zero when the caller is privileged
;
; Returns:
;   EAX = 0 on success
;         POSIX_EACCES on a namespace policy violation
;         POSIX_ENOSPC when the block is full
;         POSIX_EINVAL on a malformed name or oversized value
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_set:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov rbx, rdi                    ; Block
    mov [rsp], rdx                  ; Value
    mov [rsp + 8], rcx              ; Value length
    mov [rsp + 16], r8              ; Privileged

    test rbx, rbx
    jz .xs_inval
    cmp ecx, UXFS_XATTR_MAX_VALUE
    ja .xs_inval

    ; Split the namespace off and enforce its policy before touching anything.
    mov rdi, rsi
    lea rsi, [rsp + 24]
    call uxfs_xattr_parse_ns
    test rax, rax
    jz .xs_inval
    mov r13, rax                    ; Suffix
    mov r12d, dword [rsp + 24]      ; Namespace

    mov edi, r12d
    mov esi, UXFS_XATTR_ACCESS_WRITE
    mov edx, dword [rsp + 16]
    call uxfs_xattr_may_access
    test eax, eax
    jnz .xs_return

    ; Replace by removing any existing record first.
    mov rdi, rbx
    mov esi, r12d
    mov rdx, r13
    call uxfs_xattr_find
    test rax, rax
    jz .xs_append

    mov rdi, rbx
    mov esi, r12d
    mov rdx, r13
    call uxfs_xattr_remove_entry

.xs_append:
    mov rdi, r13
    call uxfs_xattr_strlen
    mov r14, rax                    ; Suffix length
    test r14, r14
    jz .xs_inval

    ; Record length, rounded up to 8 bytes so the next header stays aligned.
    mov r15, uxfs_xattr_entry_t_size
    add r15, r14
    add r15, [rsp + 8]
    add r15, 7
    and r15, ~7

    mov eax, dword [rbx + uxfs_xattr_header_t.used]
    mov ecx, eax
    add ecx, r15d
    cmp ecx, UXFS_XATTR_BLOCK_SIZE
    ja .xs_nospc

    cmp dword [rbx + uxfs_xattr_header_t.count], UXFS_XATTR_MAX_ENTRIES
    jae .xs_nospc

    ; Append at the current end.
    lea rdi, [rbx + rax]

    mov dword [rdi + uxfs_xattr_entry_t.rec_len], r15d
    mov byte [rdi + uxfs_xattr_entry_t.name_len], r14b
    mov byte [rdi + uxfs_xattr_entry_t.namespace], r12b
    mov rcx, [rsp + 8]
    mov word [rdi + uxfs_xattr_entry_t.value_len], cx

    ; Name first; RDI is left pointing exactly at the value destination.
    mov r10, rdi                    ; Preserve the record pointer
    lea rdi, [r10 + uxfs_xattr_entry_t_size]
    mov rsi, r13
    mov rcx, r14
    rep movsb

    ; Value follows immediately, using the position rep movsb left behind.
    mov rcx, [rsp + 8]
    test rcx, rcx
    jz .xs_committed
    mov rsi, [rsp]
    rep movsb

.xs_committed:
    mov eax, dword [rbx + uxfs_xattr_header_t.used]
    add eax, r15d
    mov dword [rbx + uxfs_xattr_header_t.used], eax
    inc dword [rbx + uxfs_xattr_header_t.count]

    inc qword [uxfs_xattr_sets]
    xor eax, eax
    jmp .xs_return

.xs_nospc:
    mov eax, POSIX_ENOSPC
    jmp .xs_return

.xs_inval:
    mov eax, POSIX_EINVAL

.xs_return:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_xattr_remove_entry
;
; Removes a record and closes the gap by shifting everything after it down.
;
; Inputs:
;   RDI = Attribute block
;   ESI = Namespace id
;   RDX = Suffix name
;
; Returns:
;   EAX = 0 on success, POSIX_ENOENT when absent
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_remove_entry:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi

    call uxfs_xattr_find
    test rax, rax
    jz .re_missing

    mov r12, rax                    ; Record to drop
    mov r13d, dword [r12 + uxfs_xattr_entry_t.rec_len]

    ; Bytes living after this record.
    mov eax, dword [rbx + uxfs_xattr_header_t.used]
    lea rcx, [rbx + rax]            ; End of live data
    mov r14, r12
    add r14, r13                    ; Start of the tail
    sub rcx, r14                    ; Tail length

    test rcx, rcx
    jz .re_shrink

    mov rdi, r12
    mov rsi, r14
    rep movsb

.re_shrink:
    mov eax, dword [rbx + uxfs_xattr_header_t.used]
    sub eax, r13d
    mov dword [rbx + uxfs_xattr_header_t.used], eax
    dec dword [rbx + uxfs_xattr_header_t.count]

    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.re_missing:
    mov eax, POSIX_ENOENT
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_xattr_get
;
; Retrieves an attribute value.
;
; Inputs:
;   RDI = Attribute block
;   RSI = Fully-qualified name
;   RDX = Destination buffer, or 0 to query the size only
;   ECX = Destination capacity
;   R8D = Non-zero when the caller is privileged
;
; Returns:
;   RAX = Value length, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_get:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov rbx, rdi
    mov [rsp], rdx                  ; Destination
    mov [rsp + 8], rcx              ; Capacity
    mov [rsp + 16], r8              ; Privileged

    test rbx, rbx
    jz .xg_inval

    mov rdi, rsi
    lea rsi, [rsp + 24]
    call uxfs_xattr_parse_ns
    test rax, rax
    jz .xg_inval
    mov r13, rax
    mov r12d, dword [rsp + 24]

    mov edi, r12d
    mov esi, UXFS_XATTR_ACCESS_READ
    mov edx, dword [rsp + 16]
    call uxfs_xattr_may_access
    test eax, eax
    jnz .xg_return

    mov rdi, rbx
    mov esi, r12d
    mov rdx, r13
    call uxfs_xattr_find
    test rax, rax
    jz .xg_missing

    mov r14, rax
    movzx r15d, word [r14 + uxfs_xattr_entry_t.value_len]

    ; A null destination is a size query.
    mov rax, [rsp]
    test rax, rax
    jz .xg_size_only

    mov rcx, [rsp + 8]
    cmp r15, rcx
    ja .xg_toobig

    movzx eax, byte [r14 + uxfs_xattr_entry_t.name_len]
    lea rsi, [r14 + uxfs_xattr_entry_t_size]
    add rsi, rax                    ; Value begins after the name
    mov rdi, [rsp]
    mov rcx, r15
    rep movsb

.xg_size_only:
    inc qword [uxfs_xattr_gets]
    mov rax, r15
    jmp .xg_return

.xg_toobig:
    mov rax, POSIX_ENOSPC
    jmp .xg_return

.xg_missing:
    mov rax, POSIX_ENOENT
    jmp .xg_return

.xg_inval:
    mov rax, POSIX_EINVAL

.xg_return:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_xattr_remove
;
; Namespace-checked removal.
;
; Inputs:
;   RDI = Attribute block
;   RSI = Fully-qualified name
;   EDX = Non-zero when the caller is privileged
;
; Returns:
;   EAX = 0 on success, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_remove:
    push rbx
    push r12
    push r13
    sub rsp, 16

    mov rbx, rdi
    mov r13d, edx

    mov rdi, rsi
    mov rsi, rsp
    call uxfs_xattr_parse_ns
    test rax, rax
    jz .xr_inval
    mov r12, rax

    mov edi, dword [rsp]
    mov esi, UXFS_XATTR_ACCESS_WRITE
    mov edx, r13d
    call uxfs_xattr_may_access
    test eax, eax
    jnz .xr_return

    mov rdi, rbx
    mov esi, dword [rsp]
    mov rdx, r12
    call uxfs_xattr_remove_entry
    jmp .xr_return

.xr_inval:
    mov eax, POSIX_EINVAL

.xr_return:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_xattr_list
;
; Counts the attributes visible to the caller.
;
; trusted.* records are omitted for unprivileged callers, because their mere
; existence is information the namespace is meant to hide.
;
; Inputs:
;   RDI = Attribute block
;   ESI = Non-zero when the caller is privileged
;
; Returns:
;   RAX = Visible attribute count, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
uxfs_xattr_list:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12d, esi

    test rbx, rbx
    jz .xl_inval
    cmp dword [rbx + uxfs_xattr_header_t.magic], UXFS_XATTR_MAGIC
    jne .xl_inval

    mov r13d, dword [rbx + uxfs_xattr_header_t.count]
    lea rdi, [rbx + uxfs_xattr_header_t_size]
    xor r14, r14                    ; Visible count

.xl_loop:
    test r13d, r13d
    jz .xl_done

    mov ecx, dword [rdi + uxfs_xattr_entry_t.rec_len]
    test ecx, ecx
    jz .xl_done

    movzx eax, byte [rdi + uxfs_xattr_entry_t.namespace]
    cmp eax, UXFS_XATTR_NS_TRUSTED
    jne .xl_visible
    test r12d, r12d
    jz .xl_next                     ; Hidden from unprivileged callers

.xl_visible:
    inc r14

.xl_next:
    add rdi, rcx
    dec r13d
    jmp .xl_loop

.xl_done:
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.xl_inval:
    mov rax, POSIX_EINVAL
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_SECURITY_XATTR_ASM
