; ============================================================================
; Config — settings files read against a schema
; ============================================================================
; DEV-12. config_parse reads a settings file's text against a ConfigSchema
; (inc/config.inc) into a settings structure: every key's default first,
; then each line in turn, one of
;   blank, or a comment: # or ; first
;   [section]           the keys after it are that section's
;   key = value         a key of the current section (or of none, before
;                       any header) and its value, of the key's type:
;                       a decimal integer within its range, true / false
;                       (yes no on off 1 0), one of its names, or a string,
;                       bare (to the end of the line or a # or ; after a
;                       space, trimmed) or "quoted" (\" \\ \n \t)
; Lines end with LF or CR LF. A line not taken (bad syntax, no such section
; or key, a value not of its type, out of range, too long, a key given
; twice) changes nothing and is counted, the first one's line and reason
; kept; the keys under a section that does not exist are passed over with
; it. The rest are taken: one mistake in a file costs only its line.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/config.inc"

; config_parse's locals
%define CP_SEC      0                   ; the section's name in the text
%define CP_SECLEN   8
%define CP_SKIP     12                  ; 1 in a section that does not exist
%define CP_LINE     16
%define CP_SEEN     24                  ; keys given, by bit
%define CP_EOL      32                  ; the line's end (trimmed)
%define CP_NEXT     40                  ; the next line's start
%define CP_ENTRY    48
%define CP_BIT      56                  ; the key's bit in CP_SEEN
%define CP_VAL      64                  ; the value's start
%define CP_STR      72                  ; a string's value, as read
%define CP_FRAME    (CP_STR + CONFIG_MAX_STRING + 8)

section .text

; ---------------------------------------------------------------------------
; config_defaults
;   Every key of a schema at its default
;   IN:  rdi = ConfigSchema*, rsi = the settings
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global config_defaults
config_defaults:
    mov rcx, [rdi + ConfigSchema.count]
    lea rdx, [rdi + ConfigSchema.keys]
.key:
    test rcx, rcx
    jz .done
    mov r8d, [rdx + ConfigKey.offset]
    mov rax, [rdx + ConfigKey.default]
    cmp dword [rdx + ConfigKey.type], CONFIG_STRING
    je .string
    mov [rsi + r8], rax
    jmp .next
.string:                                ; copied, within its capacity
    mov r9, [rdx + ConfigKey.a]
    lea r11, [rsi + r8]
    xor r10d, r10d
.char:
    lea r8, [r10 + 1]
    cmp r8, r9
    jae .terminate
    push rcx
    mov cl, [rax + r10]
    mov [r11 + r10], cl
    test cl, cl
    pop rcx
    jz .next
    inc r10
    jmp .char
.terminate:
    mov byte [r11 + r10], 0
.next:
    add rdx, ConfigKey_size
    dec rcx
    jmp .key
.done:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; config_parse
;   A settings file's text into its settings
;   IN:  rdi = text, rsi = its length, rdx = ConfigSchema* (at most
;        CONFIG_MAX_KEYS keys, strings of at most CONFIG_MAX_STRING),
;        rcx = the settings, r8 = ConfigResult*
;   OUT: rax = 0 every line taken, -EINVAL some not (ConfigResult says how
;        many, the first and why); the settings hold what was taken
; ---------------------------------------------------------------------------
global config_parse
config_parse:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, CP_FRAME
    mov rbx, rdi
    lea r12, [rdi + rsi]
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    xor eax, eax
    mov [r15], rax
    mov [r15 + 8], rax
    mov [rsp + CP_SEC], rax
    mov [rsp + CP_SECLEN], eax
    mov [rsp + CP_SKIP], eax
    mov [rsp + CP_LINE], eax
    mov [rsp + CP_SEEN], rax
    mov rdi, r13
    mov rsi, r14
    call config_defaults
.line:
    cmp rbx, r12
    jae .done
    inc dword [rsp + CP_LINE]
    mov rdi, rbx                        ; its end
.scan:
    cmp rdi, r12
    jae .ended
    mov al, [rdi]
    cmp al, 10
    je .ended
    test al, al                         ; no NUL in a settings file
    jz .nul
    inc rdi
    jmp .scan
.nul:
    mov rdi, rbx                        ; the rest of the line passed over
.nul_skip:
    cmp rdi, r12
    jae .nul_end
    cmp byte [rdi], 10
    je .nul_end
    inc rdi
    jmp .nul_skip
.nul_end:
    lea rax, [rdi + 1]
    mov [rsp + CP_NEXT], rax
    mov eax, CONFIG_E_SYNTAX
    call error
    jmp .next
.ended:
    lea rax, [rdi + 1]
    mov [rsp + CP_NEXT], rax
    mov rsi, rbx
    call trim                           ; rsi .. rdi, no spaces at either end
    mov [rsp + CP_EOL], rdi
    cmp rsi, rdi
    je .next                            ; blank
    mov al, [rsi]
    cmp al, '#'
    je .next
    cmp al, ';'
    je .next
    cmp al, '['
    je .section
    ; key = value
    mov rdx, rsi                        ; the key
.key_char:
    cmp rsi, rdi
    jae .syntax
    mov al, [rsi]
    call is_key_char
    jne .key_end
    inc rsi
    jmp .key_char
.key_end:
    mov rcx, rsi
    sub rcx, rdx                        ; its length
    jz .syntax
    call skip_spaces
    cmp rsi, rdi
    jae .syntax
    cmp byte [rsi], '='
    jne .syntax
    inc rsi
    call skip_spaces                    ; rsi: the value
    cmp dword [rsp + CP_SKIP], 0        ; under a section that does not exist
    jne .next
    mov [rsp + CP_VAL], rsi
    mov rdi, rdx
    mov esi, ecx
    call find_key                       ; -> rax = the entry, ecx its index
    test rax, rax
    jz .no_key
    mov [rsp + CP_ENTRY], rax
    mov rdx, 1                          ; given before?
    shl rdx, cl
    test [rsp + CP_SEEN], rdx
    jnz .twice
    mov [rsp + CP_BIT], rdx             ; marked once taken
    mov rsi, [rsp + CP_VAL]
    mov rdi, [rsp + CP_EOL]
    call value                          ; -> eax = 0 or a reason
    test eax, eax
    jnz .error
    mov rdx, [rsp + CP_BIT]
    or [rsp + CP_SEEN], rdx
    jmp .next
.section:                               ; [name], then nothing or a comment
    inc rsi
    call skip_spaces
    mov rdx, rsi
.section_char:
    cmp rsi, rdi
    jae .syntax
    mov al, [rsi]
    call is_key_char
    jne .section_name
    inc rsi
    jmp .section_char
.section_name:                          ; then spaces and ]
    mov rcx, rsi
    sub rcx, rdx
    push rdx
    push rcx
    call skip_spaces
    pop rcx
    pop rdx
    cmp rsi, rdi
    jae .syntax
    cmp byte [rsi], ']'
    jne .syntax
    inc rsi
    push rdx
    push rcx
    call skip_spaces
    pop rcx
    pop rdx
    cmp rsi, rdi
    je .section_named
    mov al, [rsi]
    cmp al, '#'
    je .section_named
    cmp al, ';'
    jne .syntax
.section_named:
    test rcx, rcx
    jz .syntax
    mov [rsp + CP_SEC], rdx
    mov [rsp + CP_SECLEN], ecx
    mov dword [rsp + CP_SKIP], 0
    mov rdi, rdx
    mov esi, ecx
    call find_section
    test eax, eax
    jnz .next
    mov dword [rsp + CP_SKIP], 1
    mov eax, CONFIG_E_SECTION
    jmp .error
.syntax:
    mov eax, CONFIG_E_SYNTAX
    jmp .error
.no_key:
    mov eax, CONFIG_E_KEY
    jmp .error
.twice:
    mov eax, CONFIG_E_TWICE
.error:
    call error
.next:
    mov rbx, [rsp + CP_NEXT]
    jmp .line
.done:
    xor eax, eax
    cmp dword [r15 + ConfigResult.errors], 0
    je .out
    mov rax, -EINVAL
.out:
    add rsp, CP_FRAME
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; Local (config_parse's: rbx the line, r12 the text's end, r13 the schema,
; r14 the settings, r15 the result; its locals 16 bytes above rsp in what
; it calls)
; ---------------------------------------------------------------------------

; eax = a reason: counted; the first one's line and reason kept
error:
    inc dword [r15 + ConfigResult.errors]
    cmp dword [r15 + ConfigResult.errors], 1
    jne .out
    mov [r15 + ConfigResult.reason], eax
    mov eax, [rsp + 8 + CP_LINE]
    mov [r15 + ConfigResult.line], eax
.out:
    ret

; rsi .. rdi -> both moved past spaces, tabs and a CR at either end
trim:
    call skip_spaces
.end:
    cmp rdi, rsi
    jbe .out
    mov al, [rdi - 1]
    cmp al, ' '
    je .back
    cmp al, 9
    je .back
    cmp al, 13
    jne .out
.back:
    dec rdi
    jmp .end
.out:
    ret

; rsi -> past spaces and tabs, not past rdi
skip_spaces:
    cmp rsi, rdi
    jae .out
    mov al, [rsi]
    cmp al, ' '
    je .skip
    cmp al, 9
    jne .out
.skip:
    inc rsi
    jmp skip_spaces
.out:
    ret

; al -> ZF set for a letter, digit, _ - or .
is_key_char:
    cmp al, '_'
    je .yes
    cmp al, '-'
    je .yes
    cmp al, '.'
    je .yes
    cmp al, '0'
    jb .no
    cmp al, '9'
    jbe .yes
    or al, 0x20
    cmp al, 'a'
    jb .no
    cmp al, 'z'
    ja .no
.yes:
    cmp al, al
    ret
.no:
    test esp, esp
    ret

; rdi = text, esi = its length, rdx = a NUL-terminated name -> ZF set when
; they are the same; rcx, rdi, rsi kept
same_name:
    push rcx
    xor ecx, ecx
.char:
    cmp ecx, esi
    je .end
    mov al, [rdx + rcx]
    test al, al
    jz .differ
    cmp al, [rdi + rcx]
    jne .differ
    inc ecx
    jmp .char
.end:
    cmp byte [rdx + rcx], 0
    pop rcx
    ret
.differ:
    test esp, esp
    pop rcx
    ret

; rdi, esi = a section's name -> eax = 1 some key is in it
find_section:
    mov r8, [r13 + ConfigSchema.count]
    lea rdx, [r13 + ConfigSchema.keys]
.key:
    test r8, r8
    jz .none
    call same_name
    je .found
    add rdx, ConfigKey_size
    dec r8
    jmp .key
.found:
    mov eax, 1
    ret
.none:
    xor eax, eax
    ret

; rdi, esi = a key's name -> rax = its entry in the current section (0
; none), ecx = its index
find_key:
    mov r8, [r13 + ConfigSchema.count]
    lea rdx, [r13 + ConfigSchema.keys]
    xor r9d, r9d
.key:
    cmp r9, r8
    jae .none
    cmp r9d, CONFIG_MAX_KEYS
    jae .none
    push rdi
    push rsi
    mov rdi, [rsp + 16 + 8 + CP_SEC]    ; its section: the current one (two
    mov esi, [rsp + 16 + 8 + CP_SECLEN] ; pushes and the return above)
    test rdi, rdi
    jnz .compare_section
    cmp byte [rdx], 0                   ; its section name (which starts it) ""
    jmp .section_known
.compare_section:
    call same_name
.section_known:
    pop rsi
    pop rdi
    jne .next
    add rdx, ConfigKey.key
    call same_name
    lea rdx, [rdx - ConfigKey.key]
    je .found
.next:
    add rdx, ConfigKey_size
    inc r9d
    jmp .key
.found:
    mov rax, rdx
    mov ecx, r9d
    ret
.none:
    xor eax, eax
    ret

; rsi = a value's start, rdi = its line's end; [CP_ENTRY] its key -> eax =
; 0 stored, or a reason
value:
    mov rdx, [rsp + 8 + CP_ENTRY]
    cmp rsi, rdi
    jae .bare_end
    cmp byte [rsi], '"'
    je .quoted
    mov r8, rsi                         ; bare: to a # or ; after a space
.bare:
    cmp r8, rdi
    jae .bare_cut
    mov al, [r8]
    cmp al, '#'
    je .comment
    cmp al, ';'
    jne .bare_next
.comment:
    cmp r8, rsi
    je .bare_next
    mov al, [r8 - 1]
    cmp al, ' '
    je .bare_cut
    cmp al, 9
    je .bare_cut
.bare_next:
    inc r8
    jmp .bare
.bare_cut:
    mov rdi, r8
    call trim
.bare_end:
    mov rcx, rdi
    sub rcx, rsi                        ; the value: rsi, rcx bytes
    mov eax, [rdx + ConfigKey.type]
    cmp eax, CONFIG_STRING
    je .bare_string
    test rcx, rcx
    jz .not_value
    cmp eax, CONFIG_INT
    je .integer
    cmp eax, CONFIG_BOOL
    je .boolean
    cmp eax, CONFIG_ENUM
    je .choice
    jmp .not_value
.bare_string:
    cmp rcx, [rdx + ConfigKey.a]
    jae .long
    mov r8d, [rdx + ConfigKey.offset]
    lea r8, [r14 + r8]
    xor r9d, r9d
.bare_copy:
    cmp r9, rcx
    jae .bare_copied
    mov al, [rsi + r9]
    mov [r8 + r9], al
    inc r9
    jmp .bare_copy
.bare_copied:
    mov byte [r8 + r9], 0
    jmp .stored
.quoted:                                ; into CP_STR first
    cmp dword [rdx + ConfigKey.type], CONFIG_STRING
    jne .not_value
    inc rsi
    xor ecx, ecx                        ; its length
.quoted_char:
    cmp rsi, rdi
    jae .syntax                         ; no closing quote
    mov al, [rsi]
    inc rsi
    cmp al, '"'
    je .quoted_end
    cmp al, '\'
    jne .quoted_put
    cmp rsi, rdi
    jae .syntax
    mov al, [rsi]
    inc rsi
    cmp al, '"'
    je .quoted_put
    cmp al, '\'
    je .quoted_put
    mov ah, 10
    cmp al, 'n'
    je .escaped
    mov ah, 9
    cmp al, 't'
    jne .not_value
.escaped:
    mov al, ah
.quoted_put:
    cmp ecx, CONFIG_MAX_STRING
    jae .long
    mov [rsp + 8 + CP_STR + rcx], al
    inc ecx
    jmp .quoted_char
.quoted_end:                            ; then nothing or a comment
    push rcx
    call skip_spaces
    pop rcx
    cmp rsi, rdi
    je .quoted_ok
    mov al, [rsi]
    cmp al, '#'
    je .quoted_ok
    cmp al, ';'
    jne .syntax
.quoted_ok:
    cmp rcx, [rdx + ConfigKey.a]
    jae .long
    mov r8d, [rdx + ConfigKey.offset]
    lea r8, [r14 + r8]
    xor r9d, r9d
.quoted_copy:
    cmp r9, rcx
    jae .quoted_copied
    mov al, [rsp + 8 + CP_STR + r9]
    mov [r8 + r9], al
    inc r9
    jmp .quoted_copy
.quoted_copied:
    mov byte [r8 + r9], 0
    jmp .stored
.integer:                               ; [+-]digits, within [a, b]
    xor r8d, r8d                        ; negative
    xor eax, eax
    mov al, [rsi]
    cmp al, '-'
    jne .plus
    mov r8d, 1
    jmp .sign
.plus:
    cmp al, '+'
    jne .digits
.sign:
    inc rsi
    dec rcx
    jz .not_value
.digits:
    xor eax, eax
    mov r9, 0x0CCCCCCCCCCCCCCC          ; past it, ten times overflows
.digit:
    movzx r10d, byte [rsi]
    sub r10d, '0'
    cmp r10d, 9
    ja .not_value
    cmp rax, r9
    ja .range
    imul rax, rax, 10
    add rax, r10
    js .range
    inc rsi
    dec rcx
    jnz .digit
    test r8d, r8d
    jz .signed
    neg rax
.signed:
    cmp rax, [rdx + ConfigKey.a]
    jl .range
    cmp rax, [rdx + ConfigKey.b]
    jg .range
    jmp .store
.boolean:
    mov rdi, rsi
    mov esi, ecx
    push rdx
    lea rdx, [rel bool_names]
    call choose
    pop rdx
    test eax, eax
    js .not_value
    and eax, 1                          ; names alternate true, false: 1, 0
    xor eax, 1
    jmp .store
.choice:
    mov rdi, rsi
    mov esi, ecx
    push rdx
    mov rdx, [rdx + ConfigKey.a]
    call choose
    pop rdx
    test eax, eax
    js .not_value
.store:
    mov r8d, [rdx + ConfigKey.offset]
    mov [r14 + r8], rax
.stored:
    xor eax, eax
    ret
.not_value:
    mov eax, CONFIG_E_VALUE
    ret
.range:
    mov eax, CONFIG_E_RANGE
    ret
.long:
    mov eax, CONFIG_E_LONG
    ret
.syntax:
    mov eax, CONFIG_E_SYNTAX
    ret

; rdi, esi = a word, rdx = names (each NUL-terminated, "" after the last)
; -> rax = its index among them, -1 none
choose:
    xor r9d, r9d
.name:
    cmp byte [rdx], 0
    je .none
    call same_name
    je .found
.skip:
    inc rdx
    cmp byte [rdx - 1], 0
    jne .skip
    inc r9d
    jmp .name
.found:
    mov eax, r9d
    ret
.none:
    mov rax, -1
    ret

section .rodata
; true and false by turns (choose's index: even true, odd false)
bool_names:
    db "true", 0, "false", 0, "yes", 0, "no", 0, "on", 0, "off", 0
    db "1", 0, "0", 0, 0

section .data

global config_version
config_version: dq 0x010000
