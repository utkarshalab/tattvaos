; ============================================================================
; Toplevel — Window Management (States, Configure/Ack, Move/Resize)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define Toplevel_size    120
%define TOPLEVEL_STATE_DEFAULT     0
%define TOPLEVEL_STATE_MAXIMIZED   1
%define TOPLEVEL_STATE_FULLSCREEN  2
%define TOPLEVEL_STATE_MINIMIZED   3
%define TOPLEVEL_STATE_TILED       4
%define TOPLEVEL_STATE_FLOATING    5
%define TOPLEVEL_CAP_DECORATION     (1 << 0)
%define TOPLEVEL_CAP_FULLSCREEN     (1 << 1)
%define TOPLEVEL_CAP_MAXIMIZE       (1 << 2)
%define TOPLEVEL_CAP_MINIMIZE       (1 << 3)
%define TOPLEVEL_CAP_MOVE           (1 << 4)
%define TOPLEVEL_CAP_RESIZE         (1 << 5)
%define Toplevel_surface         0
%define Toplevel_shell           8
%define Toplevel_title           16
%define Toplevel_app_id          24
%define Toplevel_state           32
%define Toplevel_pending_state   36
%define Toplevel_configure_serial 40
%define Toplevel_pending_serial  48
%define Toplevel_width           56
%define Toplevel_height          60
%define Toplevel_min_width       64
%define Toplevel_min_height      68
%define Toplevel_max_width       72
%define Toplevel_max_height      76
%define Toplevel_parent          80
%define Toplevel_workspace       88
%define Toplevel_z_order         96
%define Toplevel_policy_data     104
%define Toplevel_decoration      112
%define Toplevel_fullscreen_output 120
%define Toplevel_saved_width     128
%define Toplevel.saved_width 128
%define Toplevel_saved_height    132
%define Toplevel.saved_height 132
%define Toplevel_next            136
%define Toplevel.next 136
%define Toplevel_next_ws         144
%define Toplevel.next_ws 144
%define Toplevel_size            152

section .text

struc Toplevel
    .surface:           resq 1
    .shell:             resq 1
    .title:             resq 1
    .app_id:            resq 1
    .state:             resd 1
    .pending_state:     resd 1
    .configure_serial:  resq 1
    .pending_serial:    resq 1
    .width:             resd 1
    .height:            resd 1
    .min_width:         resd 1
    .min_height:        resd 1
    .max_width:         resd 1
    .max_height:        resd 1
    .parent:            resq 1
    .workspace:         resq 1
    .z_order:           resq 1
    .policy_data:       resq 1
    .decoration:        resq 1
    .fullscreen_output: resq 1
endstruc



; ---------------------------------------------------------------------------
; toplevel_create
;   Create toplevel for surface
; ---------------------------------------------------------------------------
global toplevel_create
toplevel_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate toplevel
    mov rdi, [rbx + Server.arena]
    mov rsi, Toplevel_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov qword [rbx + Toplevel.surface], r12
    mov qword [rbx + Toplevel.shell], r13
    mov qword [rbx + Toplevel.title], 0
    mov qword [rbx + Toplevel.app_id], 0
    mov dword [rbx + Toplevel.state], TOPLEVEL_STATE_DEFAULT
    mov dword [rbx + Toplevel.pending_state], TOPLEVEL_STATE_DEFAULT
    mov qword [rbx + Toplevel.configure_serial], 0
    mov qword [rbx + Toplevel.pending_serial], 0
    mov dword [rbx + Toplevel.width], 800
    mov dword [rbx + Toplevel.height], 600
    mov dword [rbx + Toplevel.min_width], 100
    mov dword [rbx + Toplevel.min_height], 100
    mov dword [rbx + Toplevel.max_width], 32768
    mov dword [rbx + Toplevel.max_height], 32768
    mov qword [rbx + Toplevel.parent], 0
    mov qword [rbx + Toplevel.workspace], 0
    mov qword [rbx + Toplevel.z_order], 0
    mov qword [rbx + Toplevel.policy_data], 0
    mov qword [rbx + Toplevel.decoration], 0
    mov qword [rbx + Toplevel.fullscreen_output], 0

    ; Set surface role
    mov dword [r12 + Surface.role], SHELL_ROLE_TOPLEVEL
    mov qword [r12 + Surface.role_data], rbx

    ; Add to shell's toplevel list
    mov r14, [r13 + Shell.toplevels]
    mov [rbx + Toplevel.next], r14
    mov [r13 + Shell.toplevels], rbx

    ; Assign to active workspace
    mov rax, [r13 + Shell.workspaces]
    test rax, rax
    jz .no_workspace
    mov r14, [rax + Workspace.toplevels]
    mov [rbx + Toplevel.next_ws], r14
    mov [rax + Workspace.toplevels], rbx
    mov qword [rbx + Toplevel.workspace], rax

.no_workspace:
    ; Notify policy
    mov rax, [r13 + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rbx
    call policy_new_window

.done:
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; toplevel_destroy
; ---------------------------------------------------------------------------
global toplevel_destroy
toplevel_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Remove from shell list
    ; TODO: List removal

    ; Remove from workspace
    ; TODO: Workspace list removal

    ; Notify policy
    mov r12, [rbx + Toplevel.shell]
    mov rax, [r12 + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rbx
    call policy_close_window

.done:
    ; Free title/app_id strings
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; toplevel_set_title
; ---------------------------------------------------------------------------
global toplevel_set_title
toplevel_set_title:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Free old title
    mov rax, [rbx + Toplevel.title]
    test rax, rax
    jz .set_new

    ; TODO: Free string

.set_new:
    ; Copy new title
    call str_dup_arena
    test rax, rax
    jz .oom
    mov [rbx + Toplevel.title], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; toplevel_set_app_id
; ---------------------------------------------------------------------------
global toplevel_set_app_id
toplevel_set_app_id:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Similar to set_title
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; toplevel_set_state
;   Set toplevel state (maximized, fullscreen, minimized, tiled)
; ---------------------------------------------------------------------------
global toplevel_set_state
toplevel_set_state:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    mov eax, [rbx + Toplevel.state]
    cmp eax, r12d
    je .no_change

    ; Validate state transition
    call toplevel_validate_state_transition
    test rax, rax
    jnz .invalid

    ; Apply state
    mov dword [rbx + Toplevel.pending_state], r12d

    ; Handle specific states
    cmp r12d, TOPLEVEL_STATE_FULLSCREEN
    je .handle_fullscreen
    cmp r12d, TOPLEVEL_STATE_MAXIMIZED
    je .handle_maximized
    cmp r12d, TOPLEVEL_STATE_MINIMIZED
    je .handle_minimized
    cmp r12d, TOPLEVEL_STATE_TILED
    je .handle_tiled

    ; Schedule configure
    call toplevel_schedule_configure
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.handle_fullscreen:
    ; Store current geometry for restore
    mov eax, [rbx + Toplevel.width]
    mov [rbx + Toplevel.saved_width], eax
    mov eax, [rbx + Toplevel.height]
    mov [rbx + Toplevel.saved_height], eax
    ; Set fullscreen output
    mov r12, [rbx + Toplevel.shell]
    mov rax, [r12 + Shell.outputs]
    mov [rbx + Toplevel.fullscreen_output], rax
    jmp .schedule

.handle_maximized:
    mov eax, [rbx + Toplevel.width]
    mov [rbx + Toplevel.saved_width], eax
    mov eax, [rbx + Toplevel.height]
    mov [rbx + Toplevel.saved_height], eax
    jmp .schedule

.handle_minimized:
    ; Hide surface
    ; TODO: surface_set_visible(rbx, 0)
    jmp .schedule

.handle_tiled:
    ; Notify policy for tiling
    mov rax, [rbx + Toplevel.shell]
    mov rax, [rax + Shell.policy]
    test rax, rax
    jz .schedule
    mov rdi, rax
    mov rsi, rbx
    call policy_tile_window

.schedule:
    call toplevel_schedule_configure
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.no_change:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; toplevel_validate_state_transition
; ---------------------------------------------------------------------------
toplevel_validate_state_transition:
    PROLOGUE
    ; Allow most transitions, but validate fullscreen
    cmp r12d, TOPLEVEL_STATE_FULLSCREEN
    jne .ok
    ; Fullscreen requires output
    mov rax, [rdi + Toplevel.fullscreen_output]
    test rax, rax
    jz .fail
.ok:
    xor rax, rax
    leave
    ret
.fail:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; toplevel_schedule_configure
; ---------------------------------------------------------------------------
toplevel_schedule_configure:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Increment serial
    mov rax, [rbx + Toplevel.configure_serial]
    inc rax
    mov [rbx + Toplevel.configure_serial], rax
    mov [rbx + Toplevel.pending_serial], rax

    ; Send configure event
    ; TODO: Encode and send cw_toplevel.configure

    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; toplevel_ack_configure
;   Client acks configure
; ---------------------------------------------------------------------------
global toplevel_ack_configure
toplevel_ack_configure:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Check serial matches
    mov rax, [rbx + Toplevel.pending_serial]
    cmp rax, r12
    jne .serial_mismatch

    ; Apply pending state
    mov eax, [rbx + Toplevel.pending_state]
    mov [rdi + Toplevel.state], eax

    ; Apply pending geometry
    mov eax, [rbx + Toplevel.pending_width]
    mov [rbx + Toplevel.width], eax
    mov eax, [rbx + Toplevel.pending_height]
    mov [rbx + Toplevel.height], eax

    ; Notify policy of geometry change
    mov rax, [rdi + Toplevel.shell]
    mov rax, [rax + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rbx
    call policy_window_configured

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.serial_mismatch:
    mov rax, -(ECWP_SEQ)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; toplevel_set_min_size
; ---------------------------------------------------------------------------
global toplevel_set_min_size
toplevel_set_min_size:
    PROLOGUE
    ASSERT_PTR rdi
    mov [rdi + Toplevel.min_width], esi
    mov [rdi + Toplevel.min_height], edx
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; toplevel_set_max_size
; ---------------------------------------------------------------------------
global toplevel_set_max_size
toplevel_set_max_size:
    PROLOGUE
    ASSERT_PTR rdi
    mov [rdi + Toplevel.max_width], esi
    mov [rdi + Toplevel.max_height], edx
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; toplevel_set_parent
; ---------------------------------------------------------------------------
global toplevel_set_parent
toplevel_set_parent:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov [rbx + Toplevel.parent], r12
    ; TODO: Add to parent's children list
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; toplevel_move
;   Start interactive move
; ---------------------------------------------------------------------------
global toplevel_move
toplevel_move:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR rbx

    ; Start move via seat
    mov rax, [rbx + Toplevel.shell]
    mov rax, [rax + Server.default_seat]
    test rax, rax
    jz .fail

    ; Start grab
    mov rdi, rbx
    mov rsi, GRAB_POINTER
    mov rdx, rbx
    mov rcx, r12
    call grab_pointer
    test rax, rax
    jnz .fail

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.fail:
    mov rax, -(EBUSY)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; toplevel_resize
;   Start interactive resize
; ---------------------------------------------------------------------------
global toplevel_resize
toplevel_resize:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    ; Similar to move but with edges
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data


global toplevel_version
toplevel_version: dq 0x010000
