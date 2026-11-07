; ============================================================================
; Client Clipboard Helpers — cw_clipboard requests
; ============================================================================
; Every function takes rdi = conn and leaves it unchanged for the next call.
; A selection is 0 (the clipboard) or 1 (the primary selection); a type is a
; NUL-terminated name of fewer than 32 bytes. What comes back arrives as
; events (CANVAS_EV_CLIPBOARD_*): offered when the client gets the keyboard
; or the offer changes, send when a paste wants this client's data, data
; and cancelled for a paste of its own. Only the client with the keyboard
; may offer or paste.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

extern canvas_call
extern canvas_send

%define TYPE_LEN    32
%define TYPES       4
%define CHUNK       120

section .text

; ---------------------------------------------------------------------------
; canvas_clipboard_offer
;   This client has the selection's data in these types, and owns it
;   IN:  rdi = conn, esi = selection, edx = how many types (up to 4),
;        rcx = the types, 32 bytes each
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_clipboard_offer
canvas_clipboard_offer:
    sub rsp, 8 + TYPES * TYPE_LEN + 16  ; the request; 16-byte aligned
    mov rax, -(EINVAL)
    cmp edx, TYPES
    ja .out
    push rdi
    mov [rsp + 8], esi
    mov [rsp + 12], edx
    lea rdi, [rsp + 16]                 ; the types, then nothing after them
    mov rsi, rcx
    mov ecx, edx
    shl ecx, 5
    rep movsb
    mov ecx, TYPES
    sub ecx, edx
    shl ecx, 5
    xor eax, eax
    rep stosb
    pop rdi
    mov esi, CWP_OBJ_CLIPBOARD
    mov edx, CLIPBOARD_OFFER
    mov rcx, rsp
    mov r8d, 8 + TYPES * TYPE_LEN
    call canvas_send
.out:
    add rsp, 8 + TYPES * TYPE_LEN + 16
    ret

; ---------------------------------------------------------------------------
; canvas_clipboard_receive
;   A paste: the selection's data in one of the types offered, to come as
;   data events with the serial this returns
;   IN:  rdi = conn, esi = selection, rdx = the type (NUL-terminated)
;   OUT: rax = the paste's serial, negative error
; ---------------------------------------------------------------------------
global canvas_clipboard_receive
canvas_clipboard_receive:
    push rbx
    sub rsp, 48                         ; the request; 16-byte aligned
    mov rbx, rdi
    mov [rsp], esi
    lea rdi, [rsp + 4]
    xor eax, eax
    mov ecx, TYPE_LEN
    rep stosb
    xor ecx, ecx                        ; the type, up to its NUL
.copy:
    mov al, [rdx + rcx]
    test al, al
    jz .copied
    mov [rsp + 4 + rcx], al
    inc ecx
    cmp ecx, TYPE_LEN - 1
    jb .copy
.copied:
    mov rdi, rbx
    mov esi, CWP_OBJ_CLIPBOARD
    mov edx, CLIPBOARD_RECEIVE
    mov rcx, rsp
    mov r8d, 4 + TYPE_LEN
    call canvas_call
    test rax, rax
    js .out
    mov eax, [rbx + CLIENT_WIRE + ClientWire.reply]
.out:
    add rsp, 48
    pop rbx
    ret

; ---------------------------------------------------------------------------
; canvas_clipboard_send
;   This client's data for a paste it was asked for (a send event), in as
;   many data requests as it takes, the last done
;   IN:  rdi = conn, esi = the paste's serial, rdx = data, rcx = its length
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_clipboard_send
canvas_clipboard_send:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 12 + CHUNK + 12            ; a request; 16-byte aligned
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
.chunk:
    mov [rsp], r12d
    mov ecx, r14d
    xor eax, eax
    cmp r14, CHUNK
    jbe .last
    mov ecx, CHUNK
    jmp .sized
.last:
    mov eax, 1
.sized:
    mov [rsp + 4], eax
    mov [rsp + 8], ecx
    sub r14, rcx
    lea rdi, [rsp + 12]
    mov rsi, r13
    add r13, rcx
    mov r8d, ecx
    rep movsb
    mov rdi, rbx
    mov esi, CWP_OBJ_CLIPBOARD
    mov edx, CLIPBOARD_DATA
    mov rcx, rsp
    add r8d, 12
    call canvas_send
    test rax, rax
    js .out
    cmp dword [rsp + 4], 0
    je .chunk
    xor eax, eax
.out:
    add rsp, 12 + CHUNK + 12
    EPILOGUE_RESTORE rbx, r12, r13, r14

section .data
global canvas_clipboard_helpers_version
canvas_clipboard_helpers_version: dq 0x020000
