; ============================================================================
; Greeter — the Login Screen
; ============================================================================
; A client of the server like any other, on a channel pair inside canvasd,
; since other programs cannot connect yet (KRN-03). It covers the first
; output with one surface holding a password field: a dot for each character
; typed, Backspace takes one back, Esc clears the field, Enter hands what was
; typed to the verify hook. A wrong password clears the field and turns its
; edge red; with no hook every password is wrong. What is typed is wiped once
; it has been checked.
;
; The server calls greeter_step once a turn, after input: the greeter reads
; what came in, and what it sends is served in the same turn. It needs three
; turns to show: the buffer, the surface, then the first commit. Text labels
; wait for fonts to load (ufont needs the file system).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/greeter.inc"

extern arena_alloc
extern client_accept
extern msgbuf_read
extern msgbuf_write

; Requests (proto/canvas-core.cwp) and the cw_keyboard events read
%define OP_BUFFER_CREATE    0
%define OP_SURFACE_CREATE   0
%define OP_SURFACE_DESTROY  1
%define OP_SURFACE_ATTACH   2
%define OP_SURFACE_DAMAGE   3
%define OP_SURFACE_COMMIT   12
%define EV_KEY              2
%define EV_TEXT             4

; Keys acted on
%define KEY_ESC             1
%define KEY_BACKSPACE       14
%define KEY_ENTER           28
%define KEY_KP_ENTER        96


section .text

; ---------------------------------------------------------------------------
; greeter_start
;   Connect a greeter to the server and ask for its buffer
;   IN:  rdi = server*, rsi = arena*
;   OUT: rax = greeter*, -ENODEV with no output, -EINVAL if the output is
;        smaller than the field, other negative errors from connecting
; ---------------------------------------------------------------------------
global greeter_start
greeter_start:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov r12, rdi
    mov r13, rsi
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov rax, [r12 + Server.outputs]
    test rax, rax
    jz .no_output
    cmp dword [rax + Output.width], GREETER_FIELD_W
    jb .too_small
    cmp dword [rax + Output.height], GREETER_FIELD_H
    jb .too_small

    mov rdi, r13
    mov esi, Greeter_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, Greeter_size
    rep stosb

    mov [rbx + Greeter.server], r12
    mov rax, [r12 + Server.outputs]
    mov ecx, [rax + Output.width]
    mov [rbx + Greeter.width], ecx
    lea edx, [rcx * 4]
    mov [rbx + Greeter.stride], edx
    sub ecx, GREETER_FIELD_W
    shr ecx, 1
    mov [rbx + Greeter.field_x], ecx
    mov ecx, [rax + Output.height]
    mov [rbx + Greeter.height], ecx
    sub ecx, GREETER_FIELD_H
    shr ecx, 1
    mov [rbx + Greeter.field_y], ecx

    mov rdi, r12
    lea rsi, [rbx + Greeter.pair]
    xor edx, edx
    call client_accept
    test rax, rax
    js .out

    ; create(width, height, format, flags, modifier) -> (buffer, pixels)
    mov eax, [rbx + Greeter.width]
    mov [rbx + Greeter.out_msg], eax
    mov eax, [rbx + Greeter.height]
    mov [rbx + Greeter.out_msg + 4], eax
    mov dword [rbx + Greeter.out_msg + 8], DRM_FORMAT_BGR8888
    mov dword [rbx + Greeter.out_msg + 12], 0
    mov qword [rbx + Greeter.out_msg + 16], 0
    mov rdi, rbx
    mov esi, CWP_OBJ_BUFFER
    mov edx, OP_BUFFER_CREATE
    mov ecx, 24
    call send
    test rax, rax
    js .out
    mov dword [rbx + Greeter.state], GREETER_WAIT_BUFFER
    mov [r12 + Server.greeter], rbx
    mov rax, rbx
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.no_output:
    mov rax, -(ENODEV)
    jmp .out
.too_small:
    mov rax, -(EINVAL)
    jmp .out
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; greeter_set_verify
;   The function Enter hands the typed text to
;   IN:  rdi = greeter*, rsi = function(rdi = text, esi = length) -> rax 0
;        if right, or 0 for none
; ---------------------------------------------------------------------------
global greeter_set_verify
greeter_set_verify:
    mov [rdi + Greeter.verify], rsi
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; greeter_done
;   IN:  rdi = greeter*  OUT: rax = 1 once a password was accepted, else 0
; ---------------------------------------------------------------------------
global greeter_done
greeter_done:
    xor eax, eax
    cmp dword [rdi + Greeter.state], GREETER_DONE
    sete al
    ret

; ---------------------------------------------------------------------------
; greeter_step
;   Everything that came in, then a commit if the field changed
;   IN:  rdi = greeter*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global greeter_step
greeter_step:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
.next:
    mov rdi, [rbx + Greeter.pair + ChannelPair.server_to_client]
    lea rsi, [rbx + Greeter.in_hdr]
    lea rdx, [rbx + Greeter.in_msg]
    mov ecx, GREETER_MSG_MAX
    call msgbuf_read
    test rax, rax
    js .read_all
    test word [rbx + Greeter.in_hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jnz .reply
    cmp dword [rbx + Greeter.state], GREETER_SHOWN
    jne .next                           ; typing counts only while shown
    cmp dword [rbx + Greeter.in_hdr + MsgHdr.obj], CWP_OBJ_KEYBOARD
    jne .next
    movzx eax, word [rbx + Greeter.in_hdr + MsgHdr.opcode]
    cmp eax, EV_TEXT
    je .text
    cmp eax, EV_KEY
    jne .next

    ; key(time, surface, keycode, state): presses and repeats
    cmp dword [rbx + Greeter.in_msg + 16], 0
    je .next
    mov eax, [rbx + Greeter.in_msg + 12]
    cmp eax, KEY_BACKSPACE
    je .backspace
    cmp eax, KEY_ESC
    je .clear
    cmp eax, KEY_ENTER
    je .submit
    cmp eax, KEY_KP_ENTER
    je .submit
    jmp .next
.backspace:
    mov eax, [rbx + Greeter.len]
    test eax, eax
    jz .next
    dec eax
    mov [rbx + Greeter.len], eax
    mov byte [rbx + Greeter.text + rax], 0
    jmp .changed
.clear:
    mov rdi, rbx
    call wipe
    jmp .changed
.submit:
    mov rax, [rbx + Greeter.verify]
    test rax, rax
    jz .wrong
    lea rdi, [rbx + Greeter.text]
    mov esi, [rbx + Greeter.len]
    call rax
    mov r12, rax
    mov rdi, rbx
    call wipe
    test r12, r12
    jnz .wrong_wiped
    mov dword [rbx + Greeter.state], GREETER_DONE
    mov eax, [rbx + Greeter.surface]    ; the session takes the screen
    mov [rbx + Greeter.out_msg], eax
    mov rdi, rbx
    mov esi, CWP_OBJ_SURFACE
    mov edx, OP_SURFACE_DESTROY
    mov ecx, 4
    call send
    jmp .next
.wrong:
    mov rdi, rbx
    call wipe
.wrong_wiped:
    mov dword [rbx + Greeter.failed], 1
    mov dword [rbx + Greeter.dirty], 1
    jmp .next

    ; text(time, surface, codepoint, modifiers): printable ASCII, the US keymap's
.text:
    mov eax, [rbx + Greeter.in_msg + 12]
    cmp eax, 0x20
    jb .next
    cmp eax, 0x7E
    ja .next
    mov ecx, [rbx + Greeter.len]
    cmp ecx, GREETER_MAX
    jae .next
    mov [rbx + Greeter.text + rcx], al
    inc ecx
    mov [rbx + Greeter.len], ecx
.changed:
    mov dword [rbx + Greeter.failed], 0
    mov dword [rbx + Greeter.dirty], 1
    jmp .next

    ; Replies come in the order of the requests that asked for them
.reply:
    cmp dword [rbx + Greeter.state], GREETER_WAIT_BUFFER
    je .got_buffer
    cmp dword [rbx + Greeter.state], GREETER_WAIT_SURFACE
    je .got_surface
    jmp .next
.got_buffer:
    mov eax, [rbx + Greeter.in_msg]
    mov [rbx + Greeter.buffer], eax
    mov rax, [rbx + Greeter.in_msg + 8]
    mov [rbx + Greeter.pixels], rax
    mov rdi, rbx
    mov esi, CWP_OBJ_SURFACE
    mov edx, OP_SURFACE_CREATE
    xor ecx, ecx
    call send
    mov dword [rbx + Greeter.state], GREETER_WAIT_SURFACE
    jmp .next
.got_surface:
    mov eax, [rbx + Greeter.in_msg]
    mov [rbx + Greeter.surface], eax
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    mov ecx, [rbx + Greeter.width]
    mov r8d, [rbx + Greeter.height]
    mov r9d, GREETER_BG
    call fill
    mov rdi, rbx
    call draw_field
    ; attach(surface, buffer, x, y, acquire, release)
    mov eax, [rbx + Greeter.surface]
    mov [rbx + Greeter.out_msg], eax
    mov eax, [rbx + Greeter.buffer]
    mov [rbx + Greeter.out_msg + 4], eax
    mov qword [rbx + Greeter.out_msg + 8], 0
    mov qword [rbx + Greeter.out_msg + 16], 0
    mov rdi, rbx
    mov esi, CWP_OBJ_SURFACE
    mov edx, OP_SURFACE_ATTACH
    mov ecx, 24
    call send
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    mov ecx, [rbx + Greeter.width]
    mov r8d, [rbx + Greeter.height]
    call damage_commit
    mov dword [rbx + Greeter.state], GREETER_SHOWN
    mov dword [rbx + Greeter.dirty], 0
    jmp .next

.read_all:
    cmp dword [rbx + Greeter.state], GREETER_SHOWN
    jne .done
    cmp dword [rbx + Greeter.dirty], 0
    je .done
    mov dword [rbx + Greeter.dirty], 0
    mov rdi, rbx
    call draw_field
    mov rdi, rbx
    mov esi, [rbx + Greeter.field_x]
    mov edx, [rbx + Greeter.field_y]
    mov ecx, GREETER_FIELD_W
    mov r8d, GREETER_FIELD_H
    call damage_commit
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; The field as it stands: edge, inside, a dot per character up to
; GREETER_DOTS, and the caret after the last while there is room.
; rdi = greeter
draw_field:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov esi, [rbx + Greeter.field_x]
    mov edx, [rbx + Greeter.field_y]
    mov ecx, GREETER_FIELD_W
    mov r8d, GREETER_FIELD_H
    mov r9d, GREETER_BORDER
    cmp dword [rbx + Greeter.failed], 0
    je .edge
    mov r9d, GREETER_FAILED
.edge:
    call fill
    mov rdi, rbx
    mov esi, [rbx + Greeter.field_x]
    add esi, GREETER_EDGE
    mov edx, [rbx + Greeter.field_y]
    add edx, GREETER_EDGE
    mov ecx, GREETER_FIELD_W - 2 * GREETER_EDGE
    mov r8d, GREETER_FIELD_H - 2 * GREETER_EDGE
    mov r9d, GREETER_FIELD
    call fill

    mov r12d, [rbx + Greeter.len]
    cmp r12d, GREETER_DOTS
    jbe .counted
    mov r12d, GREETER_DOTS
.counted:
    xor r13d, r13d
.dot:
    cmp r13d, r12d
    jae .caret
    mov rdi, rbx
    imul esi, r13d, GREETER_DOT_STEP
    add esi, [rbx + Greeter.field_x]
    add esi, GREETER_PAD
    mov edx, [rbx + Greeter.field_y]
    add edx, (GREETER_FIELD_H - GREETER_DOT) / 2
    mov ecx, GREETER_DOT
    mov r8d, GREETER_DOT
    mov r9d, GREETER_INK
    call fill
    inc r13d
    jmp .dot
.caret:
    cmp r12d, GREETER_DOTS
    jae .out
    mov rdi, rbx
    imul esi, r12d, GREETER_DOT_STEP
    add esi, [rbx + Greeter.field_x]
    add esi, GREETER_PAD
    mov edx, [rbx + Greeter.field_y]
    add edx, (GREETER_FIELD_H - GREETER_CARET_H) / 2
    mov ecx, GREETER_CARET_W
    mov r8d, GREETER_CARET_H
    mov r9d, GREETER_INK
    call fill
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; A rectangle of one colour, inside the buffer.
; rdi = greeter, esi = x, edx = y, ecx = width, r8d = height, r9d = colour
fill:
    mov eax, r9d
    mov r9d, ecx
    mov r10, [rdi + Greeter.pixels]
    mov r11d, [rdi + Greeter.stride]
    mov edx, edx
    imul rdx, r11
    add r10, rdx
    mov esi, esi
    lea r10, [r10 + rsi * 4]
.row:
    mov rdi, r10
    mov ecx, r9d
    rep stosd
    add r10, r11
    dec r8d
    jnz .row
    ret

; damage(surface, rect) then commit(surface, 0).
; rdi = greeter, esi = x, edx = y, ecx = width, r8d = height
damage_commit:
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov eax, [rbx + Greeter.surface]
    mov [rbx + Greeter.out_msg], eax
    mov [rbx + Greeter.out_msg + 4], esi
    mov [rbx + Greeter.out_msg + 8], edx
    mov [rbx + Greeter.out_msg + 12], ecx
    mov [rbx + Greeter.out_msg + 16], r8d
    mov esi, CWP_OBJ_SURFACE
    mov edx, OP_SURFACE_DAMAGE
    mov ecx, 20
    call send
    mov rdi, rbx
    mov dword [rbx + Greeter.out_msg + 4], 0
    mov esi, CWP_OBJ_SURFACE
    mov edx, OP_SURFACE_COMMIT
    mov ecx, 8
    call send
    add rsp, 8
    EPILOGUE_RESTORE rbx

; Forget what was typed, every byte of it.
; rdi = greeter
wipe:
    mov dword [rdi + Greeter.len], 0
    lea rdi, [rdi + Greeter.text]
    xor eax, eax
    mov ecx, GREETER_MAX
    rep stosb
    ret

; A request from Greeter.out_msg.
; rdi = greeter, esi = interface, edx = opcode, ecx = payload length
; -> rax from msgbuf_write
send:
    lea rax, [rdi + Greeter.out_hdr]
    mov [rax + MsgHdr.obj], esi
    mov [rax + MsgHdr.opcode], dx
    mov word [rax + MsgHdr.flags], 0
    mov [rax + MsgHdr.len], ecx
    lea rdx, [rdi + Greeter.out_msg]
    mov rsi, rax
    mov rdi, [rdi + Greeter.pair + ChannelPair.client_to_server]
    jmp msgbuf_write

section .data
global greeter_version
greeter_version: dq 0x010000
