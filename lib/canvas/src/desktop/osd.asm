; ============================================================================
; OSD — Volume and Brightness On-Screen Displays
; ============================================================================
; DSK-08. The volume keys (up, down, mute) and the brightness keys are the
; server's, at the login screen too: each moves its level by OSD_STEP (0 to
; 100) or turns muting over, tells the kernel (ut_audio_set_volume with the
; level and 1 when muted, ut_backlight_set with the level; weak imports:
; without them only the display changes), and shows what it is now for
; OSD_SHOW_NS: a box near the bottom of the output the pointer is on, the
; name of what changed and a bar as long as its level, drawn by the server
; over everything (osd_render). osd_step takes it away when its time is up.
; The levels start at 50 for the volume and 100 for the brightness.

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
extern ut_time_now_ns
extern ut_audio_set_volume
extern ut_backlight_set

%define KEY_MUTE            113
%define KEY_VOLUMEDOWN      114
%define KEY_VOLUMEUP        115
%define KEY_BRIGHTNESSDOWN  224
%define KEY_BRIGHTNESSUP    225
%define OSD_STEP            5
%define OSD_SHOW_NS         1500000000  ; a second and a half
%define OSD_W               200
%define OSD_H               48
%define OSD_BOTTOM          64          ; its bottom this far above the output's
%define BAR_X               16          ; the bar inside the box
%define BAR_Y               32
%define BAR_W               (OSD_W - 2 * BAR_X)
%define BAR_H               6
%define BOX_COLOR           0xE0181C28
%define TRACK_COLOR         0xFF3A3F50
%define FILL_COLOR          0xFFD0D4E0
%define TEXT_COLOR          0xD0D4E0
%define HC_BOX              0xFF000000
%define HC_FILL             0xFFFFFF00
%define TEXT_SIZE           13

section .text

; ---------------------------------------------------------------------------
; osd_key
;   A key press: a volume or brightness key changes its level and shows it
;   IN:  rdi = server*, esi = keycode
;   OUT: eax = 1 it was one of them, 0 not
; ---------------------------------------------------------------------------
global osd_key
osd_key:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    xor eax, eax
    cmp r12d, KEY_MUTE
    jb .out
    cmp r12d, KEY_VOLUMEUP
    jbe .ours
    cmp r12d, KEY_BRIGHTNESSDOWN
    je .ours
    cmp r12d, KEY_BRIGHTNESSUP
    jne .out
.ours:
    cmp qword [rbx + Server.osd_ready], 0   ; the levels to begin with
    jne .ready
    mov qword [rbx + Server.volume], 50
    mov qword [rbx + Server.brightness], 100
    mov qword [rbx + Server.osd_ready], 1
.ready:
    cmp r12d, KEY_MUTE
    je .mute
    cmp r12d, KEY_VOLUMEDOWN
    je .quieter
    cmp r12d, KEY_VOLUMEUP
    je .louder
    mov rax, [rbx + Server.brightness]
    cmp r12d, KEY_BRIGHTNESSDOWN
    je .dimmer
    add rax, OSD_STEP
    jmp .brightness
.dimmer:
    sub rax, OSD_STEP
.brightness:
    call clamp
    mov [rbx + Server.brightness], rax
    mov edi, eax
    call ut_backlight_set
    mov esi, OSD_BRIGHTNESS
    jmp .show
.mute:
    xor qword [rbx + Server.muted], 1
    jmp .volume
.quieter:
    mov rax, [rbx + Server.volume]
    sub rax, OSD_STEP
    jmp .level
.louder:
    mov qword [rbx + Server.muted], 0   ; louder unmutes
    mov rax, [rbx + Server.volume]
    add rax, OSD_STEP
.level:
    call clamp
    mov [rbx + Server.volume], rax
.volume:
    mov rdi, [rbx + Server.volume]
    mov rsi, [rbx + Server.muted]
    call ut_audio_set_volume
    mov esi, OSD_VOLUME
.show:
    mov rdi, rbx
    call show
    mov eax, 1
.out:
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; osd_step
;   Once a turn: the display away when its time is up
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global osd_step
osd_step:
    cmp qword [rdi + Server.osd_kind], 0
    je .out
    push rdi                            ; 16-byte aligned
    call ut_time_now_ns
    pop rdi
    cmp rax, [rdi + Server.osd_until]
    jb .out
    mov qword [rdi + Server.osd_kind], 0
    jmp damage_box
.out:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; osd_render
;   The display, if it is up, over a frame of its output
;   IN:  rdi = FrameCtx*, rsi = clip rect*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global osd_render
osd_render:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 16                         ; a rect
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + FrameCtx.server]
    test r13, r13
    jz .out
    cmp qword [r13 + Server.osd_kind], 0
    je .out
    mov rax, [r13 + Server.osd_output]
    cmp [rbx + FrameCtx.output], rax
    jne .out
    lea rdx, [r13 + Server.osd_box]     ; the box
    mov ecx, BOX_COLOR
    cmp qword [r13 + Server.high_contrast], 0
    je .box
    mov ecx, HC_BOX
.box:
    call fill
    mov eax, [r13 + Server.osd_box]     ; the track
    add eax, BAR_X
    mov [rsp], eax
    mov eax, [r13 + Server.osd_box + 4]
    add eax, BAR_Y
    mov [rsp + 4], eax
    mov dword [rsp + 8], BAR_W
    mov dword [rsp + 12], BAR_H
    mov rdx, rsp
    mov ecx, TRACK_COLOR
    call fill
    call level                          ; and as much of it as the level
    imul eax, eax, BAR_W
    xor edx, edx
    mov ecx, 100
    div ecx
    test eax, eax
    jz .label
    mov [rsp + 8], eax
    mov rdx, rsp
    mov ecx, FILL_COLOR
    cmp qword [r13 + Server.high_contrast], 0
    je .fill
    mov ecx, HC_FILL
.fill:
    call fill
.label:
    call label
.out:
    xor eax, eax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; rax = a level -> rax = it within 0 to 100
clamp:
    test rax, rax
    jns .low
    xor eax, eax
.low:
    cmp rax, 100
    jbe .out
    mov eax, 100
.out:
    ret

; rdi = server, esi = OSD_*: shown, until OSD_SHOW_NS from now, near the
; bottom of the output the pointer is on
show:
    push rbx
    push r12
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12d, esi
    cmp qword [rbx + Server.osd_kind], 0
    je .placed_before
    mov rdi, rbx                        ; where it was, redrawn
    call damage_box
.placed_before:
    mov [rbx + Server.osd_kind], r12
    call ut_time_now_ns
    mov rcx, OSD_SHOW_NS
    add rax, rcx
    mov [rbx + Server.osd_until], rax
    mov rax, [rbx + Server.outputs]     ; the pointer's output, else the first
    mov rcx, [rbx + Server.input_seat]
    test rcx, rcx
    jz .output
    mov rdi, rbx
    mov esi, [rcx + InputSeat.x]
    mov edx, [rcx + InputSeat.y]
    call compositor_output_at
.output:
    mov [rbx + Server.osd_output], rax
    test rax, rax
    jz .out
    mov edx, [rax + Output.width]       ; centred, near its bottom
    sub edx, OSD_W
    sar edx, 1
    add edx, [rax + Output.x]
    mov [rbx + Server.osd_box], edx
    mov edx, [rax + Output.height]
    sub edx, OSD_BOTTOM + OSD_H
    add edx, [rax + Output.y]
    mov [rbx + Server.osd_box + 4], edx
    mov dword [rbx + Server.osd_box + 8], OSD_W
    mov dword [rbx + Server.osd_box + 12], OSD_H
    mov rdi, rbx
    call damage_box
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; rdi = server: its box into its output's damage
damage_box:
    mov rax, [rdi + Server.osd_output]
    test rax, rax
    jz .out
    lea rsi, [rdi + Server.osd_box]
    mov rdi, [rax + Output.damage]
    jmp region_add_rect
.out:
    xor eax, eax
    ret

; osd_render's: eax = the level shown (0 while muted)
level:
    mov rax, [r13 + Server.brightness]
    cmp qword [r13 + Server.osd_kind], OSD_BRIGHTNESS
    je .out
    xor eax, eax
    cmp qword [r13 + Server.muted], 0
    jne .out
    mov rax, [r13 + Server.volume]
.out:
    ret

; osd_render's: rdx = rect, ecx = colour, the part inside the clip painted;
; rbx = frame, r12 = clip
fill:
    sub rsp, 40                         ; the part, the colour
    mov [rsp + 16], ecx
    lea rdi, [rsp]
    mov rsi, rdx
    mov rdx, r12
    call rect_intersect
    test rax, rax
    jnz .out
    mov rdi, rbx
    lea rsi, [rsp]
    mov edx, [rsp + 16]
    call sw_render_rect
.out:
    add rsp, 40
    ret

; osd_render's: what it is, at the box's top left
%define LABEL_FRAME (((UiText_size + 15) & ~15) + 8)
label:
    sub rsp, LABEL_FRAME
    lea rcx, [rel s_volume]
    mov r8d, s_volume_len
    cmp qword [r13 + Server.osd_kind], OSD_BRIGHTNESS
    jne .muted
    lea rcx, [rel s_brightness]
    mov r8d, s_brightness_len
    jmp .chosen
.muted:
    cmp qword [r13 + Server.muted], 0
    je .chosen
    lea rcx, [rel s_muted]
    mov r8d, s_muted_len
.chosen:
    mov [rsp + UiText.text], rcx
    mov [rsp + UiText.length], r8d
    mov dword [rsp + UiText.colour], TEXT_COLOR
    mov dword [rsp + UiText.size], TEXT_SIZE
    mov rax, [rbx + FrameCtx.framebuffer]
    mov [rsp + UiText.pixels], rax
    mov rax, [rbx + FrameCtx.stride]
    mov [rsp + UiText.stride], rax
    mov eax, [r13 + Server.osd_box]
    add eax, BAR_X
    mov [rsp + UiText.x], eax
    mov eax, [r13 + Server.osd_box + 4]
    add eax, 6
    mov [rsp + UiText.y], eax
    mov dword [rsp + UiText.width], BAR_W
    mov dword [rsp + UiText.height], 20
    mov eax, [r12]
    mov [rsp + UiText.clip_x], eax
    mov eax, [r12 + 4]
    mov [rsp + UiText.clip_y], eax
    mov eax, [r12 + 8]
    mov [rsp + UiText.clip_w], eax
    mov eax, [r12 + 12]
    mov [rsp + UiText.clip_h], eax
    mov rdi, rbx
    mov rsi, rsp
    call frame_text
    add rsp, LABEL_FRAME
    ret

section .rodata
s_volume:           db "Volume"
s_volume_len        equ $ - s_volume
s_muted:            db "Muted"
s_muted_len         equ $ - s_muted
s_brightness:       db "Brightness"
s_brightness_len    equ $ - s_brightness

section .data
global osd_version
osd_version:        dq 0x010000
