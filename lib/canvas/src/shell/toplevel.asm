; ============================================================================
; Toplevel Management — Window Lifecycle, State, Configuration
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"

extern configure_ack
extern configure_create
extern decoration_create_for_toplevel
extern decoration_destroy
extern frame_callback_init
extern surface_destroy
extern surface_set_position

section .text

; ============================================================================
; toplevel_create
;   Create new toplevel window
;   IN: rdi = toplevel*, rsi = shell*, rdx = surface*, rcx = title, r8 = app_id
;   OUT: rax = 0 OK, -ENOMEM
; ============================================================================
global toplevel_create
toplevel_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Initialize toplevel
    mov qword [rbx + TOPLEVEL_SURFACE], r13
    mov qword [rbx + TOPLEVEL_SHELL], r12
    mov dword [rbx + TOPLEVEL_STATE], TOPLEVEL_STATE_DEFAULT
    mov dword [rbx + TOPLEVEL_PENDING_STATE], TOPLEVEL_STATE_DEFAULT
    mov dword [rbx + TOPLEVEL_CONFIGURE_SERIAL], 0
    mov dword [rbx + TOPLEVEL_CAPABILITIES], TOPLEVEL_CAP_MINIMIZE | TOPLEVEL_CAP_MAXIMIZE | TOPLEVEL_CAP_FULLSCREEN | TOPLEVEL_CAP_CLOSE
    mov dword [rbx + TOPLEVEL_WIDTH], 800
    mov dword [rbx + TOPLEVEL_HEIGHT], 600
    mov dword [rbx + TOPLEVEL_SAVED_WIDTH], 800
    mov dword [rbx + TOPLEVEL_SAVED_HEIGHT], 600
    mov qword [rbx + TOPLEVEL_DECORATION], 0
    mov dword [rbx + TOPLEVEL_X], 0
    mov dword [rbx + TOPLEVEL_Y], 0

    ; Set title
    test r14, r14
    jz .no_title
    ; Copy title string (simplified)
    mov qword [rbx + TOPLEVEL_TITLE], r14
.no_title:
    test r15, r15
    jz .no_app_id
    mov qword [rbx + TOPLEVEL_APP_ID], r15
.no_app_id:

    ; Link into shell's toplevel list
    mov rax, [r12 + SHELL_TOPLEVELS]
    mov [rbx + TOPLEVEL_NEXT_WS], rax
    mov [r12 + SHELL_TOPLEVELS], rbx

    ; Create server-side decoration
    call decoration_create_for_toplevel

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; toplevel_destroy
;   Destroy toplevel window
; ============================================================================
global toplevel_destroy
toplevel_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Unlink from shell's list
    mov r12, [rbx + TOPLEVEL_SHELL]
    call .unlink_from_shell

    ; Destroy decoration
    mov rax, [rbx + TOPLEVEL_DECORATION]
    test rax, rax
    jz .no_decor
    call decoration_destroy
.no_decor:

    ; Destroy surface
    mov rax, [rbx + TOPLEVEL_SURFACE]
    test rax, rax
    jz .no_surf
    call surface_destroy
.no_surf:

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.unlink_from_shell:
    mov rax, [r12 + SHELL_TOPLEVELS]
    test rax, rax
    jz .done

    cmp rax, rbx
    jne .find_prev
    mov rax, [rbx + TOPLEVEL_NEXT_WS]
    mov [r12 + SHELL_TOPLEVELS], rax
    jmp .done

.find_prev:
    mov r12, rax
.prev_loop:
    mov rax, [r12 + TOPLEVEL_NEXT_WS]
    test rax, rax
    jz .done
    cmp rax, rbx
    je .unlink
    mov r12, rax
    jmp .prev_loop

.unlink:
    mov rax, [rbx + TOPLEVEL_NEXT_WS]
    mov [r12 + TOPLEVEL_NEXT_WS], rax

.done:
    ret

; ============================================================================
; toplevel_set_state
;   Set toplevel state (maximized, fullscreen, etc.)
; ============================================================================
global toplevel_set_state
toplevel_set_state:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Validate state
    test esi, ~0x3F  ; Only allow defined bits
    jnz .invalid

    ; Save old state for restoration
    mov eax, [rbx + TOPLEVEL_STATE]
    test esi, TOPLEVEL_STATE_MAXIMIZED
    jz .not_max
    mov eax, [rbx + TOPLEVEL_WIDTH]
    mov [rbx + TOPLEVEL_SAVED_WIDTH], eax
    mov eax, [rbx + TOPLEVEL_HEIGHT]
    mov [rbx + TOPLEVEL_SAVED_HEIGHT], eax
.not_max:

    mov dword [rbx + TOPLEVEL_PENDING_STATE], esi

    ; Schedule configure
    call toplevel_schedule_configure

    xor rax, rax
    leave
    ret

.invalid:
    mov rax, -EINVAL
    leave
    ret

; ============================================================================
; toplevel_get_state
;   Get current toplevel state
; ============================================================================
global toplevel_get_state
toplevel_get_state:
    PROLOGUE
    mov eax, [rdi + TOPLEVEL_STATE]
    leave
    ret

; ============================================================================
; toplevel_set_title
;   Set window title
; ============================================================================
global toplevel_set_title
toplevel_set_title:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov qword [rbx + TOPLEVEL_TITLE], rsi
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; toplevel_set_app_id
;   Set application ID
; ============================================================================
global toplevel_set_app_id
toplevel_set_app_id:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov qword [rbx + TOPLEVEL_APP_ID], rsi
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; toplevel_schedule_configure
;   Schedule configure event for toplevel
; ============================================================================
global toplevel_schedule_configure
toplevel_schedule_configure:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Create configure object
    mov rdi, rbx
    call configure_create
    test rax, rax
    jnz .fail

    ; Add to shell's configure list
    mov r12, [rbx + TOPLEVEL_SHELL]
    mov rsi, rax
    call .add_configure

    ; Schedule frame callback
    mov rdi, [rbx + TOPLEVEL_SURFACE]
    lea rsi, [rbx + TOPLEVEL_FRAME_CB]
    call frame_callback_init

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.fail:
    EPILOGUE_RESTORE rbx, r12
    ret

.add_configure:
    ; Add to shell's configure list
    mov rax, [r12 + SHELL_CONFIGURE_LIST]
    mov [rax + CONFIGURE_NEXT], rax
    mov [r12 + SHELL_CONFIGURE_LIST], rax
    inc dword [r12 + SHELL_CONFIGURE_COUNT]
    ret

; ============================================================================
; toplevel_configure
;   Apply pending configure
; ============================================================================
global toplevel_configure
toplevel_configure:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi  ; configure*
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Apply width/height
    mov eax, [r12 + CONFIGURE_WIDTH]
    test eax, eax
    jz .no_width
    mov [rbx + TOPLEVEL_WIDTH], eax
    mov [rbx + TOPLEVEL_PENDING_WIDTH], eax
.no_width:

    mov eax, [r12 + CONFIGURE_HEIGHT]
    test eax, eax
    jz .no_height
    mov [rbx + TOPLEVEL_HEIGHT], eax
    mov [rbx + TOPLEVEL_PENDING_HEIGHT], eax
.no_height:

    ; Apply states
    mov eax, [r12 + CONFIGURE_STATES]
    test eax, eax
    jz .no_states
    mov dword [rbx + TOPLEVEL_STATE], eax
.no_states:

    ; Save serial
    mov eax, [r12 + CONFIGURE_SERIAL]
    mov [rbx + TOPLEVEL_CONFIGURE_SERIAL], eax

    ; Acknowledge configure
    mov rdi, r12
    call configure_ack

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; toplevel_set_position
;   Set toplevel position (for floating windows)
; ============================================================================
global toplevel_set_position
toplevel_set_position:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + TOPLEVEL_X], esi
    mov dword [rbx + TOPLEVEL_Y], edx

    ; Update surface position
    mov rax, [rbx + TOPLEVEL_SURFACE]
    test rax, rax
    jz .done
    mov rdi, rax
    mov esi, dword [rbx + TOPLEVEL_X]
    mov edx, dword [rbx + TOPLEVEL_Y]
    call surface_set_position

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; toplevel_get_size
;   Get current size
; ============================================================================
global toplevel_get_size
toplevel_get_size:
    PROLOGUE
    mov eax, [rdi + TOPLEVEL_WIDTH]
    mov edx, [rdi + TOPLEVEL_HEIGHT]
    leave
    ret

; ============================================================================
; toplevel_is_maximized/fullscreen/tiled
;   State queries
; ============================================================================
global toplevel_is_maximized
toplevel_is_maximized:
    PROLOGUE
    mov eax, [rdi + TOPLEVEL_STATE]
    test eax, TOPLEVEL_STATE_MAXIMIZED
    jz .false
    mov eax, 1
    leave
    ret
.false:
    xor eax, eax
    leave
    ret

global toplevel_is_fullscreen
toplevel_is_fullscreen:
    PROLOGUE
    mov eax, [rdi + TOPLEVEL_STATE]
    test eax, TOPLEVEL_STATE_FULLSCREEN
    jz .false
    mov eax, 1
    leave
    ret
.false:
    xor eax, eax
    leave
    ret

global toplevel_is_tiled
toplevel_is_tiled:
    PROLOGUE
    mov eax, [rdi + TOPLEVEL_STATE]
    test eax, TOPLEVEL_STATE_TILED
    jz .false
    mov eax, 1
    leave
    ret
.false:
    xor eax, eax
    leave
    ret

section .data
global toplevel_version
toplevel_version: dq 0x010000
