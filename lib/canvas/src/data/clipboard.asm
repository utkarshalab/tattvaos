; ============================================================================
; Clipboard — Clipboard and Primary Selection Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/str.inc"

; struct offsets (hoisted above use)
%define Clipboard_size    80
%define SELECTION_CLIPBOARD    0
%define SELECTION_PRIMARY      1
%define CLIPBOARD_MAX_MIMES    16
%define CLIPBOARD_MAX_SIZE     (1024 * 1024)  ; 1MB default limit

section .text

struc Clipboard
    .seat:              resq 1
    .data:              resq 1
    .data_len:          resq 1
    .mime_type:         resq 1
    .mime_type_len:     resq 1
    .source_client:     resq 1
    .serial:            resq 1
    .selection_type:    resd 1  ; 0=clipboard, 1=primary
    .offered_mimes:     resq 1
    .offered_count:     resd 1
endstruc



; ---------------------------------------------------------------------------
; clipboard_init
; ---------------------------------------------------------------------------
global clipboard_init
clipboard_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.clipboard], 0
    mov qword [rbx + Server.primary_selection], 0
    mov qword [rbx + Server.arena], r12

    ; Allocate clipboard
    mov rdi, r12
    mov rsi, Clipboard_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize clipboard
    mov qword [rbx + Clipboard.seat], 0
    mov qword [rbx + Clipboard.data], 0
    mov qword [rbx + Clipboard.data_len], 0
    mov qword [rbx + Clipboard.mime_type], 0
    mov qword [rbx + Clipboard.mime_type_len], 0
    mov qword [rbx + Clipboard.source_client], 0
    mov qword [rbx + Clipboard.serial], 0
    mov dword [rbx + Clipboard.selection_type], SELECTION_CLIPBOARD
    mov qword [rbx + Clipboard.offered_mimes], 0
    mov dword [rbx + Clipboard.offered_count], 0

    mov [rdi + Server.clipboard], rbx

    ; Allocate primary selection
    mov rdi, r12
    mov rsi, Clipboard_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + Clipboard.seat], 0
    mov qword [rbx + Clipboard.data], 0
    mov qword [rbx + Clipboard.data_len], 0
    mov qword [rbx + Clipboard.mime_type], 0
    mov qword [rbx + Clipboard.mime_type_len], 0
    mov qword [rbx + Clipboard.source_client], 0
    mov qword [rbx + Clipboard.serial], 0
    mov dword [rbx + Clipboard.selection_type], SELECTION_PRIMARY
    mov qword [rbx + Clipboard.offered_mimes], 0
    mov dword [rbx + Clipboard.offered_count], 0

    mov [rdi + Server.primary_selection], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; clipboard_set
;   Set clipboard data
;   IN:  rdi = server*, rsi = client*, rdx = mime_type, rcx = mime_len, r8 = data, r9 = data_len
; ---------------------------------------------------------------------------
global clipboard_set
clipboard_set:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check size limit
    cmp r15, CLIPBOARD_MAX_SIZE
    ja .too_large

    ; Get clipboard
    mov rbx, [rbx + Server.clipboard]
    test rbx, rbx
    jz .fail

    ; Free old data
    mov rax, [rbx + Clipboard.data]
    test rax, rax
    jz .no_old_data
    ; TODO: Free old data via arena

.no_old_data:
    ; Allocate new data
    mov rdi, [r12 + Server.arena]
    mov rsi, r15
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Copy data
    mov rdi, rax
    mov rsi, r8
    mov rcx, r9
    call memcopy

    ; Copy mime type
    mov rdi, [r12 + Server.arena]
    mov rsi, r14
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax
    mov rdi, rax
    mov rsi, r13
    mov rcx, r14
    call memcopy

    ; Update clipboard
    mov rax, [rdi + Server.clipboard]
    mov qword [rax + Clipboard.data], rbx
    mov qword [rax + Clipboard.data_len], r15
    mov qword [rax + Clipboard.mime_type], r12
    mov qword [rax + Clipboard.mime_type_len], r14
    mov qword [rax + Clipboard.source_client], rdi
    inc qword [rax + Clipboard.serial]

    ; Send clipboard event to interested clients
    call clipboard_send_event

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.too_large:
    mov rax, -(ECLIP_SIZE)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; clipboard_get
;   Get clipboard data
; ---------------------------------------------------------------------------
global clipboard_get
clipboard_get:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get clipboard
    mov rax, [rbx + Server.clipboard]
    test rax, rax
    jz .empty

    ; Check mime type match
    mov r12, [rax + Clipboard.mime_type]
    mov r13, [rax + Clipboard.mime_type_len]
    ; TODO: Check if requested mime matches

    ; Return data
    mov rax, [rax + Clipboard.data]
    mov rdx, [rax + Clipboard.data_len]
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.empty:
    xor rax, rax
    xor rdx, rdx
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; clipboard_get_mimes
;   Get offered mime types
; ---------------------------------------------------------------------------
global clipboard_get_mimes
clipboard_get_mimes:
    PROLOGUE
    ; TODO: Return list of offered mime types
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; clipboard_send_event
; ---------------------------------------------------------------------------
clipboard_send_event:
    PROLOGUE
    ; TODO: Send clipboard event to clients with cw_data capability
    leave
    ret

section .data
global clipboard_version
clipboard_version: dq 0x010000
