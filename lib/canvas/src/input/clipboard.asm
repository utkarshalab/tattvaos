; ============================================================================
; Clipboard — Clipboard and Primary Selection Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; clipboard_set
;   Set clipboard content
; ============================================================================
global clipboard_set
clipboard_set:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi       ; seat
    mov r12, rsi       ; data_source
    mov r13d, edx      ; serial
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get clipboard from seat
    mov rax, [rbx + Seat_CLIPBOARD]
    test rax, rax
    jnz .has_clipboard

    ; Create clipboard
    mov rdi, 80  ; Clipboard_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Seat_CLIPBOARD], rax

    mov qword [rax + Clipboard_SEAT], rbx
    mov qword [rax + Clipboard_DATA], 0
    mov qword [rax + Clipboard_DATA_LEN], 0
    mov qword [rax + Clipboard_MIME_TYPE], 0
    mov qword [rax + Clipboard_MIME_TYPE_LEN], 0
    mov qword [rax + Clipboard_SOURCE_CLIENT], 0
    mov qword [rax + Clipboard_SERIAL], 0
    mov qword [rax + Clipboard_SELECTION_TYPE], 0  ; 0 = clipboard, 1 = primary
    mov qword [rax + Clipboard_OFFERED_MIMES], 0
    mov dword [rax + Clipboard_OFFERED_COUNT], 0

.has_clipboard:
    ; Set data source
    mov rax, [rbx + Seat_CLIPBOARD]
    mov qword [rax + Clipboard_DATA], r12
    mov dword [rax + Clipboard_SERIAL], r13d
    mov dword [rax + Clipboard_SELECTION_TYPE], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.oom:
    mov rax, -ENOMEM
    leave
    ret

; ============================================================================
; clipboard_get
;   Get clipboard content
; ============================================================================
global clipboard_get
clipboard_get:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi       ; output data_source
    ASSERT_PTR rbx

    mov rax, [rbx + Seat_CLIPBOARD]
    test rax, rax
    jz .empty

    ; Return data source
    mov rax, [rax + Clipboard_DATA]
    mov [r12], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.empty:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; primary_selection_set
;   Set primary selection
; ============================================================================
global primary_selection_set
primary_selection_set:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Similar to clipboard_set but for primary selection
    mov rax, [rbx + Seat_PRIMARY_SELECTION]
    test rax, rax
    jnz .has_primary

    mov rdi, 80
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Seat_PRIMARY_SELECTION], rax

    mov qword [rax + Clipboard_SEAT], rbx
    mov qword [rax + Clipboard_DATA], 0
    mov qword [rax + Clipboard_DATA_LEN], 0
    mov qword [rax + Clipboard_MIME_TYPE], 0
    mov qword [rax + Clipboard_MIME_TYPE_LEN], 0
    mov qword [rax + Clipboard_SOURCE_CLIENT], 0
    mov qword [rax + Clipboard_SERIAL], 0
    mov qword [rax + Clipboard_SELECTION_TYPE], 1  ; 1 = primary
    mov qword [rax + Clipboard_OFFERED_MIMES], 0
    mov dword [rax + Clipboard_OFFERED_COUNT], 0

.has_primary:
    mov rax, [rbx + Seat_PRIMARY_SELECTION]
    mov qword [rax + Clipboard_DATA], r12
    mov dword [rax + Clipboard_SERIAL], r13d
    mov dword [rax + Clipboard_SELECTION_TYPE], 1

    xor rax, rax
    leave
    ret

.oom:
    mov rax, -ENOMEM
    leave
    ret

; ============================================================================
; primary_selection_get
;   Get primary selection
; ============================================================================
global primary_selection_get
primary_selection_get:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, [rbx + Seat_PRIMARY_SELECTION]
    test rax, rax
    jz .empty

    mov rax, [rax + Clipboard_DATA]
    mov [r12], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.empty:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global clipboard_version
clipboard_version: dq 0x010000