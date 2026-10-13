; ============================================================================
; External Policy Bridge — Bridge to Out-of-Process Window Manager
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/channel.inc"

; struct offsets (hoisted above use)
%define PolicyExternal_size    56

section .text

struc PolicyExternal
    .base:              resq 1
    .server:            resq 1
    .client:            resq 1
    .channel:           resq 1
    .capabilities:      resq 1
    .pending_requests:  resq 1
endstruc

; ---------------------------------------------------------------------------
; policy_external_init
; ---------------------------------------------------------------------------
global policy_external_init
policy_external_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + PolicyExternal.base], rdi
    mov qword [rbx + PolicyExternal.server], r12
    mov qword [rbx + PolicyExternal.client], r13
    mov qword [rbx + PolicyExternal.channel], 0
    mov qword [rbx + PolicyExternal.capabilities], 0
    mov qword [rbx + PolicyExternal.pending_requests], 0

    ; Set function pointers
    mov qword [rdi + Policy.layout], policy_external_layout
    mov qword [rdi + Policy.configure], policy_external_configure
    mov qword [rdi + Policy.focus_change], policy_external_focus_change
    mov qword [rdi + Policy.new_window], policy_external_new_window
    mov qword [rdi + Policy.close_window], policy_external_close_window
    mov qword [rdi + Policy.workspace_changed], policy_external_workspace_changed
    mov qword [rdi + Policy.tile_window], policy_external_tile_window
    mov qword [rdi + Policy.window_configured], policy_external_window_configured

    ; Create channel to external policy process
    call policy_external_create_channel

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; policy_external_create_channel
; ---------------------------------------------------------------------------
policy_external_create_channel:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, [rbx + PolicyExternal.client]
    mov r13, [rbx + PolicyExternal.server]
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Allocate channel pair
    mov rdi, [r13 + Server.arena]
    mov rsi, 256
    mov rdx, 16
    call channel_init
    test rax, rax
    jnz .fail

    mov qword [rbx + PolicyExternal.channel], rax

    ; Send initial handshake
    ; TODO: Send cw_policy.connect with capabilities

    EPILOGUE_RESTORE rbx, r12, r13
    ret

.fail:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; policy_external_send_request
;   Send request to external policy
; ---------------------------------------------------------------------------
policy_external_send_request:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx

    ; Get channel
    mov rdi, [rbx + PolicyExternal.channel]
    test rdi, rdi
    jz .fail

    ; Send message
    ; TODO: Encode and send via channel

    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.fail:
    mov rax, -(ENOTCONN)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; policy_external_receive_response
; ---------------------------------------------------------------------------
policy_external_receive_response:
    PROLOGUE
    ; TODO: Receive and parse response
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_external_layout
; ---------------------------------------------------------------------------
global policy_external_layout
policy_external_layout:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Send layout request to external policy
    mov rdi, rbx
    mov rsi, r12
    call policy_external_send_layout_request

    ; Wait for response
    ; TODO: Block until response

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_external_send_layout_request
; ---------------------------------------------------------------------------
policy_external_send_layout_request:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, [r12 + Output.width]
    mov r14, [r12 + Output.height]
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get toplevels
    mov r12, [r12 + Output.toplevels]

    ; Build layout request message
    ; TODO: Encode layout request with window geometries

    ; Send via channel
    call policy_external_send_request

    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; policy_external_configure
; ---------------------------------------------------------------------------
global policy_external_configure
policy_external_configure:
    PROLOGUE
    ; Forward to external policy
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_external_focus_change
; ---------------------------------------------------------------------------
global policy_external_focus_change
policy_external_focus_change:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Send focus change event
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_external_new_window
; ---------------------------------------------------------------------------
global policy_external_new_window
policy_external_new_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Send new window event
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_external_close_window
; ---------------------------------------------------------------------------
global policy_external_close_window
policy_external_close_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Send close window event
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_external_workspace_changed
; ---------------------------------------------------------------------------
global policy_external_workspace_changed
policy_external_workspace_changed:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Send workspace changed event
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_external_tile_window
; ---------------------------------------------------------------------------
global policy_external_tile_window
policy_external_tile_window:
    PROLOGUE
    mov rax, -(ENOTSUP)
    leave
    ret

; ---------------------------------------------------------------------------
; policy_external_window_configured
; ---------------------------------------------------------------------------
global policy_external_window_configured
policy_external_window_configured:
    PROLOGUE
    xor rax, rax
    leave
    ret

section .data
global policy_external_version
policy_external_version: dq 0x010000
