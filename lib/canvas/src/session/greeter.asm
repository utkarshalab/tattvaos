; ============================================================================
; Greeter — the Login Screen
; ============================================================================
; A client of the server through the client library, on a channel pair inside
; canvasd, since other programs cannot connect yet (KRN-03). It is an overlay
; layer over the whole first output holding a password field: a dot for each
; character typed, Backspace takes one back (and repeats), Esc clears the
; field, Enter hands what was typed to the verify hook. A wrong password
; clears the field and turns its edge red; with no hook every password is
; wrong. What is typed is wiped once it has been checked.
;
; greeter_start makes the buffer and the surface with library calls, which
; turn server_poll while they wait, so it is called outside the loop's turn;
; canvasd's loop calls greeter_step after each server_poll, and what it
; sends is served in the next turn. Text labels wait for fonts to load (ufont
; needs the file system).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/backend.inc"
%include "inc/canvas_client.inc"
%include "inc/greeter.inc"

extern arena_alloc
extern canvas_buffer_create
extern canvas_buffer_mmap
extern canvas_connect_pair
extern canvas_event_poll
extern canvas_layer_create
extern canvas_surface_attach
extern canvas_surface_commit
extern canvas_surface_create
extern canvas_surface_damage
extern canvas_surface_destroy
extern client_accept
extern server_poll

; Keys acted on
%define KEY_ESC             1
%define KEY_BACKSPACE       14
%define KEY_ENTER           28
%define KEY_KP_ENTER        96

; An input event's (time, surface, a, b): a and b
%define EV_A                (Greeter.event + ClientEvent.data + 12)
%define EV_B                (Greeter.event + ClientEvent.data + 16)

section .text

; ---------------------------------------------------------------------------
; greeter_start
;   Connect a greeter and show it
;   IN:  rdi = server*, rsi = arena*
;   OUT: rax = greeter*, -ENODEV with no output, -EINVAL if the output is
;        smaller than the field, -ENOMEM, other negative errors from the
;        server
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

    ; Connected, with the server turning while a call waits
    mov rdi, r12
    lea rsi, [rbx + Greeter.pair]
    mov edx, CLIENT_CAP_LAYER
    call client_accept
    test rax, rax
    js .out
    lea rdi, [rbx + Greeter.pair]
    lea rsi, [rel server_poll]
    mov rdx, r12
    call canvas_connect_pair
    test rax, rax
    jz .oom
    mov [rbx + Greeter.conn], rax

    ; Its buffer, its surface, an overlay over everything
    mov rdi, rax
    mov esi, [rbx + Greeter.width]
    mov edx, [rbx + Greeter.height]
    mov ecx, DRM_FORMAT_BGR8888
    call canvas_buffer_create
    test rax, rax
    js .out
    mov [rbx + Greeter.buffer], eax
    mov rdi, [rbx + Greeter.conn]
    mov esi, eax
    call canvas_buffer_mmap
    mov [rbx + Greeter.pixels], rax
    mov rdi, [rbx + Greeter.conn]
    call canvas_surface_create
    test rax, rax
    js .out
    mov [rbx + Greeter.surface], eax
    mov rdi, [rbx + Greeter.conn]
    mov esi, eax
    mov edx, CANVAS_LAYER_OVERLAY
    mov ecx, CANVAS_ANCHOR_ALL
    xor r8d, r8d
    call canvas_layer_create
    test rax, rax
    js .out

    ; Drawn and shown
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    mov ecx, [rbx + Greeter.width]
    mov r8d, [rbx + Greeter.height]
    mov r9d, GREETER_BG
    call fill
    mov rdi, rbx
    call draw_field
    mov rdi, [rbx + Greeter.conn]
    mov esi, [rbx + Greeter.surface]
    mov edx, [rbx + Greeter.buffer]
    xor ecx, ecx
    xor r8d, r8d
    call canvas_surface_attach
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    mov ecx, [rbx + Greeter.width]
    mov r8d, [rbx + Greeter.height]
    call damage_commit
    mov dword [rbx + Greeter.state], GREETER_SHOWN
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
;   Every event that came in, then a commit if the field changed
;   IN:  rdi = greeter*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global greeter_step
greeter_step:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    cmp dword [rbx + Greeter.state], GREETER_SHOWN
    jne .done
.next:
    mov rdi, [rbx + Greeter.conn]
    lea rsi, [rbx + Greeter.event]
    call canvas_event_poll
    test eax, eax
    jz .read_all
    cmp dword [rbx + Greeter.state], GREETER_SHOWN
    jne .next                           ; done: what is left goes unread
    mov eax, [rbx + Greeter.event + ClientEvent.type]
    cmp eax, CANVAS_EV_TEXT
    je .text
    cmp eax, CANVAS_EV_KEY
    jne .next

    ; key(time, surface, keycode, state): presses and repeats
    cmp dword [rbx + EV_B], 0
    je .next
    mov eax, [rbx + EV_A]
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
    mov rdi, [rbx + Greeter.conn]       ; the session takes the screen
    mov esi, [rbx + Greeter.surface]
    call canvas_surface_destroy
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
    mov eax, [rbx + EV_A]
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
    mov r9d, r8d
    mov r8d, ecx
    mov ecx, edx
    mov edx, esi
    mov rdi, [rbx + Greeter.conn]
    mov esi, [rbx + Greeter.surface]
    call canvas_surface_damage
    mov rdi, [rbx + Greeter.conn]
    mov esi, [rbx + Greeter.surface]
    xor edx, edx
    call canvas_surface_commit
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

section .data
global greeter_version
greeter_version: dq 0x020000
