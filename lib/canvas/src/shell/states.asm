; ============================================================================
; States — Window State Management (Maximized, Fullscreen, Minimized, Tiled)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

extern zorder_remove
extern zorder_insert

; struct offsets (hoisted above use)
%define TOPLEVEL_STATE_DEFAULT     0
%define TOPLEVEL_STATE_MAXIMIZED   1
%define TOPLEVEL_STATE_FULLSCREEN  2
%define TOPLEVEL_STATE_MINIMIZED   3
%define TOPLEVEL_STATE_TILED       4
%define TOPLEVEL_STATE_FLOATING    5
%define STATE_FLAG_MAXIMIZED    (1 << 0)
%define STATE_FLAG_FULLSCREEN   (1 << 1)
%define STATE_FLAG_MINIMIZED    (1 << 2)
%define STATE_FLAG_TILED        (1 << 3)
%define STATE_FLAG_FLOATING     (1 << 4)
%define STATE_FLAG_ACTIVATED    (1 << 5)

section .text



; ---------------------------------------------------------------------------
; states_init
; ---------------------------------------------------------------------------
global states_init
states_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_get
;   Get current state flags
; ---------------------------------------------------------------------------
global states_get
states_get:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    leave
    ret

; ---------------------------------------------------------------------------
; states_set
;   Set state flags (replaces all)
; ---------------------------------------------------------------------------
global states_set
states_set:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + Toplevel.state], esi
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_add
;   Add state flag
; ---------------------------------------------------------------------------
global states_add
states_add:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    or eax, esi
    mov [rdi + Toplevel.state], eax
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_remove
;   Remove state flag
; ---------------------------------------------------------------------------
global states_remove
states_remove:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    not esi
    and eax, esi
    mov [rdi + Toplevel.state], eax
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_has
;   Check if state flag is set
; ---------------------------------------------------------------------------
global states_has
states_has:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    test eax, esi
    jz .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_toggle
;   Toggle state flag
; ---------------------------------------------------------------------------
global states_toggle
states_toggle:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    xor eax, esi
    mov [rdi + Toplevel.state], eax
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_is_maximized
; ---------------------------------------------------------------------------
global states_is_maximized
states_is_maximized:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    and eax, STATE_FLAG_MAXIMIZED
    jz .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_is_fullscreen
; ---------------------------------------------------------------------------
global states_is_fullscreen
states_is_fullscreen:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    and eax, STATE_FLAG_FULLSCREEN
    jz .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_is_minimized
; ---------------------------------------------------------------------------
global states_is_minimized
states_is_minimized:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    and eax, STATE_FLAG_MINIMIZED
    jz .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_is_tiled
; ---------------------------------------------------------------------------
global states_is_tiled
states_is_tiled:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    and eax, STATE_FLAG_TILED
    jz .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_is_floating
; ---------------------------------------------------------------------------
global states_is_floating
states_is_floating:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    and eax, STATE_FLAG_FLOATING
    jz .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_is_activated
; ---------------------------------------------------------------------------
global states_is_activated
states_is_activated:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    and eax, STATE_FLAG_ACTIVATED
    jz .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_activate
; ---------------------------------------------------------------------------
global states_activate
states_activate:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    or eax, STATE_FLAG_ACTIVATED
    mov [rdi + Toplevel.state], eax
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_deactivate
; ---------------------------------------------------------------------------
global states_deactivate
states_deactivate:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Toplevel.state]
    and eax, ~STATE_FLAG_ACTIVATED
    mov [rdi + Toplevel.state], eax
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; states_maximize
; ---------------------------------------------------------------------------
global states_maximize
states_maximize:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Save current geometry
    mov eax, [rbx + Toplevel.width]
    mov [rbx + Toplevel.saved_width], eax
    mov eax, [rbx + Toplevel.height]
    mov [rbx + Toplevel.saved_height], eax

    ; Set maximized
    mov eax, [rbx + Toplevel.state]
    or eax, STATE_FLAG_MAXIMIZED
    mov [rbx + Toplevel.state], eax

    mov rax,[rbx + Toplevel.output]
    test rax,rax
    jz .no_output
    mov ecx,[rax + Output.width]
    mov [rbx + Toplevel.pending_width],ecx
    mov edx,[rax + Output.height]
    mov [rbx + Toplevel.pending_height],edx
    mov byte [rbx + Toplevel.pending_state],1
    mov esi,[rax + Output.x]
    mov edx,[rax + Output.y]
    mov rdi,rbx
    call toplevel_set_position
.no_output:

    mov rdi,rbx
    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; states_unmaximize
; ---------------------------------------------------------------------------
global states_unmaximize
states_unmaximize:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, [rbx + Toplevel.state]
    and eax, ~STATE_FLAG_MAXIMIZED
    mov [rbx + Toplevel.state], eax

    ; Restore saved geometry
    mov eax, [rbx + Toplevel.saved_width]
    mov [rbx + Toplevel.pending_width], eax
    mov eax, [rbx + Toplevel.saved_height]
    mov [rbx + Toplevel.pending_height], eax

    mov rdi,rbx
    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; states_fullscreen
; ---------------------------------------------------------------------------
global states_fullscreen
states_fullscreen:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Save current geometry
    mov eax, [rbx + Toplevel.width]
    mov [rbx + Toplevel.saved_width], eax
    mov eax, [rbx + Toplevel.height]
    mov [rbx + Toplevel.saved_height], eax

    ; Set fullscreen
    mov eax, [rbx + Toplevel.state]
    or eax, STATE_FLAG_FULLSCREEN
    mov [rbx + Toplevel.state], eax

    mov rax,[rbx + Toplevel.output]
    test rax,rax
    jz .no_output
    mov ecx,[rax + Output.width]
    mov [rbx + Toplevel.pending_width],ecx
    mov edx,[rax + Output.height]
    mov [rbx + Toplevel.pending_height],edx
    mov byte [rbx + Toplevel.pending_state],1
    mov esi,[rax + Output.x]
    mov edx,[rax + Output.y]
    mov rdi,rbx
    call toplevel_set_position
.no_output:

    mov rdi,rbx
    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; states_unfullscreen
; ---------------------------------------------------------------------------
global states_unfullscreen
states_unfullscreen:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, [rbx + Toplevel.state]
    and eax, ~STATE_FLAG_FULLSCREEN
    mov [rbx + Toplevel.state], eax

    ; Restore saved geometry
    mov eax, [rbx + Toplevel.saved_width]
    mov [rbx + Toplevel.pending_width], eax
    mov eax, [rbx + Toplevel.saved_height]
    mov [rbx + Toplevel.pending_height], eax

    mov rdi,rbx
    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; states_minimize
; ---------------------------------------------------------------------------
global states_minimize
states_minimize:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, [rbx + Toplevel.state]
    or eax, STATE_FLAG_MINIMIZED
    mov [rbx + Toplevel.state], eax

    mov rax,[rbx + Toplevel.shell]
    test rax,rax
    jz .configured
    mov rdi,[rax + Shell.server]
    mov rsi,[rbx + Toplevel.surface]
    test rdi,rdi
    jz .configured
    test rsi,rsi
    jz .configured
    call zorder_remove

.configured:
    mov rdi,rbx
    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; states_unminimize
; ---------------------------------------------------------------------------
global states_unminimize
states_unminimize:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, [rbx + Toplevel.state]
    and eax, ~STATE_FLAG_MINIMIZED
    mov [rbx + Toplevel.state], eax

    mov rax,[rbx + Toplevel.shell]
    test rax,rax
    jz .configured
    mov rdi,[rax + Shell.server]
    mov rsi,[rbx + Toplevel.surface]
    test rdi,rdi
    jz .configured
    test rsi,rsi
    jz .configured
    mov rdx,[rsi + Surface.z_order]
    call zorder_insert

.configured:
    mov rdi,rbx
    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; states_tile
; ---------------------------------------------------------------------------
global states_tile
states_tile:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, [rbx + Toplevel.state]
    or eax, STATE_FLAG_TILED
    mov [rbx + Toplevel.state], eax

    ; Notify policy for tiling
    mov rax, [rbx + Toplevel.shell]
    mov rax, [rax + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rbx
    call policy_tile_window

.done:
    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; states_untile
; ---------------------------------------------------------------------------
global states_untile
states_untile:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, [rbx + Toplevel.state]
    and eax, ~STATE_FLAG_TILED
    mov [rbx + Toplevel.state], eax

    ; Revert to floating
    mov eax, [rbx + Toplevel.state]
    or eax, STATE_FLAG_FLOATING
    mov [rbx + Toplevel.state], eax

    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; states_float
; ---------------------------------------------------------------------------
global states_float
states_float:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, [rbx + Toplevel.state]
    and eax, ~STATE_FLAG_TILED
    or eax, STATE_FLAG_FLOATING
    mov [rbx + Toplevel.state], eax

    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global states_version
states_version: dq 0x010000
