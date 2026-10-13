; ============================================================================
; Rules — Window Rules Engine (Per-App Window Matching)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define Rule_size    80
%define RULE_PATTERN_APP_ID     0
%define RULE_PATTERN_TITLE      1
%define RULE_PATTERN_CLASS      2
%define RULE_PATTERN_ROLE       3
%define RULE_ACTION_NONE        0
%define RULE_ACTION_WORKSPACE   1
%define RULE_ACTION_STATE       2
%define RULE_ACTION_FLOATING    3
%define RULE_ACTION_DECORATION  4
%define RULE_ACTION_POSITION    5
%define RULE_ACTION_SIZE        6
%define RULE_ACTION_OPACITY     7
%define RULE_ACTION_FOCUS       6
%define MATCH_EXACT     0
%define MATCH_CONTAINS  1
%define MATCH_REGEX     2
%define MATCH_WILDCARD  3

section .text

struc Rule
    .pattern:           resq 1
    .pattern_type:      resd 1
    .workspace:         resd 1
    .state:             resd 1
    .floating:          resb 1
    .fullscreen:        resb 1
    .maximized:         resb 1
    .minimized:         resb 1
    .tiled:             resb 1
    .decorated:         resb 1
    .border:            resb 1
    .workspace_num:     resd 1
    .monitor:           resd 1
    .position_x:        resd 1
    .position_y:        resd 1
    .width:             resd 1
    :height:            resd 1
    .opacity:           resd 1
    .focus:             resb 1
    .next:              resq 1
endstruc




; ---------------------------------------------------------------------------
; rules_init
; ---------------------------------------------------------------------------
global rules_init
rules_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.rules], 0
    mov qword [rbx + Server.rule_count], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; rules_add
;   Add window rule
; ---------------------------------------------------------------------------
global rules_add
rules_add:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Allocate rule
    mov rdi, [rbx + Server.arena]
    mov rsi, Rule_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Fill rule
    mov qword [rbx + Rule.pattern], r12
    mov dword [rbx + Rule.pattern_type], r13d
    mov dword [rbx + Rule.workspace], r14d
    mov dword [rbx + Rule.state], 0
    mov byte [rbx + Rule.floating], 0
    mov byte [rbx + Rule.fullscreen], 0
    mov byte [rbx + Rule.maximized], 0
    mov byte [rbx + Rule.minimized], 0
    mov byte [rbx + Rule.tiled], 0
    mov byte [rbx + Rule.decorated], 1
    mov byte [rbx + Rule.border], 1
    mov dword [rbx + Rule.workspace_num], -1
    mov dword [rbx + Rule.monitor], -1
    mov dword [rbx + Rule.position_x], -1
    mov dword [rbx + Rule.position_y], -1
    mov dword [rbx + Rule.width], -1
    mov dword [rbx + Rule.height], -1
    mov dword [rbx + Rule.opacity], 255
    mov byte [rbx + Rule.focus], 0
    mov qword [rbx + Rule.next], 0

    ; Add to list
    mov rax, [rdi + Server.rules]
    mov [rbx + Rule.next], rax
    mov [rdi + Server.rules], rbx
    inc qword [rdi + Server.rule_count]

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; rules_remove
; ---------------------------------------------------------------------------
global rules_remove
rules_remove:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Find and remove rule
    mov rax, [rdi + Server.rules]
    test rax, rax
    jz .not_found
    cmp rax, r12
    je .remove_head

    mov rbx, rax
.find_loop:
    mov rax, [rax + Rule.next]
    test rax, rax
    jz .not_found
    cmp rax, r12
    je .remove_middle
    mov rbx, rax
    jmp .find_loop

.remove_head:
    mov rax, [rdi + Server.rules]
    mov rsi, [rax + Rule.next]
    mov [rdi + Server.rules], rsi
    jmp .done

.remove_middle:
    mov rax, [rax + Rule.next]
    mov [rbx + Rule.next], rax

.done:
    dec qword [rdi + Server.rule_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; rules_match
;   Match window against rules
;   IN:  rdi = server*, rsi = app_id, rdx = title, rcx = class, r8 = role
;   OUT: rax = matched rule*, 0 if none
; ---------------------------------------------------------------------------
global rules_match
rules_match:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx

    mov rax, [rbx + Server.rules]
    test rax, rax
    jz .no_match

.match_loop:
    ; Check pattern type
    mov r12d, [rax + Rule.pattern_type]
    mov r13, [rax + Rule.pattern]

    cmp r12d, RULE_PATTERN_APP_ID
    je .match_app_id
    cmp r12d, RULE_PATTERN_TITLE
    je .match_title
    cmp r12d, RULE_PATTERN_CLASS
    je .match_class
    cmp r12d, RULE_PATTERN_ROLE
    je .match_role
    jmp .next_rule

.match_app_id:
    test r12, r12
    jz .next_rule
    mov rdi, r13
    mov rsi, r12
    call str_compare
    test rax, rax
    jz .match
    jmp .next_rule

.match_title:
    test r13, r13
    jz .next_rule
    mov rdi, r13
    mov rsi, r12
    call str_compare
    test rax, rax
    jz .match
    jmp .next_rule

.match_class:
    test r14, r14
    jz .next_rule
    mov rdi, r13
    mov rsi, r14
    call str_compare
    test rax, rax
    jz .match
    jmp .next_rule

.match_role:
    test r15, r15
    jz .next_rule
    mov rdi, r13
    mov rsi, r15
    call str_compare
    test rax, rax
    jz .match
    jmp .next_rule

.next_rule:
    mov rax, [rax + Rule.next]
    test rax, rax
    jnz .match_loop

.no_match:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.match:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; rules_apply
;   Apply matched rule to toplevel
; ---------------------------------------------------------------------------
global rules_apply
rules_apply:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Server.rules]
    test rax, rax
    jz .done

.apply_loop:
    ; Apply rule actions
    test byte [rax + Rule.workspace], 1
    jz .check_state
    mov r12d, [rax + Rule.workspace_num]
    test r12d, r12d
    js .check_state
    ; TODO: Move to workspace

.check_state:
    test byte [rax + Rule.state], 1
    jz .check_floating
    mov r12d, [rax + Rule.state]
    ; TODO: Apply state

.check_floating:
    test byte [rax + Rule.floating], 1
    jz .check_fullscreen
    mov r12b, [rax + Rule.floating]
    test r12b, r12b
    jz .check_fullscreen
    ; Set floating
    call states_float

.check_fullscreen:
    test byte [rax + Rule.fullscreen], 1
    jz .check_maximized
    mov r12b, [rax + Rule.fullscreen]
    test r12b, r12b
    jz .check_maximized
    call states_fullscreen

.check_maximized:
    test byte [rax + Rule.maximized], 1
    jz .check_minimized
    mov r12b, [rax + Rule.maximized]
    test r12b, r12b
    jz .check_minimized
    call states_maximize

.check_minimized:
    test byte [rax + Rule.minimized], 1
    jz .check_tiled
    mov r12b, [rax + Rule.minimized]
    test r12b, r12b
    jz .check_tiled
    call states_minimize

.check_tiled:
    test byte [rax + Rule.tiled], 1
    jz .check_decorated
    mov r12b, [rax + Rule.tiled]
    test r12b, r12b
    jz .check_decorated
    call states_tile

.check_decorated:
    test byte [rax + Rule.decorated], 1
    jz .check_position
    mov r12b, [rax + Rule.decorated]
    test r12b, r12b
    jz .check_position
    ; TODO: decoration_set_mode

.check_position:
    mov eax, [rax + Rule.position_x]
    test eax, eax
    js .check_size
    mov edx, [rax + Rule.position_y]
    test edx, edx
    js .check_size
    ; TODO: Move window

.check_size:
    mov eax, [rax + Rule.width]
    test eax, eax
    js .check_opacity
    mov edx, [rax + Rule.height]
    test edx, edx
    js .check_opacity
    ; TODO: Resize window

.check_opacity:
    mov eax, [rax + Rule.opacity]
    cmp eax, 255
    jle .check_focus
    ; TODO: Set opacity

.check_focus:
    test byte [rax + Rule.focus], 1
    jz .next_rule
    ; Focus window
    mov rdi, [rbx + Server.focus]
    mov rsi, rdi
    call focus_set

.next_rule:
    mov rax, [rax + Rule.next]
    test rax, rax
    jnz .apply_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global rules_version
rules_version: dq 0x010000
