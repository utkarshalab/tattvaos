%ifndef GUARD_PKG_FORMAT_UPK_ASM
%define GUARD_PKG_FORMAT_UPK_ASM
; =============================================================================
; File     : pkg/format/upk.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: UPK packages (docs/UPK_SPEC.md): open and verify one, find its
;              files. Built by utasm -f upk.
;
;   upk_open   checks a package in memory, in the order the spec's
;              "Installing" gives, and stops at the first failure: the
;              header and the place of every table (entry table, string
;              table and manifest exactly where the signature covers them);
;              the signature (signer among the trusted keys, Ed25519 over the
;              SHA-256 of header, tables and manifest); every entry (path,
;              kind, place, SHA-256); the manifest (known keys, each once;
;              name, version, kind; the entry). Nothing in the package runs.
;   upk_file   a file's bytes, by path.
; =============================================================================

bits 64

%include "pkg/format/upk.inc"

; upk_open's stack frame
%define UO_CTX          0                                   ; sha256_ctx_t
%define UO_DIGEST       ((sha256_ctx_t_size + 15) & ~15)    ; 32
%define UO_ZERO         (UO_DIGEST + 32)                    ; 64 zero bytes
%define UO_ALLOW        (UO_ZERO + 64)                      ; allow unsigned
%define UO_MAN_END      (UO_ALLOW + 8)                      ; end of the manifest
%define UO_VALS         (UO_MAN_END + 8)                    ; 10 x (ptr, len)
%define UO_SIZE         (UO_VALS + 160 + 8)                 ; 6 pushes: aligned

; manifest keys, in the order of their (ptr, len) slots
%define MK_NAME         0
%define MK_VERSION      1
%define MK_KIND         2
%define MK_ENTRY        5

section .rodata
upk_key_names:
    db 4, "name", 7, "version", 4, "kind", 5, "title", 9, "publisher"
    db 5, "entry", 12, "capabilities", 6, "models", 7, "depends", 6, "min_os"
    db 0
upk_reserved_names:
    db 3, "lib", 3, "cmd", 5, "model", 0
align 8, db 0                       ; the ULF image stays a multiple of 8 bytes

section .text

; -----------------------------------------------------------------------------
; upk_open — check and open a UPK package
; Input:  RDI = the package in memory, RSI = its length,
;         RDX = trusted public keys (32 bytes each), RCX = how many,
;         R8  = upk_pkg_t* to fill, R9 = 1 to accept an unsigned package
; Output: EAX = 0, or UPK_ERR_* (negative)
; -----------------------------------------------------------------------------
global upk_open
upk_open:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, UO_SIZE

    mov rbx, rdi                    ; RBX = the package
    mov r12, rsi                    ; R12 = its length
    mov r14, rdx                    ; R14 = trusted keys
    mov r15, rcx                    ; R15 = their count
    mov r13, r8                     ; R13 = the record
    mov [rsp + UO_ALLOW], r9

    mov rdi, r13
    xor eax, eax
    mov ecx, upk_pkg_t_size
    rep stosb
    lea rdi, [rsp + UO_ZERO]
    mov ecx, 64 + 8 + 8 + 160
    rep stosb

    ; ---- 1. the header and the tables' places ----
    cmp r12, UPK_HEADER_SIZE
    jb .format
    cmp dword [rbx + UPK_H_MAGIC], UPK_MAGIC
    jne .format
    cmp word [rbx + UPK_H_VERSION], UPK_VERSION
    jne .format
    cmp word [rbx + UPK_H_HSIZE], UPK_HEADER_SIZE
    jne .format
    test dword [rbx + UPK_H_FLAGS], ~UPK_FLAG_SIGNED
    jnz .format
    cmp qword [rbx + UPK_H_FILE_SIZE], r12
    jne .format
    mov ecx, [rbx + UPK_H_COUNT]
    test ecx, ecx
    jz .format
    cmp ecx, UPK_MAX_ENTRIES
    ja .format
    ; entries right after the header, the strings after them, the manifest
    ; after those: all inside what the signature covers
    cmp dword [rbx + UPK_H_ENTRY_OFF], UPK_HEADER_SIZE
    jne .format
    shl rcx, 6
    add rcx, UPK_HEADER_SIZE
    mov eax, [rbx + UPK_H_STR_OFF]
    cmp rax, rcx
    jne .format
    mov ecx, [rbx + UPK_H_STR_SIZE]
    test ecx, ecx
    jz .format
    add rax, rcx
    mov edx, [rbx + UPK_H_MAN_OFF]
    cmp rdx, rax
    jne .format
    cmp byte [rbx + rax - 1], 0     ; every path ends inside the string table
    jne .format
    mov ecx, [rbx + UPK_H_MAN_SIZE]
    cmp ecx, UPK_MAX_MANIFEST
    ja .format
    add rdx, rcx
    cmp rdx, r12
    ja .format
    mov [rsp + UO_MAN_END], rdx

    ; ---- 2. the signature ----
    test dword [rbx + UPK_H_FLAGS], UPK_FLAG_SIGNED
    jnz .signed
    cmp qword [rsp + UO_ALLOW], 0
    je .unsigned
    jmp .entries
.signed:
    ; the trusted key whose SHA-256 the header names
    xor ebp, ebp
.find_key:
    cmp rbp, r15
    jae .untrusted
    mov rdi, rbp
    shl rdi, 5
    add rdi, r14
    mov esi, 32
    lea rdx, [rsp + UO_DIGEST]
    call sha256_hash
    lea rsi, [rsp + UO_DIGEST]
    lea rdi, [rbx + UPK_H_SIGNER]
    mov ecx, 32
    repe cmpsb
    je .have_key
    inc rbp
    jmp .find_key
.have_key:
    shl rbp, 5
    add rbp, r14                    ; RBP = the public key
    ; the signed message: SHA-256 of the header (signature zero) and the
    ; tables and manifest after it
    lea rdi, [rsp + UO_CTX]
    call sha256_init
    lea rdi, [rsp + UO_CTX]
    mov rsi, rbx
    mov edx, UPK_H_SIGNATURE
    call sha256_update
    lea rdi, [rsp + UO_CTX]
    lea rsi, [rsp + UO_ZERO]
    mov edx, 64
    call sha256_update
    lea rdi, [rsp + UO_CTX]
    lea rsi, [rbx + UPK_HEADER_SIZE]
    mov rdx, [rsp + UO_MAN_END]
    sub rdx, UPK_HEADER_SIZE
    call sha256_update
    lea rdi, [rsp + UO_CTX]
    lea rsi, [rsp + UO_DIGEST]
    call sha256_final
    mov rdi, rbp
    lea rsi, [rsp + UO_DIGEST]
    mov edx, 32
    lea rcx, [rbx + UPK_H_SIGNATURE]
    call ed25519_verify
    cmp rax, 1
    jne .bad_signature
    mov dword [r13 + upk_pkg_t.signed], 1

    ; ---- 3. every entry ----
.entries:
    xor ebp, ebp                    ; RBP = the entry
.entry:
    cmp ebp, [rbx + UPK_H_COUNT]
    jae .entries_ok
    mov rdi, rbp
    shl rdi, 6
    lea r8, [rbx + rdi + UPK_HEADER_SIZE]   ; R8 = the entry
    mov eax, [r8 + UPK_E_PATH]
    cmp eax, [rbx + UPK_H_STR_SIZE]
    jae .format
    mov eax, [r8 + UPK_E_KIND]
    cmp eax, UPK_KIND_MAIN
    jb .format
    cmp eax, UPK_KIND_MODEL
    ja .format
    ; its bytes: after the manifest, 16-aligned, inside the package
    mov rax, [r8 + UPK_E_DATA_OFF]
    cmp rax, [rsp + UO_MAN_END]
    jb .format
    test eax, 15
    jnz .format
    mov rcx, [r8 + UPK_E_SIZE]
    add rcx, rax
    jc .format
    cmp rcx, r12
    ja .format
    ; its path, and no earlier entry with the same one
    push r8
    mov rdi, r8
    call .path_of                   ; RSI = the path
    call upk_path_ok
    pop r8
    jnz .bad_path
    xor r9d, r9d
.dup:
    cmp r9, rbp
    jae .dup_done
    mov rdi, r9
    shl rdi, 6
    lea rdi, [rbx + rdi + UPK_HEADER_SIZE]
    push r8
    push r9
    call .path_of
    mov rdx, rsi
    mov rdi, [rsp + 8]
    call .path_of
    call upk_streq
    pop r9
    pop r8
    je .bad_path
    inc r9
    jmp .dup
.dup_done:
    ; its SHA-256
    push r8
    mov rdi, [r8 + UPK_E_DATA_OFF]
    add rdi, rbx
    mov rsi, [r8 + UPK_E_SIZE]
    lea rdx, [rsp + 8 + UO_DIGEST]
    call sha256_hash
    pop r8
    lea rsi, [rsp + UO_DIGEST]
    lea rdi, [r8 + UPK_E_SHA256]
    mov ecx, 32
    repe cmpsb
    jne .bad_digest
    inc ebp
    jmp .entry
.entries_ok:

    ; ---- 4. the manifest ----
    call .manifest
    test eax, eax
    jnz .ret

    ; ---- the record ----
    mov [r13 + upk_pkg_t.data], rbx
    mov [r13 + upk_pkg_t.size], r12
    lea rax, [rbx + UPK_HEADER_SIZE]
    mov [r13 + upk_pkg_t.entries], rax
    mov eax, [rbx + UPK_H_COUNT]
    mov [r13 + upk_pkg_t.count], rax
    mov eax, [rbx + UPK_H_STR_OFF]
    add rax, rbx
    mov [r13 + upk_pkg_t.strtab], rax
    mov rax, [rsp + UO_VALS + MK_NAME*16]
    mov [r13 + upk_pkg_t.name], rax
    mov rax, [rsp + UO_VALS + MK_NAME*16 + 8]
    mov [r13 + upk_pkg_t.name_len], rax
    mov rax, [rsp + UO_VALS + MK_VERSION*16]
    mov [r13 + upk_pkg_t.version], rax
    mov rax, [rsp + UO_VALS + MK_VERSION*16 + 8]
    mov [r13 + upk_pkg_t.version_len], rax
    xor eax, eax
    jmp .ret

.format:
    mov eax, UPK_ERR_FORMAT
    jmp .ret
.unsigned:
    mov eax, UPK_ERR_UNSIGNED
    jmp .ret
.untrusted:
    mov eax, UPK_ERR_UNTRUSTED
    jmp .ret
.bad_signature:
    mov eax, UPK_ERR_SIGNATURE
    jmp .ret
.bad_digest:
    mov eax, UPK_ERR_DIGEST
    jmp .ret
.bad_path:
    mov eax, UPK_ERR_PATH
.ret:
    add rsp, UO_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; .path_of: RDI = an entry -> RSI = its path (NUL-terminated). Clobbers RAX.
.path_of:
    mov esi, [rdi + UPK_E_PATH]
    mov eax, [rbx + UPK_H_STR_OFF]
    add rsi, rax
    add rsi, rbx
    ret

; ---- .manifest: parse and check it -----------------------------------------
; Output: EAX = 0 or UPK_ERR_MANIFEST. Fills the (ptr, len) slots and the
; record's kind and entry. (Called with one return address on the stack, so
; the frame is at RSP + 8.)
.manifest:
    mov r8d, [rbx + UPK_H_MAN_OFF]
    add r8, rbx                     ; R8 = the cursor
    mov r9, rbx
    add r9, [rsp + 8 + UO_MAN_END]  ; R9 = the end
.m_line:
    cmp r8, r9
    jae .m_parsed
    mov r10, r8                     ; R10 = the line's start
.m_eol:
    cmp r8, r9
    jae .m_have_line
    cmp byte [r8], 10
    je .m_have_line
    inc r8
    jmp .m_eol
.m_have_line:
    mov r11, r8                     ; R11 = its end
    inc r8
    ; a '#' ends it
    mov rsi, r10
.m_comment:
    cmp rsi, r11
    jae .m_trim
    cmp byte [rsi], '#'
    je .m_cut
    inc rsi
    jmp .m_comment
.m_cut:
    mov r11, rsi
.m_trim:
    call .m_trim_range
    cmp r10, r11
    jae .m_line                     ; blank
    ; the '='
    mov rsi, r10
.m_eq:
    cmp rsi, r11
    jae .m_bad
    cmp byte [rsi], '='
    je .m_have_eq
    inc rsi
    jmp .m_eq
.m_have_eq:
    push r11
    push rsi                        ; the '='
    mov r11, rsi
    call .m_trim_range              ; the key: R10..R11
    call upk_key_slot               ; EAX = its slot, or -1
    pop rsi
    pop r11
    cmp eax, -1
    je .m_bad
    shl eax, 4
    lea rcx, [rsp + 8 + UO_VALS]
    add rcx, rax                    ; RCX = its (ptr, len)
    cmp qword [rcx], 0
    jne .m_bad                      ; a second time
    lea r10, [rsi + 1]
    call .m_trim_range              ; the value: R10..R11
    mov [rcx], r10
    mov rax, r11
    sub rax, r10
    mov [rcx + 8], rax
    test rax, rax
    jnz .m_line
    ; an empty value is allowed only for the optional keys; it must not
    ; read as "not given", so point it at its own place with length 0
    mov [rcx], r10
    jmp .m_line
.m_parsed:
    ; name: 1-32 of a-z 0-9 -, not reserved
    mov rsi, [rsp + 8 + UO_VALS + MK_NAME*16]
    mov rcx, [rsp + 8 + UO_VALS + MK_NAME*16 + 8]
    test rcx, rcx
    jz .m_bad
    cmp rcx, UPK_MAX_NAME
    ja .m_bad
    xor edx, edx
.m_name:
    cmp rdx, rcx
    jae .m_name_ok
    mov al, [rsi + rdx]
    inc rdx
    cmp al, '-'
    je .m_name
    cmp al, '0'
    jb .m_bad
    cmp al, '9'
    jbe .m_name
    cmp al, 'a'
    jb .m_bad
    cmp al, 'z'
    ja .m_bad
    jmp .m_name
.m_name_ok:
    lea rdi, [rel upk_reserved_names]
    call upk_in_list                ; RSI, RCX in the list at RDI?
    je .m_bad
    ; version: three runs of digits joined by '.'
    mov rsi, [rsp + 8 + UO_VALS + MK_VERSION*16]
    mov rcx, [rsp + 8 + UO_VALS + MK_VERSION*16 + 8]
    test rcx, rcx
    jz .m_bad
    add rcx, rsi                    ; RCX = its end
    mov edx, 3
.m_ver_part:
    xor r10d, r10d
.m_ver_digit:
    cmp rsi, rcx
    jae .m_ver_end
    mov al, [rsi]
    cmp al, '0'
    jb .m_ver_end
    cmp al, '9'
    ja .m_ver_end
    inc rsi
    inc r10
    jmp .m_ver_digit
.m_ver_end:
    test r10, r10
    jz .m_bad
    dec edx
    jz .m_ver_last
    cmp rsi, rcx
    jae .m_bad
    cmp byte [rsi], '.'
    jne .m_bad
    inc rsi
    jmp .m_ver_part
.m_ver_last:
    cmp rsi, rcx
    jne .m_bad
    ; kind: app, lib or cmd
    mov rsi, [rsp + 8 + UO_VALS + MK_KIND*16]
    mov rcx, [rsp + 8 + UO_VALS + MK_KIND*16 + 8]
    cmp rcx, 3
    jne .m_bad
    mov eax, UPK_PKG_APP
    cmp word [rsi], 'ap'
    jne .m_not_app
    cmp byte [rsi + 2], 'p'
    je .m_have_kind
.m_not_app:
    mov eax, UPK_PKG_LIB
    cmp word [rsi], 'li'
    jne .m_not_lib
    cmp byte [rsi + 2], 'b'
    je .m_have_kind
.m_not_lib:
    mov eax, UPK_PKG_CMD
    cmp word [rsi], 'cm'
    jne .m_bad
    cmp byte [rsi + 2], 'd'
    jne .m_bad
.m_have_kind:
    mov [r13 + upk_pkg_t.kind], eax
    ; entry: given exactly when the package is not a library, naming the one
    ; entry of kind main (app) or cmd (cmd); no other entry of those kinds
    mov rsi, [rsp + 8 + UO_VALS + MK_ENTRY*16]
    mov rcx, [rsp + 8 + UO_VALS + MK_ENTRY*16 + 8]
    mov r10d, UPK_KIND_MAIN
    cmp eax, UPK_PKG_CMD
    jne .m_main_kind
    mov r10d, UPK_KIND_CMD
.m_main_kind:
    cmp eax, UPK_PKG_LIB
    jne .m_needs_entry
    test rsi, rsi
    jnz .m_bad                      ; a library has no entry
    xor r10d, r10d                  ; and no main / cmd binary
    jmp .m_scan
.m_needs_entry:
    test rcx, rcx
    jz .m_bad
.m_scan:
    xor edx, edx                    ; EDX = entries of the main kinds
    xor r9d, r9d
.m_scan_next:
    cmp r9d, [rbx + UPK_H_COUNT]
    jae .m_scanned
    mov rdi, r9
    shl rdi, 6
    lea rdi, [rbx + rdi + UPK_HEADER_SIZE]
    inc r9d
    mov eax, [rdi + UPK_E_KIND]
    cmp eax, UPK_KIND_MAIN
    je .m_main
    cmp eax, UPK_KIND_CMD
    jne .m_scan_next
.m_main:
    inc edx
    cmp eax, r10d
    jne .m_bad                      ; the other main kind, or any in a library
    ; its path must be the entry's
    push rsi
    push rcx
    push rdi
    call .path_of_m                 ; RAX = its path
    pop rdi
    pop rcx
    pop rsi
    xor r11d, r11d
.m_cmp:
    cmp r11, rcx
    jae .m_cmp_end
    mov r8b, [rax + r11]
    cmp r8b, [rsi + r11]
    jne .m_bad
    inc r11
    jmp .m_cmp
.m_cmp_end:
    cmp byte [rax + rcx], 0
    jne .m_bad
    mov [r13 + upk_pkg_t.entry], rdi
    jmp .m_scan_next
.m_scanned:
    xor eax, eax
    cmp r10d, 0
    je .m_count_lib
    cmp edx, 1
    jne .m_bad
    ret
.m_count_lib:
    test edx, edx
    jnz .m_bad
    ret
.m_bad:
    mov eax, UPK_ERR_MANIFEST
    ret

; RDI = an entry -> RAX = its path. Clobbers nothing else.
.path_of_m:
    mov eax, [rdi + UPK_E_PATH]
    push rcx
    mov ecx, [rbx + UPK_H_STR_OFF]
    add rax, rcx
    add rax, rbx
    pop rcx
    ret

; R10..R11 -> the same range without spaces, tabs or CRs at either end.
; Clobbers AL.
.m_trim_range:
.m_front:
    cmp r10, r11
    jae .m_trimmed
    mov al, [r10]
    cmp al, ' '
    je .m_front_next
    cmp al, 9
    je .m_front_next
    cmp al, 13
    jne .m_back
.m_front_next:
    inc r10
    jmp .m_front
.m_back:
    cmp r11, r10
    jbe .m_trimmed
    mov al, [r11 - 1]
    cmp al, ' '
    je .m_back_next
    cmp al, 9
    je .m_back_next
    cmp al, 13
    jne .m_trimmed
.m_back_next:
    dec r11
    jmp .m_back
.m_trimmed:
    ret

; -----------------------------------------------------------------------------
; upk_key_slot — R10..R11 = a manifest key -> EAX = its slot (0-9), or -1
; Clobbers RCX, RDX, RDI.
; -----------------------------------------------------------------------------
upk_key_slot:
    lea rdi, [rel upk_key_names]
    xor eax, eax
.next:
    movzx ecx, byte [rdi]
    test ecx, ecx
    jz .none
    mov rdx, r11
    sub rdx, r10
    cmp rdx, rcx
    jne .skip
    ; same length: the same bytes?
    xor edx, edx
.cmp:
    cmp rdx, rcx
    jae .found
    push rax
    mov al, [r10 + rdx]
    cmp al, [rdi + 1 + rdx]
    pop rax
    jne .skip
    inc rdx
    jmp .cmp
.found:
    ret
.skip:
    lea rdi, [rdi + rcx + 1]
    inc eax
    jmp .next
.none:
    mov eax, -1
    ret

; -----------------------------------------------------------------------------
; upk_in_list — RSI, RCX = a string and its length, RDI = a list of
; length-prefixed strings ending in 0 -> ZF set when the string is in it.
; Clobbers RAX, RDX, RDI.
; -----------------------------------------------------------------------------
upk_in_list:
.next:
    movzx eax, byte [rdi]
    test eax, eax
    jz .no
    cmp rax, rcx
    jne .skip
    xor edx, edx
.cmp:
    cmp rdx, rcx
    jae .yes
    mov al, [rsi + rdx]
    cmp al, [rdi + 1 + rdx]
    jne .skip_reload
    inc rdx
    jmp .cmp
.skip_reload:
    movzx eax, byte [rdi]
.skip:
    lea rdi, [rdi + rax + 1]
    jmp .next
.yes:
    xor eax, eax                    ; ZF set
    ret
.no:
    or eax, 1                       ; ZF clear
    ret

; -----------------------------------------------------------------------------
; upk_path_ok — RSI = a NUL-terminated path -> ZF set when it is a package
; path: parts of a-z 0-9 . _ - joined by '/', none empty, "." or "..".
; Clobbers RAX, RCX, RDX.
; -----------------------------------------------------------------------------
upk_path_ok:
    push rsi
    xor ecx, ecx                    ; part length
    xor edx, edx                    ; dots in it
.c:
    mov al, [rsi]
    test al, al
    jz .end
    cmp al, '/'
    je .slash
    inc ecx
    cmp al, '.'
    jne .not_dot
    inc edx
    jmp .next
.not_dot:
    cmp al, '_'
    je .next
    cmp al, '-'
    je .next
    cmp al, '0'
    jb .bad
    cmp al, '9'
    jbe .next
    cmp al, 'a'
    jb .bad
    cmp al, 'z'
    ja .bad
.next:
    inc rsi
    jmp .c
.slash:
    call .part
    jnz .bad
    xor ecx, ecx
    xor edx, edx
    inc rsi
    jmp .c
.end:
    call .part
    pop rsi
    ret
.bad:
    or eax, 1
    pop rsi
    ret
.part:
    test ecx, ecx
    jz .part_bad
    cmp ecx, edx
    jne .part_good
    cmp ecx, 2
    jbe .part_bad
.part_good:
    xor eax, eax
    ret
.part_bad:
    or eax, 1
    ret

; -----------------------------------------------------------------------------
; upk_streq — RSI, RDX = two NUL-terminated strings -> ZF set when equal.
; Clobbers RCX, AL.
; -----------------------------------------------------------------------------
upk_streq:
    xor ecx, ecx
.c:
    mov al, [rsi + rcx]
    cmp al, [rdx + rcx]
    jne .r
    inc rcx
    test al, al
    jnz .c
.r:
    ret

; -----------------------------------------------------------------------------
; upk_file — a file of an opened package, by path
; Input:  RDI = upk_pkg_t* (from upk_open), RSI = the path (NUL-terminated)
; Output: RAX = its bytes, RDX = its size; RAX = 0 when there is no such file
; Clobbers: RCX, R8, R9
; -----------------------------------------------------------------------------
global upk_file
upk_file:
    mov r8, [rdi + upk_pkg_t.entries]
    mov r9, [rdi + upk_pkg_t.count]
.next:
    test r9, r9
    jz .none
    mov eax, [r8 + UPK_E_PATH]
    add rax, [rdi + upk_pkg_t.strtab]
    xor ecx, ecx
.cmp:
    mov dl, [rax + rcx]
    cmp dl, [rsi + rcx]
    jne .skip
    inc rcx
    test dl, dl
    jnz .cmp
    mov rax, [r8 + UPK_E_DATA_OFF]
    add rax, [rdi + upk_pkg_t.data]
    mov rdx, [r8 + UPK_E_SIZE]
    ret
.skip:
    add r8, UPK_ENTRY_SIZE
    dec r9
    jmp .next
.none:
    xor eax, eax
    xor edx, edx
    ret

%endif ; GUARD_PKG_FORMAT_UPK_ASM
