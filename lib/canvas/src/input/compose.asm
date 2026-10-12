; ============================================================================
; Compose — Dead Keys and Compose Sequences (Multi-key)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

%define COMPOSE_MAX_SEQ     8
%define COMPOSE_MAX_ENTRIES 1024

struc ComposeState {
    .active:        resb 1
    .sequence_len:  resb 1
    .sequence:      resd COMPOSE_MAX_SEQ
    .table:         resq 1
}
%define ComposeState_size    48

struc ComposeEntry {
    .sequence:      resd COMPOSE_MAX_SEQ
    .len:           resb 1
    .result:        resd 1
}
%define ComposeEntry_size    40

; ---------------------------------------------------------------------------
; compose_init
; ---------------------------------------------------------------------------
global compose_init
compose_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate compose state
    mov rdi, r12
    mov rsi, ComposeState_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Server.compose_state], rax

    ; Load compose table
    call compose_load_table

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; compose_load_table
; ---------------------------------------------------------------------------
compose_load_table:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate table
    mov rdi, r12
    mov rsi, COMPOSE_MAX_ENTRIES
    imul rsi, ComposeEntry_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Server.compose_table], rax

    ; Populate default compose sequences
    call compose_populate_default

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; compose_populate_default
; ---------------------------------------------------------------------------
compose_populate_default:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, [rbx + Server.compose_table]
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Common compose sequences
    ; dead_acute + a = á
    call compose_add_entry 0xFE51, 'a', 0xE1
    ; dead_grave + a = à
    call compose_add_entry 0xFE50, 'a', 0xE0
    ; dead_circumflex + a = â
    call compose_add_entry 0xFE52, 'a', 0xE2
    ; dead_tilde + a = ã
    call compose_add_entry 0xFE53, 'a', 0xE3
    ; dead_diaeresis + a = ä
    call compose_add_entry 0xFE54, 'a', 0xE4
    ; dead_acute + e = é
    call compose_add_entry 0xFE51, 'e', 0xE9
    ; dead_acute + i = í
    call compose_add_entry 0xFE51, 'i', 0xED
    ; dead_acute + o = ó
    call compose_add_entry 0xFE51, 'o', 0xF3
    ; dead_acute + u = ú
    call compose_add_entry 0xFE51, 'u', 0xFA
    ; dead_grave + e = è
    call compose_add_entry 0xFE50, 'e', 0xE8
    ; dead_grave + i = ì
    call compose_add_entry 0xFE50, 'i', 0xEC
    ; dead_grave + o = ò
    call compose_add_entry 0xFE50, 'o', 0xF2
    ; dead_grave + u = ù
    call compose_add_entry 0xFE50, 'u', 0xF9
    ; dead_circumflex + e = ê
    call compose_add_entry 0xFE52, 'e', 0xEA
    ; dead_circumflex + i = î
    call compose_add_entry 0xFE52, 'i', 0xEE
    ; dead_circumflex + o = ô
    call compose_add_entry 0xFE52, 'o', 0xF4
    ; dead_circumflex + u = û
    call compose_add_entry 0xFE52, 'u', 0xFB
    ; dead_tilde + n = ñ
    call compose_add_entry 0xFE53, 'n', 0xF1
    ; dead_tilde + o = õ
    call compose_add_entry 0xFE53, 'o', 0xF5
    ; dead_diaeresis + e = ë
    call compose_add_entry 0xFE54, 'e', 0xEB
    ; dead_diaeresis + i = ï
    call compose_add_entry 0xFE54, 'i', 0xEF
    ; dead_diaeresis + o = ö
    call compose_add_entry 0xFE54, 'o', 0xF6
    ; dead_diaeresis + u = ü
    call compose_add_entry 0xFE54, 'u', 0xFC
    ; dead_cedilla + c = ç
    call compose_add_entry 0xFE55, 'c', 0xE7
    ; dead_stroke + o = ø
    call compose_add_entry 0xFE56, 'o', 0xF8
    ; dead_ogonek + a = ą
    call compose_add_entry 0xFE57, 'a', 0x105
    ; dead_horn + o = ơ
    call compose_add_entry 0xFE58, 'o', 0x1A1
    ; dead_hook + u = ư
    call compose_add_entry 0xFE59, 'u', 0x1B0
    ; dead_doubleacute + o = ő
    call compose_add_entry 0xFE5A, 'o', 0x151
    ; dead_doubleacute + u = ű
    call compose_add_entry 0xFE5A, 'u', 0x171
    ; dead_belowdot + a = ạ
    call compose_add_entry 0xFE5B, 'a', 0x1EA1
    ; dead_belowdot + o = ọ
    call compose_add_entry 0xFE5B, 'o', 0x1ECD
    ; dead_belowdot + u = ụ
    call compose_add_entry 0xFE5B, 'u', 0x1EE5
    ; dead_hook + o = ổ
    call compose_add_entry 0xFE5C, 'o', 0x1ED3
    ; dead_horn + u = ư
    call compose_add_entry 0xFE5D, 'u', 0x1B0
    ; Multi-key sequences: <Multi_key> <o> <c> = ©
    call compose_add_entry 0xFE03, 'o', 'c', 0xA9
    ; <Multi_key> <o> <r> = ®
    call compose_add_entry 0xFE03, 'o', 'r', 0xAE
    ; <Multi_key> <T> <M> = ™
    call compose_add_entry 0xFE03, 'T', 'M', 0x2122
    ; <Multi_key> <1> <2> = ½
    call compose_add_entry 0xFE03, '1', '2', 0xBD
    ; <Multi_key> <1> <4> = ¼
    call compose_add_entry 0xFE03, '1', '4', 0xBC
    ; <Multi_key> <3> <4> = ¾
    call compose_add_entry 0xFE03, '3', '4', 0xBE
    ; <Multi_key> <-> <-> = —
    call compose_add_entry 0xFE03, '-', '-', 0x2014
    ; <Multi_key> <.> <.> <.> = …
    call compose_add_entry 0xFE03, '.', '.', '.', 0x2026

    ret

; ---------------------------------------------------------------------------
; compose_add_entry
;   IN: rdi = keysym1, rsi = keysym2, rdx = keysym3 (optional), rcx = result
; ---------------------------------------------------------------------------
compose_add_entry:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ; TODO: Add to table
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; compose_process_key
;   Process key through compose state
;   IN:  rdi = compose_state*, rsi = keysym
;   OUT: rax = result keysym (0 if composing)
; ---------------------------------------------------------------------------
global compose_process_key
compose_process_key:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Check for Multi_key
    cmp r12, 0xFE03  ; XK_Multi_key
    je .multi_key

    ; Check for dead keys
    cmp r12, 0xFE50  ; dead_grave
    je .dead_key
    cmp r12, 0xFE51  ; dead_acute
    je .dead_key
    cmp r12, 0xFE52  ; dead_circumflex
    je .dead_key
    cmp r12, 0xFE53  ; dead_tilde
    je .dead_key
    cmp r12, 0xFE54  ; dead_diaeresis
    je .dead_key
    cmp r12, 0xFE55  ; dead_cedilla
    je .dead_key
    cmp r12, 0xFE56  ; dead_stroke
    je .dead_key
    cmp r12, 0xFE57  ; dead_ogonek
    je .dead_key
    cmp r12, 0xFE58  ; dead_horn
    je .dead_key

    ; Regular key
    mov al, [rbx + ComposeState.active]
    test al, al
    jz .no_compose

    ; Add to sequence
    mov al, [rbx + ComposeState.sequence_len]
    cmp al, COMPOSE_MAX_SEQ
    jae .reset

    mov [rbx + ComposeState.sequence + rax * 4], r12d
    inc byte [rbx + ComposeState.sequence_len]

    ; Try to match sequence
    call compose_match_sequence
    test rax, rax
    jz .composing

    ; Match found
    call compose_reset
    ret

.composing:
    xor rax, rax
    ret

.reset:
    call compose_reset
    xor rax, rax
    ret

.no_compose:
    mov rax, r12
    ret

.multi_key:
    mov byte [rbx + ComposeState.active], 1
    mov byte [rbx + ComposeState.sequence_len], 0
    xor rax, rax
    ret

.dead_key:
    mov byte [rbx + ComposeState.active], 1
    mov byte [rbx + ComposeState.sequence_len], 1
    mov [rbx + ComposeState.sequence + 0], r12d
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; compose_match_sequence
; ---------------------------------------------------------------------------
compose_match_sequence:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12, [rbx + Server.compose_table]
    mov r13, [rbx + ComposeState.sequence_len]
    test r13, r13
    jz .no_match

    mov r14, 0
    mov r15, COMPOSE_MAX_ENTRIES
.search_loop:
    cmp r14, r15
    jae .no_match

    ; Check length
    mov al, [r12 + ComposeEntry.len]
    cmp al, [rbx + ComposeState.sequence_len]
    jne .next_entry

    ; Compare sequence
    mov rdi, [rbx + ComposeState.sequence]
    mov rsi, r12
    add rsi, ComposeEntry.sequence
    mov rcx, r13
.compare_loop:
    test rcx, rcx
    jz .match
    mov eax, [rdi]
    cmp eax, [rsi]
    jne .next_entry
    add rdi, 4
    add rsi, 4
    dec rcx
    jmp .compare_loop

.match:
    mov eax, [r12 + ComposeEntry.result]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.next_entry:
    add r12, ComposeEntry_size
    inc r14
    jmp .search_loop

.no_match:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; compose_reset
; ---------------------------------------------------------------------------
compose_reset:
    PROLOGUE
    mov byte [rdi + ComposeState.active], 0
    mov byte [rdi + ComposeState.sequence_len], 0
    xor rax, rax
    ret

section .data
global compose_version
compose_version: dq 0x010000