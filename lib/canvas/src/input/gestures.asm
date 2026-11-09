; ============================================================================
; Gestures — Touchpad Hold, Swipe and Pinch (TCH-02)
; ============================================================================
; A touchpad is a device whose InputDevInfo.caps has both pointer (2) and
; touch (4). Its contacts (records type 6) are not fingers on the screen:
; input.asm hands them here, and they make gestures for the surface under
; the pointer, as cw_gesture events (CAP_POINTER). The pointer's motion and
; taps come from the touchpad's driver as records 2 and 4, as ever.
;
; At each frame end, with n fingers down:
;   - n changed: what was running ends (cancelled unless every finger was
;     lifted), and with fingers still down a hold begins for n.
;   - n the same: a hold becomes a pinch when two fingers spread or close by
;     GESTURE_START pixels, or a swipe when three or more move together by
;     that much (it ends, cancelled, and the other begins); a swipe then
;     tells how far the fingers' middle moved, a pinch the scale since it
;     began (16.16) and that move. Two fingers moving together are scrolling,
;     the driver's to report.
;   - Four or more fingers moving together are the server's (WIN-21): no
;     swipe goes to the client; when they lift or change, a move of
;     WORKSPACE_SWIPE pixels left shows the next workspace, right the one
;     before (not while the screen is locked).
; Places are the device's mapped onto the first output (input_device_point),
; so the moves are in layout pixels.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/event.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern input_device_point
extern input_send
extern input_surface_at
extern window_switch_workspace

%define GESTURE_START   8               ; layout pixels before a hold turns
%define KIND_NONE       0
%define KIND_HOLD       1
%define KIND_SWIPE      2
%define KIND_PINCH      3
%define KIND_WORKSPACE  4               ; four fingers or more: the server's
%define WORKSPACE_SWIPE 48              ; pixels across that switch
%define PHASE_DOWN      0
%define PHASE_MOVE      1
%define PHASE_UP        2
%define PHASE_FRAME     3
%define PHASE_CANCEL    4
%define EVENT_LONG      20

%define EV(e)           (CWP_OBJ_GESTURE << 16 | GESTURE_EV_ %+ e)

section .text

; ---------------------------------------------------------------------------
; gesture_touch
;   One contact record of a touchpad: a finger down, moved or up, or the
;   frame end, where gestures are worked out
;   IN:  rdi = seat*, rsi = RawInput* (type 6)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global gesture_touch
gesture_touch:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov eax, [r12 + RawInput.code]
    shr eax, 8
    and eax, 0xF
    cmp eax, PHASE_FRAME
    je .frame
    mov r13d, eax                       ; the phase
    movzx r14d, byte [r12 + RawInput.code]
    inc r14d                            ; its slot + 1, as kept
    xor ecx, ecx                        ; its entry
.find:
    cmp [rbx + InputSeat.tp_slot + rcx * 4], r14d
    je .found
    inc ecx
    cmp ecx, TOUCHPAD_FINGERS
    jb .find
    mov ecx, -1
.found:
    cmp r13d, PHASE_DOWN
    je .down
    cmp ecx, -1
    je .out                             ; nothing of it down
    cmp r13d, PHASE_MOVE
    je .place
    cmp r13d, PHASE_UP
    je .up
    cmp r13d, PHASE_CANCEL
    jne .out
.up:
    mov dword [rbx + InputSeat.tp_slot + rcx * 4], 0
    dec dword [rbx + InputSeat.tp_count]
    jmp .out
.down:
    cmp ecx, -1
    jne .place                          ; down again: as a move
    xor ecx, ecx                        ; a free entry
.free:
    cmp dword [rbx + InputSeat.tp_slot + rcx * 4], 0
    je .take
    inc ecx
    cmp ecx, TOUCHPAD_FINGERS
    jb .free
    jmp .out                            ; too many fingers: ignored
.take:
    mov [rbx + InputSeat.tp_slot + rcx * 4], r14d
    inc dword [rbx + InputSeat.tp_count]
.place:
    mov r13d, ecx
    mov rdi, rbx
    mov esi, [r12 + RawInput.device]
    mov edx, [r12 + RawInput.value]
    call input_device_point
    mov [rbx + InputSeat.tp_x + r13 * 4], eax
    mov [rbx + InputSeat.tp_y + r13 * 4], edx
    jmp .out
.frame:
    mov rdi, rbx
    call frame
.out:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; A frame end: the fingers' middle and spread, then the gesture as above.
; rdi = seat
frame:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov rdi, rbx
    call middle                         ; eax, edx = x, y; ecx = spread
    mov r12d, eax
    mov r13d, edx
    mov r14d, ecx
    mov r15d, [rbx + InputSeat.tp_count]
    cmp r15d, [rbx + InputSeat.tp_fingers]
    je .same
    xor esi, esi                        ; cancelled unless all were lifted
    test r15d, r15d
    setnz sil
    mov rdi, rbx
    call finish
    mov [rbx + InputSeat.tp_fingers], r15d
    mov [rbx + InputSeat.tp_cx], r12d
    mov [rbx + InputSeat.tp_cy], r13d
    mov [rbx + InputSeat.tp_cx0], r12d
    mov [rbx + InputSeat.tp_cy0], r13d
    mov [rbx + InputSeat.tp_spread0], r14d
    test r15d, r15d
    jz .out
    mov rdi, rbx                        ; a hold, for what is under the
    call input_surface_at               ; pointer now
    mov [rbx + InputSeat.tp_surface], rax
    mov dword [rbx + InputSeat.tp_kind], KIND_HOLD
    mov rdi, rbx
    mov edx, EV(HOLD_BEGIN)
    mov r8d, r15d
    xor r9d, r9d
    call tell
    jmp .out

.same:
    test r15d, r15d
    jz .out
    mov eax, r12d                       ; the move since the last frame,
    sub eax, [rbx + InputSeat.tp_cx]    ; packed: x low, y high
    and eax, 0xFFFF
    mov ecx, r13d
    sub ecx, [rbx + InputSeat.tp_cy]
    shl ecx, 16
    or eax, ecx
    mov [rsp], eax
    mov [rbx + InputSeat.tp_cx], r12d
    mov [rbx + InputSeat.tp_cy], r13d
    mov eax, [rbx + InputSeat.tp_kind]
    cmp eax, KIND_SWIPE
    je .swipe
    cmp eax, KIND_PINCH
    je .pinch
    cmp eax, KIND_WORKSPACE
    je .workspace
    cmp eax, KIND_HOLD
    jne .out
    cmp r15d, 2                         ; two: a pinch when they spread
    jne .many
    mov eax, r14d
    sub eax, [rbx + InputSeat.tp_spread0]
    mov ecx, eax
    neg ecx
    cmovs ecx, eax                      ; |spread - spread at the start|
    cmp ecx, GESTURE_START
    jl .out
    mov rdi, rbx
    mov esi, 1
    call finish
    mov dword [rbx + InputSeat.tp_kind], KIND_PINCH
    mov rdi, rbx
    mov edx, EV(PINCH_BEGIN)
    mov r8d, r15d
    xor r9d, r9d
    call tell
    jmp .out
.many:
    cmp r15d, 3                         ; three or more: a swipe when they
    jb .out                             ; move together
    mov eax, r12d
    sub eax, [rbx + InputSeat.tp_cx0]
    mov ecx, eax
    neg ecx
    cmovs ecx, eax
    mov eax, r13d
    sub eax, [rbx + InputSeat.tp_cy0]
    mov edx, eax
    neg edx
    cmovs edx, eax
    add ecx, edx
    cmp ecx, GESTURE_START
    jl .out
    mov rdi, rbx
    mov esi, 1
    call finish
    cmp r15d, 4
    jb .client_swipe
    mov dword [rbx + InputSeat.tp_kind], KIND_WORKSPACE
    mov eax, r12d                       ; counted from where they began
    sub eax, [rbx + InputSeat.tp_cx0]
    mov [rbx + InputSeat.tp_total], eax
    jmp .out
.client_swipe:
    mov dword [rbx + InputSeat.tp_kind], KIND_SWIPE
    mov rdi, rbx
    mov edx, EV(SWIPE_BEGIN)
    mov r8d, r15d
    xor r9d, r9d
    call tell
    jmp .out
.workspace:
    movsx eax, word [rsp]               ; the move across
    add [rbx + InputSeat.tp_total], eax
    jmp .out
.swipe:
    mov rdi, rbx
    mov edx, EV(SWIPE_UPDATE)
    mov r8d, [rsp]
    mov r9d, r15d
    call tell
    jmp .out
.pinch:
    mov ecx, [rbx + InputSeat.tp_spread0]   ; the scale since it began
    test ecx, ecx
    jnz .spread
    inc ecx
.spread:
    mov eax, r14d
    shl rax, 16
    xor edx, edx
    div rcx
    mov r8d, eax
    mov rdi, rbx
    mov edx, EV(PINCH_UPDATE)
    mov r9d, [rsp]
    call tell
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; What runs ends: hold_end, swipe_end or pinch_end(cancelled).
; rdi = seat, esi = 1 cancelled, 0 not
finish:
    mov eax, [rdi + InputSeat.tp_kind]
    mov dword [rdi + InputSeat.tp_kind], KIND_NONE
    mov r8d, esi
    xor r9d, r9d
    mov edx, EV(HOLD_END)
    cmp eax, KIND_HOLD
    je tell
    mov edx, EV(SWIPE_END)
    cmp eax, KIND_SWIPE
    je tell
    mov edx, EV(PINCH_END)
    cmp eax, KIND_PINCH
    je tell
    cmp eax, KIND_WORKSPACE
    je workspace_swiped
    xor eax, eax
    ret

; Four fingers lifted or changed: far enough left, the next workspace;
; right, the one before (window_switch_workspace refuses past the ends);
; none while locked.
; rdi = seat
workspace_swiped:
    mov eax, [rdi + InputSeat.tp_total]
    mov rdx, [rdi + InputSeat.server]
    cmp qword [rdx + Server.locked], 0
    jne .none
    mov ecx, [rdx + Server.workspace]
    cmp eax, -WORKSPACE_SWIPE
    jle .next
    cmp eax, WORKSPACE_SWIPE
    jl .none
    dec ecx                             ; right: the one before
    jmp .show
.next:
    inc ecx
.show:
    mov rdi, rdx
    mov esi, ecx
    jmp window_switch_workspace
.none:
    xor eax, eax
    ret

; One cw_gesture event to the gesture's surface, if it has one.
; rdi = seat, edx = interface << 16 | event, r8d, r9d = its a and b
tell:
    mov rsi, [rdi + InputSeat.tp_surface]
    test rsi, rsi
    jz .none
    mov ecx, EVENT_LONG
    jmp input_send
.none:
    xor eax, eax
    ret

; rdi = seat -> eax, edx = the middle of the fingers down, ecx = their mean
; distance from it (|dx| + |dy|); all 0 with none
middle:
    push rbx
    push r12
    push r13
    xor eax, eax                        ; x sum, y sum, count
    xor edx, edx
    xor r8d, r8d
    xor ecx, ecx
.sum:
    cmp dword [rdi + InputSeat.tp_slot + rcx * 4], 0
    je .next
    add eax, [rdi + InputSeat.tp_x + rcx * 4]
    add edx, [rdi + InputSeat.tp_y + rcx * 4]
    inc r8d
.next:
    inc ecx
    cmp ecx, TOUCHPAD_FINGERS
    jb .sum
    test r8d, r8d
    jz .empty
    mov r9d, edx
    cdq
    idiv r8d
    mov r10d, eax                       ; x
    mov eax, r9d
    cdq
    idiv r8d
    mov r11d, eax                       ; y
    xor ebx, ebx                        ; the spread
    xor ecx, ecx
.spread:
    cmp dword [rdi + InputSeat.tp_slot + rcx * 4], 0
    je .skip
    mov eax, [rdi + InputSeat.tp_x + rcx * 4]
    sub eax, r10d
    mov r12d, eax
    neg r12d
    cmovs r12d, eax
    mov eax, [rdi + InputSeat.tp_y + rcx * 4]
    sub eax, r11d
    mov r13d, eax
    neg r13d
    cmovs r13d, eax
    add ebx, r12d
    add ebx, r13d
.skip:
    inc ecx
    cmp ecx, TOUCHPAD_FINGERS
    jb .spread
    mov eax, ebx
    xor edx, edx
    div r8d
    mov ecx, eax
    mov eax, r10d
    mov edx, r11d
    jmp .out
.empty:
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
.out:
    pop r13
    pop r12
    pop rbx
    ret

section .data
global gestures_version
gestures_version: dq 0x020000
