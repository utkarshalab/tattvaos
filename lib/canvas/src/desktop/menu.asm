; ============================================================================
; Menus — the Power Menu and the App Launcher
; ============================================================================
; Two menus the server draws itself, over everything, as it draws Alt+Tab;
; one open at a time, never while the login screen is up. While one is open
; every key press is the menu's: Up and Down move the selection, Enter acts
; on it, Esc closes.
;
; The power menu (DSK-06), Ctrl+Alt+Delete or the power key: Lock, Switch
; user, Sleep, Restart, Shut down. Lock puts the login screen up; Switch user
; does too, for its row of names (a session for each user comes later);
; Sleep puts it up and asks the kernel to suspend (ut_power_suspend);
; Restart and Shut down ask the kernel (ut_power_restart, ut_power_off).
; Server.power_last keeps the last choice.
;
; The launcher (DSK-07), Super+Space: a search line, then the apps whose
; names hold what was typed, any case, in the order they came, up to eight
; at a time. Typing adds to the search, Backspace takes off its last
; character; Enter starts the app selected (ut_app_launch with its name) and
; closes. The apps come from the kernel the first time it opens
; (ut_app_list: each name followed by a NUL) and from launcher_add_app.
; Server.launches counts the starts, Server.launch_last is the last one's
; place in the list, plus 1.
;
; The kernel's calls are weak imports: without them Sleep only locks,
; Restart and Shut down do nothing, and the launcher lists what was added.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/render.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/ui_text.inc"

extern compositor_output_at
extern rect_intersect
extern region_add_rect
extern sw_render_rect
extern frame_text
extern greeter_lock
extern ut_power_suspend
extern ut_power_restart
extern ut_power_off
extern ut_app_list
extern ut_app_launch

%define KEY_ESC         1               ; keycodes
%define KEY_BACKSPACE   14
%define KEY_ENTER       28
%define KEY_UP          103
%define KEY_DOWN        108

%define MENU_NONE       0
%define MENU_POWER      1
%define MENU_LAUNCHER   2
%define POWER_ROWS      5
%define LAUNCHER_ROWS   8               ; matches shown, under the search
%define MENU_W          240
%define ROW_H           20
%define PAD             8
%define TEXT_SIZE       13
%define QUERY_MAX       31
%define BOX_COLOR       0xFF181C28
%define FIELD_COLOR     0xFF2C3248
%define SELECTED_COLOR  0xFF3E4C78
%define TEXT_COLOR      0xD0D4E0
%define HINT_COLOR      0x7880A0
%define HC_BOX          0xFF000000      ; high contrast: black, white text,
%define HC_SELECTED     0xFFFFFF00      ; the selection yellow with black
%define HC_TEXT         0xFFFFFF
%define HC_TEXT_SELECTED 0x000000

section .text

; ---------------------------------------------------------------------------
; power_menu_open / launcher_open
;   Open a menu on the output the pointer is on
;   IN:  rdi = server*
;   OUT: rax = 0, -EBUSY with a menu open or the login screen up
; ---------------------------------------------------------------------------
global power_menu_open
power_menu_open:
    mov esi, MENU_POWER
    jmp open

global launcher_open
launcher_open:
    mov esi, MENU_LAUNCHER
    jmp open

; ---------------------------------------------------------------------------
; menu_close
;   Close the menu open, if any
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global menu_close
menu_close:
    cmp dword [rel kind], MENU_NONE
    je .out
    sub rsp, 8
    call damage_box
    add rsp, 8
    mov dword [rel kind], MENU_NONE
.out:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; menu_open_kind
;   OUT: eax = 0 no menu, 1 the power menu, 2 the launcher
; ---------------------------------------------------------------------------
global menu_open_kind
menu_open_kind:
    mov eax, [rel kind]
    ret

; ---------------------------------------------------------------------------
; menu_key
;   A key press, while a menu is open, is the menu's
;   IN:  rdi = server*, esi = keycode, edx = the character it types (0: none)
;   OUT: eax = 1 taken, 0 no menu open or a modifier (Shift, Ctrl, Alt,
;        Super, the locks), which the seat keeps as ever
; ---------------------------------------------------------------------------
global menu_key
menu_key:
    xor eax, eax
    cmp dword [rel kind], MENU_NONE
    je .none
    cmp [rel server_p], rdi
    je .ours
    mov dword [rel kind], MENU_NONE     ; another server's: forgotten
    ret
.ours:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    cmp qword [rbx + Server.locked], 0
    je .open
    call menu_close                     ; the login screen's keys are its own
    xor eax, eax
    jmp .out
.open:
    lea rcx, [rel modifier_keys]        ; modifiers stay the seat's: a held
    xor eax, eax                        ; Shift must still shift
.modifier:
    cmp esi, [rcx + rax * 4]
    je .not_taken
    inc eax
    cmp eax, MODIFIER_KEYS
    jb .modifier
    cmp esi, KEY_ESC
    je .close
    cmp esi, KEY_UP
    je .up
    cmp esi, KEY_DOWN
    je .down
    cmp esi, KEY_ENTER
    je .enter
    cmp dword [rel kind], MENU_LAUNCHER
    jne .taken
    cmp esi, KEY_BACKSPACE
    je .back
    cmp edx, ' '                        ; a printable character to the search
    jb .taken
    cmp edx, '~'
    ja .taken
    mov eax, [rel query_len]
    cmp eax, QUERY_MAX
    jae .taken
    lea rcx, [rel query]
    mov [rcx + rax], dl
    inc dword [rel query_len]
    jmp .search
.back:
    cmp dword [rel query_len], 0
    je .taken
    dec dword [rel query_len]
.search:
    call filter
    jmp .changed
.up:
    cmp dword [rel selected], 0
    je .taken
    dec dword [rel selected]
    jmp .changed
.down:
    call rows_selectable
    mov ecx, [rel selected]
    inc ecx
    cmp ecx, eax
    jae .taken
    mov [rel selected], ecx
.changed:
    mov rdi, rbx
    call damage_box
    jmp .taken
.close:
    mov rdi, rbx
    call menu_close
    jmp .taken
.enter:
    mov rdi, rbx
    call act
.taken:
    mov eax, 1
    jmp .out
.not_taken:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12
.none:
    ret

; ---------------------------------------------------------------------------
; launcher_add_app
;   An app for the launcher to list
;   IN:  rdi = server*, rsi = its name (UTF-8), edx = its length
;   OUT: rax = 0, -EINVAL for an empty name or one past APP_NAME_MAX bytes,
;        -ENOSPC with APPS_MAX listed
; ---------------------------------------------------------------------------
global launcher_add_app
launcher_add_app:
    mov rax, -(EINVAL)
    test edx, edx
    jz .out
    cmp edx, APP_NAME_MAX
    ja .out
    mov rax, -(ENOSPC)
    mov rcx, [rdi + Server.app_count]
    cmp rcx, APPS_MAX
    jae .out
    inc qword [rdi + Server.app_count]
    shl rcx, 5                          ; App_size 32: a length, the name
    lea rdi, [rdi + Server.apps + rcx]
    mov [rdi], dl
    inc rdi
    mov ecx, edx
    rep movsb
    xor eax, eax
.out:
    ret

; ---------------------------------------------------------------------------
; menu_render
;   The open menu over a frame of its output
;   IN:  rdi = FrameCtx*, rsi = clip rect*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global menu_render
menu_render:
    cmp dword [rel kind], MENU_NONE
    je .idle
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 16                         ; a row
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rel output]
    cmp [rbx + FrameCtx.output], rax
    jne .out                            ; another output's frame
    mov rax, [rel server_p]
    cmp qword [rax + Server.locked], 0
    jne .out
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rel box]
    mov ecx, BOX_COLOR
    call contrast
    cmovnz ecx, [rel hc_box]
    call fill
    xor r13d, r13d
.row:
    call rows_shown
    cmp r13d, eax
    jae .out
    mov eax, [rel box]                  ; its place
    add eax, PAD
    mov [rsp], eax
    imul eax, r13d, ROW_H
    add eax, [rel box + 4]
    add eax, PAD
    mov [rsp + 4], eax
    mov dword [rsp + 8], MENU_W - 2 * PAD
    mov dword [rsp + 12], ROW_H
    cmp dword [rel kind], MENU_POWER
    je .power_row
    test r13d, r13d                     ; the launcher: the search first
    jnz .app_row
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rsp
    mov ecx, FIELD_COLOR
    call contrast
    cmovnz ecx, [rel hc_box]
    call fill
    lea rcx, [rel query]
    mov r8d, [rel query_len]
    mov r9d, TEXT_COLOR
    test r8d, r8d
    jnz .query
    lea rcx, [rel hint]
    mov r8d, hint_len
    mov r9d, HINT_COLOR
.query:
    call contrast
    cmovnz r9d, [rel hc_text]
    jmp .text
.app_row:
    lea r14d, [r13 - 1]
    cmp r14d, [rel match_count]
    jae .next
    mov eax, r14d
    call row_colour
    lea rax, [rel matches]
    mov eax, [rax + r14 * 4]
    shl eax, 5
    mov rcx, [rel server_p]
    lea rcx, [rcx + Server.apps + rax]
    movzx r8d, byte [rcx]
    inc rcx
    jmp .text
.power_row:
    mov eax, r13d
    call row_colour
    lea rax, [rel power_labels]
    mov rcx, [rax + r13 * 8]
    lea rax, [rel power_lengths]
    movzx r8d, byte [rax + r13]
.text:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rsp
    call text
.next:
    inc r13d
    jmp .row
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14
.idle:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; rdi = server, esi = kind: open it -> rax = 0, -EBUSY
open:
    mov rax, -(EBUSY)
    cmp dword [rel kind], MENU_NONE
    jne .out
    cmp qword [rdi + Server.locked], 0
    jne .out
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov [rel server_p], rdi
    mov [rel kind], esi
    mov dword [rel selected], 0
    mov dword [rel query_len], 0
    call pick_output
    cmp dword [rel kind], MENU_LAUNCHER
    jne .placed
    cmp qword [rbx + Server.apps_loaded], 0
    jne .loaded
    mov rdi, rbx
    call load_apps
.loaded:
    call filter
.placed:
    call place_box
    mov rdi, rbx
    call damage_box
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx
.out:
    ret

; rdi = server: the kernel's apps, once
load_apps:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov qword [rbx + Server.apps_loaded], 1
    lea rdi, [rel app_buf]
    mov esi, APP_BUF_SIZE
    call ut_app_list
    test rax, rax
    jle .out
    mov r12, rax                        ; names to go
    lea r13, [rel app_buf]
.name:
    test r12, r12
    jz .out
    lea rcx, [rel app_buf + APP_BUF_SIZE]
    mov rdx, r13
.end:
    cmp rdx, rcx
    jae .out                            ; no NUL: the rest dropped
    cmp byte [rdx], 0
    je .found
    inc rdx
    jmp .end
.found:
    push rdx
    push rdx                            ; 16-byte aligned
    mov rdi, rbx
    mov rsi, r13
    sub rdx, r13
    call launcher_add_app               ; too long or too many: left out
    pop rdx
    pop rdx
    lea r13, [rdx + 1]
    dec r12
    jmp .name
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; The apps whose names hold the search, any case, into matches; the first
; selected
filter:
    push rbx
    push r12
    push r13
    mov dword [rel match_count], 0
    mov dword [rel selected], 0
    mov rax, [rel server_p]
    mov r12, [rax + Server.app_count]
    lea r13, [rax + Server.apps]
    xor ebx, ebx
.app:
    cmp rbx, r12
    jae .out
    mov rdi, rbx
    shl rdi, 5
    add rdi, r13
    call holds
    test eax, eax
    jz .next
    mov eax, [rel match_count]
    lea rcx, [rel matches]
    mov [rcx + rax * 4], ebx
    inc dword [rel match_count]
.next:
    inc rbx
    jmp .app
.out:
    pop r13
    pop r12
    pop rbx
    ret

%macro LOWER 1                          ; an ASCII capital to small; esi used
    lea esi, [%1 - 'A']
    cmp esi, 'Z' - 'A'
    ja %%done
    or %1, 0x20
%%done:
%endmacro

; rdi = an app (its length, its name) -> eax = 1 if the name holds the
; search, ASCII letters in any case
holds:
    movzx r8d, byte [rdi]               ; the name's length
    inc rdi
    mov r9d, [rel query_len]
    mov eax, 1
    test r9d, r9d
    jz .out                             ; nothing typed: every app
    xor eax, eax
    sub r8d, r9d
    jb .out                             ; shorter than the search
    xor ecx, ecx                        ; where in the name
.start:
    cmp ecx, r8d
    ja .out
    xor edx, edx                        ; how far into the search
.char:
    cmp edx, r9d
    je .yes
    lea r10d, [rcx + rdx]
    movzx r10d, byte [rdi + r10]
    lea r11, [rel query]
    movzx r11d, byte [r11 + rdx]
    LOWER r10d
    LOWER r11d
    cmp r10d, r11d
    jne .move
    inc edx
    jmp .char
.move:
    inc ecx
    jmp .start
.yes:
    mov eax, 1
.out:
    ret

; rdi = server: Enter on the selection
act:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, [rel selected]
    cmp dword [rel kind], MENU_LAUNCHER
    je .launch
    call menu_close
    lea eax, [r12 + 1]
    mov [rbx + Server.power_last], rax
    cmp r12d, 2
    ja .restart
    mov rdi, [rbx + Server.greeter]     ; lock, switch user, sleep: the login
    test rdi, rdi                       ; screen up
    jz .locked
    call greeter_lock
.locked:
    cmp r12d, 2
    jne .out
    inc qword [rbx + Server.suspends]   ; and sleep
    call ut_power_suspend
    jmp .out
.restart:
    cmp r12d, 3
    jne .off
    call ut_power_restart
    jmp .out
.off:
    call ut_power_off
    jmp .out
.launch:
    cmp r12d, [rel match_count]
    jae .out                            ; nothing matches: stays open
    lea rax, [rel matches]
    mov r12d, [rax + r12 * 4]
    call menu_close
    inc qword [rbx + Server.launches]
    lea eax, [r12 + 1]
    mov [rbx + Server.launch_last], rax
    shl r12d, 5
    lea rdi, [rbx + Server.apps + r12 + 1]
    movzx esi, byte [rbx + Server.apps + r12]
    call ut_app_launch
.out:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; -> eax = the rows the selection moves over
rows_selectable:
    mov eax, POWER_ROWS
    cmp dword [rel kind], MENU_POWER
    je .out
    mov eax, [rel match_count]
.out:
    ret

; -> eax = the rows drawn: the power menu's five; the search and up to
; LAUNCHER_ROWS matches
rows_shown:
    mov eax, POWER_ROWS
    cmp dword [rel kind], MENU_POWER
    je .out
    mov eax, LAUNCHER_ROWS + 1
.out:
    ret

; -> ZF clear (nz) in high contrast; every register kept but the flags
contrast:
    push rax
    mov rax, [rel server_p]
    cmp qword [rax + Server.high_contrast], 0
    pop rax
    ret

; menu_render's row eax: the selected one painted; r9d = its text colour.
; Needs menu_render's rbx, r12 and its row at the caller's rsp + 8.
row_colour:
    mov r9d, TEXT_COLOR
    cmp eax, [rel selected]
    jne .plain
    push rcx                            ; 16-byte aligned
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rsp + 16]
    mov ecx, SELECTED_COLOR
    call contrast
    cmovnz ecx, [rel hc_selected]
    call fill
    pop rcx
    mov r9d, TEXT_COLOR
    call contrast
    cmovnz r9d, [rel hc_text_selected]
    ret
.plain:
    call contrast
    cmovnz r9d, [rel hc_text]
    ret

; rdi = frame, rsi = clip, rdx = rect, ecx = colour: the rect's part inside
; the clip painted
fill:
    sub rsp, 40                         ; the clipped part, frame, colour
    mov [rsp + 16], rdi
    mov [rsp + 24], ecx
    lea rdi, [rsp]
    mov rax, rsi
    mov rsi, rdx
    mov rdx, rax
    call rect_intersect
    test rax, rax
    jnz .out
    mov rdi, [rsp + 16]
    lea rsi, [rsp]
    mov edx, [rsp + 24]
    call sw_render_rect
.out:
    add rsp, 40
    ret

%define TEXT_FRAME (((UiText_size + 15) & ~15) + 8)   ; the UiText; aligned
; rdi = frame, rsi = clip, rdx = row rect, rcx = text, r8d = its length,
; r9d = colour: the text in the row, less a margin
text:
    test r8d, r8d
    jz .none
    sub rsp, TEXT_FRAME
    mov [rsp + UiText.text], rcx
    mov [rsp + UiText.length], r8d
    mov [rsp + UiText.colour], r9d
    mov dword [rsp + UiText.size], TEXT_SIZE
    mov rax, [rdi + FrameCtx.framebuffer]
    mov [rsp + UiText.pixels], rax
    mov rax, [rdi + FrameCtx.stride]
    mov [rsp + UiText.stride], rax
    mov eax, [rdx]
    add eax, PAD
    mov [rsp + UiText.x], eax
    mov eax, [rdx + 4]
    mov [rsp + UiText.y], eax
    mov eax, [rdx + 8]
    sub eax, 2 * PAD
    mov [rsp + UiText.width], eax
    mov eax, [rdx + 12]
    mov [rsp + UiText.height], eax
    mov eax, [rsi]
    mov [rsp + UiText.clip_x], eax
    mov eax, [rsi + 4]
    mov [rsp + UiText.clip_y], eax
    mov eax, [rsi + 8]
    mov [rsp + UiText.clip_w], eax
    mov eax, [rsi + 12]
    mov [rsp + UiText.clip_h], eax
    mov rsi, rsp                        ; mapped into the frame
    call frame_text
    add rsp, TEXT_FRAME
.none:
    ret

; rdi = server: the output the pointer is on (the first with no seat)
pick_output:
    mov rax, [rdi + Server.input_seat]
    test rax, rax
    jz .first
    mov esi, [rax + InputSeat.x]
    mov edx, [rax + InputSeat.y]
    sub rsp, 8
    call compositor_output_at
    add rsp, 8
    mov [rel output], rax
    ret
.first:
    mov rax, [rdi + Server.outputs]
    mov [rel output], rax
    ret

; The box: centred on its output, in the layout
place_box:
    mov rax, [rel output]
    test rax, rax
    jz .out
    call rows_shown
    imul ecx, eax, ROW_H
    add ecx, 2 * PAD
    mov dword [rel box + 8], MENU_W
    mov [rel box + 12], ecx
    mov rax, [rel output]
    mov edx, [rax + Output.width]
    sub edx, MENU_W
    sar edx, 1
    add edx, [rax + Output.x]
    mov [rel box], edx
    mov edx, [rax + Output.height]
    sub edx, ecx
    sar edx, 1
    add edx, [rax + Output.y]
    mov [rel box + 4], edx
.out:
    ret

; The box into its output's damage
damage_box:
    mov rax, [rel output]
    test rax, rax
    jz .out
    mov rdi, [rax + Output.damage]
    lea rsi, [rel box]
    jmp region_add_rect
.out:
    ret

section .rodata
hc_box:             dd HC_BOX
hc_selected:        dd HC_SELECTED
hc_text:            dd HC_TEXT
hc_text_selected:   dd HC_TEXT_SELECTED
hint:               db "Type to search"
hint_len            equ $ - hint
lock_label:         db "Lock"
switch_label:       db "Switch user"
sleep_label:        db "Sleep"
restart_label:      db "Restart"
off_label:          db "Shut down"
end_labels:
power_lengths:      db switch_label - lock_label, sleep_label - switch_label
                    db restart_label - sleep_label, off_label - restart_label
                    db end_labels - off_label

section .data
alignb 8
modifier_keys:      dd 29, 42, 54, 56, 97, 100, 125, 126, 58, 69, 70
MODIFIER_KEYS       equ ($ - modifier_keys) / 4
power_labels:       dq lock_label, switch_label, sleep_label, restart_label, off_label
global menu_version
menu_version:       dq 0x010000

section .bss
alignb 8
server_p:       resq 1
output:         resq 1                  ; where the box is drawn
box:            resd 4                  ; x, y, width, height
kind:           resd 1                  ; MENU_*
selected:       resd 1
query_len:      resd 1
match_count:    resd 1
matches:        resd APPS_MAX           ; the apps shown, by place in the list
query:          resb QUERY_MAX + 1
alignb 8
app_buf:        resb APP_BUF_SIZE       ; the kernel's names
