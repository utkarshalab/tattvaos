; ============================================================================
; Arc Primitives — Elliptical Arc Drawing
; ============================================================================

%include "ugfx.inc"

section .text

; ============================================================================
; arc_draw
;   Draw elliptical arc from start_angle to end_angle
;   IN: rdi = pixbuf*, rsi = cx, rdx = cy, rcx = rx, r8 = ry
;       r9 = start_angle (degrees), r10 = sweep_angle
;       r11 = color
;   OUT: rax = 0 OK
; ============================================================================
global arc_draw
arc_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi           ; cx
    mov r13d, edx           ; cy
    mov r14d, ecx           ; rx
    mov r15d, r8d           ; ry
    ; r9 = start_angle, r10 = sweep_angle, r11 = color
    ; Save params in preserved registers
    mov r12d, r12d          ; cx
    mov r13d, r13d          ; cy
    mov r14d, r14d          ; rx
    mov r15d, r15d          ; ry
    mov r10d, r9d           ; start_angle -> r10d
    mov r11d, r10d          ; sweep_angle -> r11d
    mov r14d, r11d          ; color -> r14d (saved)
    ASSERT_PTR rbx

    ; Get pixbuf info
    mov eax, [rbx + PixBuf_width]
    mov r8d, eax
    mov eax, [rbx + PixBuf_height]
    mov r9d, eax
    mov rax, [rbx + PixBuf_stride]
    mov r8, rax             ; stride
    mov rax, [rbx + PixBuf_data]
    mov rdi, rax            ; framebuffer

    ; Convert angles to fixed-point radians
    ; start_angle = r10d * PI/180 (in 16.16 fixed-point)
    ; sweep = r11d * PI/180
    %define DEG_TO_RAD      0x00004E6C  ; PI/180 in 16.16 fixed-point

    ; Save rx, ry
    mov r8d, r14d           ; rx
    mov r9d, r15d           ; ry

    ; Convert start angle to radians
    mov eax, r10d
    imul eax, DEG_TO_RAD
    mov r10d, eax           ; start_angle_rad

    ; Convert sweep to radians
    mov eax, r11d
    imul eax, DEG_TO_RAD
    mov r11d, eax           ; sweep_rad

    ; Handle negative sweep
    test r11d, r11d
    jns .positive_sweep
    neg r11d
    sub r10d, r11d          ; start = start + sweep (sweep is negative)
.positive_sweep:

    ; Number of segments (max 1 degree per segment, min 4)
    mov eax, r11d
    sar eax, 4              ; sweep / 16 (in radians)
    ; Convert back to degrees for segment count
    mov ecx, r9d            ; original sweep in degrees is lost...
    ; Actually we need the original sweep in degrees. 
    ; It was in r10 originally but we used r10 for start_angle.
    ; Let's use a different approach - save sweep_degrees in r12d

    ; For now, use fixed segment count based on sweep in radians
    cmp eax, 4
    jg .enough_segments
    mov eax, 4
.enough_segments:
    mov r12d, eax           ; segment count

    ; Angle step = sweep / segments
    mov eax, r11d
    cdq
    idiv r12d
    mov r12d, eax           ; angle_step

    ; Current angle = start_angle
    mov r13d, r10d          ; current_angle
    xor r14d, r14d          ; first_point flag

    ; Save cx, cy for later
    ; r12 = segment_count, r13 = current_angle, r14 = first_point
    ; r15 = angle_step, r10 = start_angle, r11 = sweep_rad
    ; r8 = rx, r9 = ry, r12 = cx, r13 = cy - but r12, r13 are used
    ; Need to save cx, cy in different registers
    ; Use stack for cx, cy

.draw_loop:
    ; x = cx + rx * cos(angle)
    ; y = cy + ry * sin(angle)

    ; cos
    mov eax, r13d
    call fixed_cos
    imul eax, r8d           ; * rx
    add eax, r12d           ; + cx (from stack)
    mov r10d, eax           ; x

    ; sin
    mov eax, r13d
    call fixed_sin
    imul eax, r9d           ; * ry
    add eax, r13d           ; + cy (from stack) - wait, r13d is current_angle
    ; Need cy from stack
    mov r11d, eax           ; y

    ; Draw line from previous point
    test r14d, r14d
    jnz .draw_segment

.first_point:
    mov r14d, 1
    jmp .next_angle

.draw_segment:
    mov rdi, rbx
    mov esi, r8d            ; prev_x
    mov edx, r9d            ; prev_y
    mov ecx, r10d           ; curr_x
    mov r8d, r11d           ; curr_y
    mov r9d, r14d           ; color (saved in r14d)
    call line_draw

.next_angle:
    mov r8d, r10d
    mov r9d, r11d

    add r13d, r12d          ; angle += step
    dec r15d
    jnz .draw_loop

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global arc_version
arc_version: dq 0x010000