; =============================================================================
; str/net/url_parser.asm
; URL/URI parsing and IDN (Punycode) domain converters.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_punycode_encode
extern str_punycode_decode

struc ParsedURL
    .scheme    resb STRSLICE_SIZE
    .user      resb STRSLICE_SIZE
    .pass      resb STRSLICE_SIZE
    .host      resb STRSLICE_SIZE
    .port      resb STRSLICE_SIZE
    .path      resb STRSLICE_SIZE
    .query     resb STRSLICE_SIZE
    .fragment  resb STRSLICE_SIZE
endstruc

section .text

; -----------------------------------------------------------------------------
; str_url_parse
;
; Parses a full URL/URI string slice into structured ParsedURL components.
;
; Signature:
;   int64_t str_url_parse(const StrSlice *url, ParsedURL *out)
; -----------------------------------------------------------------------------
STR_FUNC str_url_parse
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    mov     rbx, rdi            ; url
    mov     r12, rsi            ; out

    ; zero out the ParsedURL output structure (128 bytes)
    mov     rdi, r12
    xor     eax, eax
    mov     ecx, 16             ; 16 * 8 = 128 bytes
    rep stosq

    mov     r13, [rbx + StrSlice.ptr]   ; cursor
    mov     rcx, [rbx + StrSlice.len]
    mov     r14, r13
    add     r14, rcx                    ; end ptr

    cmp     r13, r14
    jae     .parse_done

    ; 1. Find Scheme (look for "://")
    mov     rdi, r13
.find_scheme_loop:
    mov     rax, r14
    sub     rax, rdi
    cmp     rax, 3
    jb      .no_scheme

    cmp     byte [rdi], ':'
    jne     .next_scheme_char
    cmp     byte [rdi + 1], '/'
    jne     .next_scheme_char
    cmp     byte [rdi + 2], '/'
    je      .found_scheme

.next_scheme_char:
    inc     rdi
    jmp     .find_scheme_loop

.found_scheme:
    ; scheme is from r13 to rdi
    mov     [r12 + ParsedURL.scheme + StrSlice.ptr], r13
    mov     rax, rdi
    sub     rax, r13
    mov     [r12 + ParsedURL.scheme + StrSlice.len], rax

    ; advance cursor past "://"
    add     rdi, 3
    mov     r13, rdi
    jmp     .parse_authority

.no_scheme:
    ; no scheme found, start path parsing directly
    jmp     .parse_path

.parse_authority:
    ; authority runs until the first '/', '?', '#', or end
    mov     rdi, r13
.find_auth_end:
    cmp     rdi, r14
    jae     .found_auth_end
    movzx   eax, byte [rdi]
    cmp     al, '/'
    je      .found_auth_end
    cmp     al, '?'
    je      .found_auth_end
    cmp     al, '#'
    je      .found_auth_end
    inc     rdi
    jmp     .find_auth_end

.found_auth_end:
    mov     r9, rdi             ; auth end ptr
    ; authority slice is [r13, r9)

    ; check for '@' (User Info) within authority
    mov     rsi, r13
.find_at:
    cmp     rsi, r9
    jae     .no_userinfo
    cmp     byte [rsi], '@'
    je      .found_userinfo
    inc     rsi
    jmp     .find_at

.found_userinfo:
    ; userinfo is [r13, rsi)
    ; split userinfo by ':' into user and pass
    mov     rcx, r13
.find_user_colon:
    cmp     rcx, rsi
    jae     .user_only
    cmp     byte [rcx], ':'
    je      .user_and_pass
    inc     rcx
    jmp     .find_user_colon

.user_and_pass:
    mov     [r12 + ParsedURL.user + StrSlice.ptr], r13
    mov     rax, rcx
    sub     rax, r13
    mov     [r12 + ParsedURL.user + StrSlice.len], rax

    inc     rcx                 ; past ':'
    mov     [r12 + ParsedURL.pass + StrSlice.ptr], rcx
    mov     rax, rsi
    sub     rax, rcx
    mov     [r12 + ParsedURL.pass + StrSlice.len], rax
    jmp     .auth_host

.user_only:
    mov     [r12 + ParsedURL.user + StrSlice.ptr], r13
    mov     rax, rsi
    sub     rax, r13
    mov     [r12 + ParsedURL.user + StrSlice.len], rax
    jmp     .auth_host

.no_userinfo:
    ; no user info, host starts at r13
    mov     rsi, r13

.auth_host:
    ; host starts at rsi, ends at r9
    ; check for port (colon ':') in host
    mov     rcx, rsi
.find_port_colon:
    cmp     rcx, r9
    jae     .host_only
    cmp     byte [rcx], ':'
    je      .host_and_port
    inc     rcx
    jmp     .find_port_colon

.host_and_port:
    mov     [r12 + ParsedURL.host + StrSlice.ptr], rsi
    mov     rax, rcx
    sub     rax, rsi
    mov     [r12 + ParsedURL.host + StrSlice.len], rax

    inc     rcx                 ; past ':'
    mov     [r12 + ParsedURL.port + StrSlice.ptr], rcx
    mov     rax, r9
    sub     rax, rcx
    mov     [r12 + ParsedURL.port + StrSlice.len], rax
    jmp     .advance_auth

.host_only:
    mov     [r12 + ParsedURL.host + StrSlice.ptr], rsi
    mov     rax, r9
    sub     rax, rsi
    mov     [r12 + ParsedURL.host + StrSlice.len], rax

.advance_auth:
    mov     r13, r9             ; cursor is now at auth end

.parse_path:
    cmp     r13, r14
    jae     .parse_done

    ; check for fragment '#' in remainder
    mov     rdi, r13
.find_frag:
    cmp     rdi, r14
    jae     .no_frag
    cmp     byte [rdi], '#'
    je      .found_frag
    inc     rdi
    jmp     .find_frag

.found_frag:
    ; fragment is from rdi+1 to r14
    mov     rax, rdi
    inc     rax
    mov     [r12 + ParsedURL.fragment + StrSlice.ptr], rax
    mov     rcx, r14
    sub     rcx, rax
    mov     [r12 + ParsedURL.fragment + StrSlice.len], rcx
    mov     r14, rdi            ; truncate search boundary to before '#'

.no_frag:
    ; check for query '?' in remainder
    mov     rdi, r13
.find_query:
    cmp     rdi, r14
    jae     .no_query
    cmp     byte [rdi], '?'
    je      .found_query
    inc     rdi
    jmp     .find_query

.found_query:
    ; query is from rdi+1 to r14
    mov     rax, rdi
    inc     rax
    mov     [r12 + ParsedURL.query + StrSlice.ptr], rax
    mov     rcx, r14
    sub     rcx, rax
    mov     [r12 + ParsedURL.query + StrSlice.len], rcx
    mov     r14, rdi            ; truncate boundary to before '?'

.no_query:
    ; path is from r13 to r14
    mov     [r12 + ParsedURL.path + StrSlice.ptr], r13
    mov     rax, r14
    sub     rax, r13
    mov     [r12 + ParsedURL.path + StrSlice.len], rax

.parse_done:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_url_parse

; -----------------------------------------------------------------------------
; str_url_to_idn
;
; Translate a Unicode hostname into standard ASCII Punycode labels (e.g. xn--).
;
; Signature:
;   int64_t str_url_to_idn(const StrSlice *host, uint8_t *dst,
;                           uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_url_to_idn
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 32             ; allocate local storage (StrSlice and progress tracking)

    mov     rbx, rdi            ; host
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    mov     r15, [rbx + StrSlice.ptr]   ; cursor
    mov     rax, [rbx + StrSlice.len]
    mov     rcx, r15
    add     rcx, rax                    ; end ptr
    mov     [rsp + 24], rcx             ; save end ptr
    xor     r9, r9                      ; output offset

.label_loop:
    cmp     r15, [rsp + 24]
    jae     .idn_done

    ; find next dot '.' or end
    mov     rdi, r15
.find_dot:
    cmp     rdi, [rsp + 24]
    jae     .found_label_end
    cmp     byte [rdi], '.'
    je      .found_label_end
    inc     rdi
    jmp     .find_dot

.found_label_end:
    ; label is [r15, rdi)
    mov     [rsp + StrSlice.ptr], r15
    mov     rax, rdi
    sub     rax, r15
    mov     [rsp + StrSlice.len], rax

    ; check if label has any non-ASCII character
    mov     rsi, r15
    xor     ecx, ecx            ; has non-ascii = false
.ascii_check:
    cmp     rsi, rdi
    jae     .ascii_checked
    cmp     byte [rsi], 128
    jae     .non_ascii_found
    inc     rsi
    jmp     .ascii_check

.non_ascii_found:
    mov     ecx, 1
.ascii_checked:
    test    ecx, ecx
    jz      .write_raw_label

    ; non-ASCII: prefix with "xn--" and punycode encode
    ; capacity check
    mov     rax, r9
    add     rax, 4
    cmp     rax, r13
    ja      .idn_overflow

    mov     byte [r12 + r9], 'x'
    mov     byte [r12 + r9 + 1], 'n'
    mov     byte [r12 + r9 + 2], '-'
    mov     byte [r12 + r9 + 3], '-'
    add     r9, 4

    ; punycode encode label
    lea     rdi, [rsp]          ; slice
    mov     rsi, r12
    add     rsi, r9             ; dst
    mov     rdx, r13
    sub     rdx, r9             ; remaining cap
    lea     rcx, [rsp + 16]     ; out_len
    push    rdi
    push    r9
    push    r12
    push    r13
    push    r14
    push    r15
    push    rdi
    call    str_punycode_encode
    pop     rdi
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r9
    pop     rdi
    test    rax, rax
    jnz     .idn_err

    add     r9, [rsp + 16]      ; advance by encoded bytes
    jmp     .after_label

.write_raw_label:
    ; copy ASCII label directly
    mov     rcx, [rsp + StrSlice.len]
    mov     rax, r9
    add     rax, rcx
    cmp     rax, r13
    ja      .idn_overflow

    mov     rsi, [rsp + StrSlice.ptr]
    xor     edx, edx
.copy_loop:
    cmp     rdx, rcx
    jae     .copy_done
    movzx   eax, byte [rsi + rdx]
    mov     [r12 + r9 + rdx], al
    inc     rdx
    jmp     .copy_loop
.copy_done:
    add     r9, rcx

.after_label:
    ; advance cursor
    mov     r15, rdi
    cmp     r15, [rsp + 24]
    jae     .idn_done

    ; write dot '.'
    mov     rax, r9
    inc     rax
    cmp     rax, r13
    ja      .idn_overflow

    mov     byte [r12 + r9], '.'
    inc     r9
    inc     r15                 ; past dot
    jmp     .label_loop

.idn_done:
    mov     [r14], r9
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.idn_overflow:
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.idn_err:
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID
    pop     rbp
    ret
STR_ENDFUNC str_url_to_idn
