; ============================================================================
; Client Clipboard Helpers — set/get Clipboard + Selection
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

global canvas_clipboard_set
canvas_clipboard_set:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; rsi=mime, rdx=mime_len, rcx=data, r8=data_len
    ; TODO: send cw_data.set_selection
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

global canvas_clipboard_get
canvas_clipboard_get:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; TODO: request cw_data.receive, block on reply
    xor rax, rax
    xor rdx, rdx
    EPILOGUE_RESTORE rbx
    ret

global canvas_clipboard_clear
canvas_clipboard_clear:
    PROLOGUE
    xor rax, rax
    leave
    ret

global canvas_selection_set
canvas_selection_set:
    PROLOGUE
    xor rax, rax
    leave
    ret

global canvas_selection_get
canvas_selection_get:
    PROLOGUE
    xor rax, rax
    xor rdx, rdx
    leave
    ret

section .data
global canvas_clipboard_helpers_version
canvas_clipboard_helpers_version: dq 0x010000
