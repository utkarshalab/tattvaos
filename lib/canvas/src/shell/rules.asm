; ============================================================================
; Rules — Window Rules Engine (Per-App Window Matching)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

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
%define RULE_ACTION_FOCUS       8
%define MATCH_EXACT     0
%define MATCH_CONTAINS  1
%define MATCH_REGEX     2
%define MATCH_WILDCARD  3

section .text

; ---------------------------------------------------------------------------
; rules_init
;   Initialize rules engine
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global rules_init
rules_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.rules], 0
    mov qword [rbx + Server.rules_count], 0
    mov qword [rbx + Server.arena], r12

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; rule_create
;   Create new window rule
;   IN:  rdi = server*, rsi = pattern_type, rdx = pattern, rcx = action, r8 = action_data, r9 = priority
;   OUT: rax = rule*, negative error
; ---------------------------------------------------------------------------
global rule_create
rule_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp,16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp],r9d
    ASSERT_PTR rbx

    ; Allocate rule
    mov rdi, [rbx + Server.arena]
    mov rsi, Rule_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r11,rax

    ; Initialize rule
    mov [r11 + Rule.pattern_type],r12d
    mov [r11 + Rule.pattern],r13
    mov [r11 + Rule.action],r14d
    mov [r11 + Rule.action_data],r15
    mov eax,[rsp]
    mov [r11 + Rule.priority],eax
    mov dword [r11 + Rule.enabled],1

    ; Add to server's rule list
    mov rax, [rbx + Server.rules]
    mov [r11 + Rule.next],rax
    mov [rbx + Server.rules],r11
    inc qword [rbx + Server.rules_count]

    mov rax,r11
    add rsp,16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    add rsp,16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; rule_destroy
; ---------------------------------------------------------------------------
global rule_destroy
rule_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Remove from server's rule list
    mov rax, [rbx + Server.rules]
    test rax, rax
    jz .not_found

    cmp rax, r12
    je .remove_head

    mov r13, rax
.find_loop:
    mov rax, [rax + Rule.next]
    test rax, rax
    jz .not_found
    cmp rax, r12
    je .remove_middle
    mov r13, rax
    jmp .find_loop

.remove_head:
    mov rax, [r12 + Rule.next]
    mov [rbx + Server.rules], rax
    jmp .destroy

.remove_middle:
    mov rax, [r12 + Rule.next]
    mov [r13 + Rule.next], rax

.destroy:
    ; Free rule
    mov rdi, [rbx + Server.arena]
    mov rsi, r12
    call arena_free

    dec qword [rbx + Server.rules_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx,r12,r13
    ret

; ---------------------------------------------------------------------------
; rule_match
;   Check if surface matches rule
; ---------------------------------------------------------------------------
global rule_match
rule_match:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    cmp dword [rbx + Rule.enabled],0
    je .no
    mov rdi,[rbx + Rule.pattern]
    test rdi,rdi
    jz .no
    mov eax,[rbx + Rule.pattern_type]
    cmp eax,RULE_PATTERN_APP_ID
    je .app
    cmp eax,RULE_PATTERN_TITLE
    je .title
    cmp eax,RULE_PATTERN_CLASS
    je .external
    cmp eax,RULE_PATTERN_ROLE
    jne .no
.external:
    mov rsi,r13
    jmp .compare
.app:
    mov rsi,[r12 + Toplevel.app_id]
    jmp .compare
.title:
    mov rsi,[r12 + Toplevel.title]
.compare:
    test rsi,rsi
    jz .no
    call str_cmp
    test rax,rax
    setz al
    movzx eax,al
    jmp .out
.no:
    xor eax,eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; rule_apply
;   Apply rule to surface
; ---------------------------------------------------------------------------
global rule_apply
rule_apply:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp dword [rbx + Rule.enabled],0
    je .disabled
    mov eax,[rbx + Rule.action]
    cmp eax,RULE_ACTION_NONE
    je .ok
    cmp eax,RULE_ACTION_WORKSPACE
    je .workspace
    cmp eax,RULE_ACTION_STATE
    je .state
    cmp eax,RULE_ACTION_FLOATING
    je .floating
    cmp eax,RULE_ACTION_DECORATION
    je .decoration
    cmp eax,RULE_ACTION_POSITION
    je .position
    cmp eax,RULE_ACTION_SIZE
    je .size
    cmp eax,RULE_ACTION_OPACITY
    je .unsupported
    jmp .unsupported
.workspace:
    mov rax,[rbx + Rule.action_data]
    mov [r12 + Toplevel.workspace],rax
    jmp .ok
.state:
    mov rsi,[rbx + Rule.action_data]
    mov rdi,r12
    call states_set
    jmp .out
.floating:
    mov rdi,r12
    call states_float
    jmp .out
.decoration:
    mov rdi,[r12 + Toplevel.decoration]
    test rdi,rdi
    jz .unsupported
    mov rsi,[rbx + Rule.action_data]
    call decoration_set_mode
    jmp .out
.position:
    mov rax,[rbx + Rule.action_data]
    mov rdi,r12
    mov esi,eax
    shr rax,32
    mov edx,eax
    call toplevel_set_position
    jmp .out
.size:
    mov rax,[rbx + Rule.action_data]
    test eax,eax
    jz .unsupported
    mov [r12 + Toplevel.pending_width],eax
    shr rax,32
    test eax,eax
    jz .unsupported
    mov [r12 + Toplevel.pending_height],eax
    mov byte [r12 + Toplevel.pending_state],1
    mov rdi,r12
    call toplevel_schedule_configure
    jmp .out
.ok:
    xor eax,eax
    jmp .out
.disabled:
    mov rax,-EPERM
    jmp .out
.unsupported:
    mov rax,-EINVAL
.out:
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global rules_version
rules_version: dq 0x010000
