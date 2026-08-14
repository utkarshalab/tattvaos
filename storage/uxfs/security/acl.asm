; =============================================================================
; Tattva OS — storage/uxfs/security/acl.asm
; =============================================================================
; POSIX.1e Access Control Lists.
;
; Implements:
;   - ACL construction and validation (`uxfs_acl_init`, `uxfs_acl_validate`)
;   - Entry insertion and lookup (`uxfs_acl_add_entry`, `uxfs_acl_find`)
;   - The POSIX permission algorithm (`uxfs_acl_check`)
;   - Mask recalculation (`uxfs_acl_recalc_mask`)
;   - Mode-bit interoperability (`uxfs_acl_from_mode`, `uxfs_acl_to_mode`)
;
; Plain mode bits express exactly three subjects: owner, one group, everyone.
; That is not enough for an enterprise filesystem, where a file routinely needs
; distinct rights for several users and several groups at once. ACLs add named
; user and named group entries to cover that.
;
; The permission algorithm is order-sensitive and stops at the FIRST matching
; class, which is what makes ACLs deny-capable without explicit deny entries:
;
;   1. uid == owner                  -> ACL_USER_OBJ, mask NOT applied
;   2. uid matches a named user      -> that entry, masked
;   3. gid matches owning group      -> ACL_GROUP_OBJ, masked
;   4. gid matches a named group     -> that entry, masked
;   5. otherwise                     -> ACL_OTHER, mask NOT applied
;
; A named user entry granting rw is therefore CAPPED by the mask, while the
; owner entry is not. Checking every class and unioning the results — the
; intuitive implementation — silently grants access the mask was placed there
; to withhold.
;
; The mask is the mechanism by which a chmod on an ACL-bearing file still
; means something: lowering the group bits lowers the mask, which lowers every
; named entry at once.
;
; ACLs are persisted as the system.posix_acl_access extended attribute, so the
; namespace policy in xattr.asm is what stops an unprivileged process from
; rewriting the ACL that governs it.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

; Entry tags, in the canonical ordering an on-disk ACL must follow.
%define UXFS_ACL_USER_OBJ           0x01    ; The owning user
%define UXFS_ACL_USER               0x02    ; A named user
%define UXFS_ACL_GROUP_OBJ          0x04    ; The owning group
%define UXFS_ACL_GROUP              0x08    ; A named group
%define UXFS_ACL_MASK               0x10    ; Ceiling on all masked classes
%define UXFS_ACL_OTHER              0x20    ; Everyone else

; Permission bits, matching the POSIX rwx ordering.
%define UXFS_ACL_READ               0x04
%define UXFS_ACL_WRITE              0x02
%define UXFS_ACL_EXECUTE            0x01
%define UXFS_ACL_PERM_MASK          0x07

%define UXFS_ACL_MAX_ENTRIES        32
%define UXFS_ACL_UNDEFINED_ID       0xFFFFFFFF
%define UXFS_ACL_VERSION            2

struc uxfs_acl_entry_t
    .tag:               resw 1      ; UXFS_ACL_*
    .perm:              resw 1      ; rwx bits
    .id:                resd 1      ; uid or gid, or UXFS_ACL_UNDEFINED_ID
endstruc

struc uxfs_acl_t
    .version:           resd 1      ; UXFS_ACL_VERSION
    .count:             resd 1      ; Live entry count
    ; uxfs_acl_entry_t[count] follows
endstruc

section .data
align 8
uxfs_acl_checks:        dq 0
uxfs_acl_grants:        dq 0
uxfs_acl_denials:       dq 0

section .text

global uxfs_acl_init
global uxfs_acl_add_entry
global uxfs_acl_find
global uxfs_acl_check
global uxfs_acl_validate
global uxfs_acl_recalc_mask
global uxfs_acl_from_mode
global uxfs_acl_to_mode

; -----------------------------------------------------------------------------
; uxfs_acl_entry_ptr
;
; Inputs:
;   RDI = ACL, RSI = Entry index
;
; Returns:
;   RAX = Entry address
; -----------------------------------------------------------------------------
align 32
uxfs_acl_entry_ptr:
    mov rax, rsi
    imul rax, uxfs_acl_entry_t_size
    add rax, uxfs_acl_t_size
    add rax, rdi
    ret

; -----------------------------------------------------------------------------
; uxfs_acl_init
;
; Prepares an empty ACL.
;
; Inputs:
;   RDI = Pointer to an ACL buffer
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on a null argument
; -----------------------------------------------------------------------------
align 32
uxfs_acl_init:
    test rdi, rdi
    jz .ai_inval
    mov dword [rdi + uxfs_acl_t.version], UXFS_ACL_VERSION
    mov dword [rdi + uxfs_acl_t.count], 0
    xor eax, eax
    ret
.ai_inval:
    mov eax, POSIX_EINVAL
    ret

; -----------------------------------------------------------------------------
; uxfs_acl_add_entry
;
; Appends an entry.
;
; Inputs:
;   RDI = ACL
;   ESI = Tag
;   EDX = Permission bits
;   ECX = uid/gid, or UXFS_ACL_UNDEFINED_ID
;
; Returns:
;   EAX = 0 on success, POSIX_ENOSPC when full, POSIX_EINVAL on a bad tag
; -----------------------------------------------------------------------------
align 32
uxfs_acl_add_entry:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx

    test rbx, rbx
    jz .ae_inval

    ; Only the six defined tags are acceptable.
    cmp r12d, UXFS_ACL_USER_OBJ
    je .ae_tag_ok
    cmp r12d, UXFS_ACL_USER
    je .ae_tag_ok
    cmp r12d, UXFS_ACL_GROUP_OBJ
    je .ae_tag_ok
    cmp r12d, UXFS_ACL_GROUP
    je .ae_tag_ok
    cmp r12d, UXFS_ACL_MASK
    je .ae_tag_ok
    cmp r12d, UXFS_ACL_OTHER
    je .ae_tag_ok
    jmp .ae_inval

.ae_tag_ok:
    and r13d, UXFS_ACL_PERM_MASK    ; Silently drop undefined permission bits

    mov eax, dword [rbx + uxfs_acl_t.count]
    cmp eax, UXFS_ACL_MAX_ENTRIES
    jae .ae_nospc

    mov rdi, rbx
    mov rsi, rax
    call uxfs_acl_entry_ptr

    mov word [rax + uxfs_acl_entry_t.tag], r12w
    mov word [rax + uxfs_acl_entry_t.perm], r13w
    mov dword [rax + uxfs_acl_entry_t.id], r14d

    inc dword [rbx + uxfs_acl_t.count]

    xor eax, eax
    jmp .ae_return

.ae_nospc:
    mov eax, POSIX_ENOSPC
    jmp .ae_return

.ae_inval:
    mov eax, POSIX_EINVAL

.ae_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_acl_find
;
; Locates the first entry with a given tag, and matching id when the tag is a
; named user or group.
;
; Inputs:
;   RDI = ACL
;   ESI = Tag
;   EDX = id, ignored for tags that carry none
;
; Returns:
;   RAX = Entry pointer, or 0 when absent
; -----------------------------------------------------------------------------
align 32
uxfs_acl_find:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx

    test rbx, rbx
    jz .af_missing

    mov r14d, dword [rbx + uxfs_acl_t.count]
    xor r15, r15

.af_loop:
    cmp r15d, r14d
    jae .af_missing

    mov rdi, rbx
    mov rsi, r15
    call uxfs_acl_entry_ptr

    movzx ecx, word [rax + uxfs_acl_entry_t.tag]
    cmp ecx, r12d
    jne .af_next

    ; Named entries must also match on id.
    cmp r12d, UXFS_ACL_USER
    je .af_check_id
    cmp r12d, UXFS_ACL_GROUP
    je .af_check_id
    jmp .af_found

.af_check_id:
    cmp dword [rax + uxfs_acl_entry_t.id], r13d
    jne .af_next

.af_found:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.af_next:
    inc r15
    jmp .af_loop

.af_missing:
    xor rax, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_acl_recalc_mask
;
; Recomputes the mask as the union of every masked class: named users, named
; groups and the owning group.
;
; The owner and other entries are excluded because they are never masked.
; Including them would raise the ceiling above what the file's group bits are
; meant to permit.
;
; Inputs:
;   RDI = ACL
;
; Returns:
;   EAX = New mask permission bits, or POSIX_EINVAL
; -----------------------------------------------------------------------------
align 32
uxfs_acl_recalc_mask:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    test rbx, rbx
    jz .rm_inval

    mov r12d, dword [rbx + uxfs_acl_t.count]
    xor r13, r13                    ; Index
    xor r14d, r14d                  ; Accumulated union

.rm_loop:
    cmp r13d, r12d
    jae .rm_store

    mov rdi, rbx
    mov rsi, r13
    call uxfs_acl_entry_ptr

    movzx ecx, word [rax + uxfs_acl_entry_t.tag]

    cmp ecx, UXFS_ACL_USER
    je .rm_accumulate
    cmp ecx, UXFS_ACL_GROUP
    je .rm_accumulate
    cmp ecx, UXFS_ACL_GROUP_OBJ
    je .rm_accumulate
    jmp .rm_next

.rm_accumulate:
    movzx ecx, word [rax + uxfs_acl_entry_t.perm]
    or r14d, ecx

.rm_next:
    inc r13
    jmp .rm_loop

.rm_store:
    ; Write the recomputed value back into the mask entry when one exists.
    mov rdi, rbx
    mov esi, UXFS_ACL_MASK
    mov edx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_find
    test rax, rax
    jz .rm_done
    mov word [rax + uxfs_acl_entry_t.perm], r14w

.rm_done:
    mov eax, r14d
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.rm_inval:
    mov eax, POSIX_EINVAL
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_acl_check
;
; The POSIX.1e permission algorithm.
;
; Inputs:
;   RDI = ACL
;   ESI = Requesting uid
;   EDX = Requesting primary gid
;   ECX = Requested permission bits
;   R8D = Owning uid
;   R9D = Owning gid
;
; Returns:
;   EAX = 0 when permitted, POSIX_EACCES when denied, POSIX_EINVAL on a bad ACL
; -----------------------------------------------------------------------------
align 32
uxfs_acl_check:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov rbx, rdi                    ; ACL
    mov [rsp], rsi                  ; uid
    mov [rsp + 8], rdx              ; gid
    mov [rsp + 16], rcx             ; Wanted permissions
    mov r14d, r8d                   ; Owner uid
    mov r15d, r9d                   ; Owner gid

    test rbx, rbx
    jz .ac_inval
    cmp dword [rbx + uxfs_acl_t.version], UXFS_ACL_VERSION
    jne .ac_inval

    inc qword [uxfs_acl_checks]

    ; ---- 1. Owner: matched first, and NEVER masked ----
    mov eax, dword [rsp]
    cmp eax, r14d
    jne .ac_named_user

    mov rdi, rbx
    mov esi, UXFS_ACL_USER_OBJ
    mov edx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_find
    test rax, rax
    jz .ac_deny

    movzx r12d, word [rax + uxfs_acl_entry_t.perm]
    jmp .ac_decide                  ; No mask for the owner

    ; ---- 2. Named user ----
.ac_named_user:
    mov rdi, rbx
    mov esi, UXFS_ACL_USER
    mov edx, dword [rsp]
    call uxfs_acl_find
    test rax, rax
    jz .ac_owning_group

    movzx r12d, word [rax + uxfs_acl_entry_t.perm]
    jmp .ac_apply_mask

    ; ---- 3. Owning group ----
.ac_owning_group:
    mov eax, dword [rsp + 8]
    cmp eax, r15d
    jne .ac_named_group

    mov rdi, rbx
    mov esi, UXFS_ACL_GROUP_OBJ
    mov edx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_find
    test rax, rax
    jz .ac_named_group

    movzx r12d, word [rax + uxfs_acl_entry_t.perm]
    jmp .ac_apply_mask

    ; ---- 4. Named group ----
.ac_named_group:
    mov rdi, rbx
    mov esi, UXFS_ACL_GROUP
    mov edx, dword [rsp + 8]
    call uxfs_acl_find
    test rax, rax
    jz .ac_other

    movzx r12d, word [rax + uxfs_acl_entry_t.perm]
    jmp .ac_apply_mask

    ; ---- 5. Other: also never masked ----
.ac_other:
    mov rdi, rbx
    mov esi, UXFS_ACL_OTHER
    mov edx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_find
    test rax, rax
    jz .ac_deny

    movzx r12d, word [rax + uxfs_acl_entry_t.perm]
    jmp .ac_decide

.ac_apply_mask:
    ; Every masked class is capped by the mask entry, when one is present.
    mov rdi, rbx
    mov esi, UXFS_ACL_MASK
    mov edx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_find
    test rax, rax
    jz .ac_decide                   ; No mask entry: nothing to cap

    movzx ecx, word [rax + uxfs_acl_entry_t.perm]
    and r12d, ecx

.ac_decide:
    ; Every requested bit must be present in the effective set.
    mov ecx, dword [rsp + 16]
    and ecx, UXFS_ACL_PERM_MASK
    mov eax, r12d
    and eax, ecx
    cmp eax, ecx
    jne .ac_deny

    inc qword [uxfs_acl_grants]
    xor eax, eax
    jmp .ac_return

.ac_deny:
    inc qword [uxfs_acl_denials]
    mov eax, POSIX_EACCES
    jmp .ac_return

.ac_inval:
    mov eax, POSIX_EINVAL

.ac_return:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_acl_validate
;
; Checks structural validity.
;
; A minimal ACL needs exactly one USER_OBJ, one GROUP_OBJ and one OTHER. Any
; named user or group entry additionally requires a MASK, because without one
; there is no way for chmod to constrain those entries afterwards.
;
; Inputs:
;   RDI = ACL
;
; Returns:
;   EAX = 0 when valid, POSIX_EINVAL otherwise
; -----------------------------------------------------------------------------
align 32
uxfs_acl_validate:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    test rbx, rbx
    jz .av_inval
    cmp dword [rbx + uxfs_acl_t.version], UXFS_ACL_VERSION
    jne .av_inval

    mov r12d, dword [rbx + uxfs_acl_t.count]
    test r12d, r12d
    jz .av_inval
    cmp r12d, UXFS_ACL_MAX_ENTRIES
    ja .av_inval

    xor r13, r13                    ; Index
    xor r14d, r14d                  ; Tag presence bitmap
    xor r15d, r15d                  ; Named-entry counter

.av_loop:
    cmp r13d, r12d
    jae .av_check

    mov rdi, rbx
    mov rsi, r13
    call uxfs_acl_entry_ptr

    movzx ecx, word [rax + uxfs_acl_entry_t.tag]

    ; Reject undefined permission bits outright.
    movzx edx, word [rax + uxfs_acl_entry_t.perm]
    test edx, ~UXFS_ACL_PERM_MASK
    jnz .av_inval

    cmp ecx, UXFS_ACL_USER
    je .av_named
    cmp ecx, UXFS_ACL_GROUP
    je .av_named

    ; Singleton tags must not repeat.
    test r14d, ecx
    jnz .av_inval
    or r14d, ecx
    jmp .av_next

.av_named:
    inc r15d

.av_next:
    inc r13
    jmp .av_loop

.av_check:
    ; The three required singletons.
    test r14d, UXFS_ACL_USER_OBJ
    jz .av_inval
    test r14d, UXFS_ACL_GROUP_OBJ
    jz .av_inval
    test r14d, UXFS_ACL_OTHER
    jz .av_inval

    ; Named entries are meaningless without a mask to bound them.
    test r15d, r15d
    jz .av_ok
    test r14d, UXFS_ACL_MASK
    jz .av_inval

.av_ok:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.av_inval:
    mov eax, POSIX_EINVAL
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_acl_from_mode
;
; Builds the minimal ACL equivalent to a set of mode bits. Every file has a
; conceptual ACL even without a stored one; this is it.
;
; Inputs:
;   RDI = ACL buffer
;   ESI = POSIX mode bits
;
; Returns:
;   EAX = 0 on success
; -----------------------------------------------------------------------------
align 32
uxfs_acl_from_mode:
    push rbx
    push r12

    mov rbx, rdi
    mov r12d, esi

    call uxfs_acl_init
    test eax, eax
    jnz .fm_return

    ; Owner: mode bits 8..6
    mov rdi, rbx
    mov esi, UXFS_ACL_USER_OBJ
    mov edx, r12d
    shr edx, 6
    and edx, UXFS_ACL_PERM_MASK
    mov ecx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_add_entry

    ; Owning group: mode bits 5..3
    mov rdi, rbx
    mov esi, UXFS_ACL_GROUP_OBJ
    mov edx, r12d
    shr edx, 3
    and edx, UXFS_ACL_PERM_MASK
    mov ecx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_add_entry

    ; Other: mode bits 2..0
    mov rdi, rbx
    mov esi, UXFS_ACL_OTHER
    mov edx, r12d
    and edx, UXFS_ACL_PERM_MASK
    mov ecx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_add_entry

    xor eax, eax

.fm_return:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_acl_to_mode
;
; Projects an ACL back onto mode bits for stat().
;
; The GROUP bits come from the MASK when one exists, not from GROUP_OBJ. That
; is deliberate and matches POSIX: the mask is the effective ceiling, so
; reporting GROUP_OBJ would show permissions the mask actually withholds.
;
; Inputs:
;   RDI = ACL
;
; Returns:
;   EAX = Mode bits, or POSIX_EINVAL
; -----------------------------------------------------------------------------
align 32
uxfs_acl_to_mode:
    push rbx
    push r12

    mov rbx, rdi
    test rbx, rbx
    jz .tm_inval
    xor r12d, r12d                  ; Accumulated mode

    mov rdi, rbx
    mov esi, UXFS_ACL_USER_OBJ
    mov edx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_find
    test rax, rax
    jz .tm_group
    movzx ecx, word [rax + uxfs_acl_entry_t.perm]
    shl ecx, 6
    or r12d, ecx

.tm_group:
    ; Prefer the mask: it is what actually bounds group access.
    mov rdi, rbx
    mov esi, UXFS_ACL_MASK
    mov edx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_find
    test rax, rax
    jnz .tm_group_bits

    mov rdi, rbx
    mov esi, UXFS_ACL_GROUP_OBJ
    mov edx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_find
    test rax, rax
    jz .tm_other

.tm_group_bits:
    movzx ecx, word [rax + uxfs_acl_entry_t.perm]
    shl ecx, 3
    or r12d, ecx

.tm_other:
    mov rdi, rbx
    mov esi, UXFS_ACL_OTHER
    mov edx, UXFS_ACL_UNDEFINED_ID
    call uxfs_acl_find
    test rax, rax
    jz .tm_done
    movzx ecx, word [rax + uxfs_acl_entry_t.perm]
    or r12d, ecx

.tm_done:
    mov eax, r12d
    pop r12
    pop rbx
    ret

.tm_inval:
    mov eax, POSIX_EINVAL
    pop r12
    pop rbx
    ret
