; ============================================================================
; Client Clipboard Helpers — set/get Clipboard + Selection
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

%define CLIENT_CLIP_LEN       88
%define CLIENT_CLIP_MIME_LEN  96
%define CLIENT_CLIP_MIME      8192
%define CLIENT_CLIP_DATA      8448
%define CLIENT_CLIP_MAX       16384
%define CLIENT_SEL_LEN        24832
%define CLIENT_SEL_MIME_LEN   24840
%define CLIENT_SEL_MIME       24848
%define CLIENT_SEL_DATA       25104

global canvas_clipboard_set
canvas_clipboard_set:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rcx
    mov r13, r8
    ASSERT_PTR rbx
    test rsi, rsi
    jz .set_invalid
    test rcx, rcx
    jz .set_invalid
    cmp rdx, 255
    ja .set_invalid
    cmp r8, CLIENT_CLIP_MAX
    ja .set_large
    mov [rbx + CLIENT_CLIP_MIME_LEN], rdx
    mov [rbx + CLIENT_CLIP_LEN], r13
    lea rdi, [rbx + CLIENT_CLIP_MIME]
    call memcopy
    lea rdi, [rbx + CLIENT_CLIP_DATA]
    mov rsi, r12
    mov rdx, r13
    call memcopy
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.set_invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.set_large:
    mov rax, -(E2BIG)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

global canvas_clipboard_get
canvas_clipboard_get:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rdx, [rbx + CLIENT_CLIP_LEN]
    test rdx, rdx
    jz .get_none
    lea rax, [rbx + CLIENT_CLIP_DATA]
    EPILOGUE_RESTORE rbx
    ret
.get_none:
    xor eax, eax
    EPILOGUE_RESTORE rbx
    ret

global canvas_clipboard_clear
canvas_clipboard_clear:
    PROLOGUE
    mov qword [rdi + CLIENT_CLIP_LEN], 0
    mov qword [rdi + CLIENT_CLIP_MIME_LEN], 0
    xor rax, rax
    leave
    ret

global canvas_selection_set
canvas_selection_set:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rcx
    mov r13, r8
    cmp rdx, 255
    ja .selection_bad
    cmp r8, CLIENT_CLIP_MAX
    ja .selection_bad
    mov [rbx + CLIENT_SEL_MIME_LEN], rdx
    mov [rbx + CLIENT_SEL_LEN], r13
    lea rdi, [rbx + CLIENT_SEL_MIME]
    call memcopy
    lea rdi, [rbx + CLIENT_SEL_DATA]
    mov rsi, r12
    mov rdx, r13
    call memcopy
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.selection_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

global canvas_selection_get
canvas_selection_get:
    PROLOGUE
    mov rdx, [rdi + CLIENT_SEL_LEN]
    test rdx, rdx
    jz .selection_none
    lea rax, [rdi + CLIENT_SEL_DATA]
    leave
    ret
.selection_none:
    xor eax, eax
    leave
    ret

section .data
global canvas_clipboard_helpers_version
canvas_clipboard_helpers_version: dq 0x010000
