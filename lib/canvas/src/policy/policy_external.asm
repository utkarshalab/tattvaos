; ============================================================================
; External Policy Bridge — Bridge to Out-of-Process Window Manager
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/channel.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
extern channel_send
extern channel_recv

; struct offsets (hoisted above use)
%define PolicyExternal_SIZE    56
%define POLICY_OP_CONNECT       1
%define POLICY_OP_LAYOUT        2
%define POLICY_OP_FOCUS         3
%define POLICY_OP_NEW_WINDOW    4
%define POLICY_OP_CLOSE_WINDOW  5
%define POLICY_OP_WORKSPACE     6
%define POLICY_OP_CONFIGURE     7
%define POLICY_OP_TILE          8
%define POLICY_OP_CONFIGURED    9
%define POLICY_OP_RESPONSE      0x8000
%define POLICY_CAP_LAYOUT       1
%define POLICY_CAP_LIFECYCLE    2
%define POLICY_CAP_WORKSPACES   4

section .text

; PolicyExternal struct layout (manual offsets)\n; Offsets defined in inc/struct_offsets.inc\n\n; ----------\n

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

    ; The external policy is another native Canvas client.  Wrap its inbound
    ; message ring in a Channel; no wire ABI or handle translation is needed.
    mov rdi, [r13 + Server.arena]
    mov rsi, 32
    call arena_alloc
    test rax, rax
    jz .fail

    mov qword [rbx + PolicyExternal.channel], rax
    mov rcx, [r12 + Client.rx_ring]
    mov [rax + Channel.msg_ring], rcx
    mov qword [rax + Channel.handle_ring], 0
    mov [rax + Channel.client], r12
    mov [rax + Channel.server], r13

    mov qword [rbx + PolicyExternal.capabilities], POLICY_CAP_LAYOUT | POLICY_CAP_LIFECYCLE | POLICY_CAP_WORKSPACES
    mov rdi, rbx
    mov rsi, POLICY_OP_CONNECT
    lea rdx, [rbx + PolicyExternal.capabilities]
    mov rcx, 8
    call policy_external_send_request

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

    ; Native request header: object id, opcode, flags, payload length.
    sub rsp, 16
    mov rax, [rbx + PolicyExternal.client]
    mov eax, [rax + Client.id]
    mov [rsp + MsgHdr_obj], eax
    mov [rsp + MsgHdr_opcode], r12w
    mov word [rsp + MsgHdr_flags], MsgFlag_NEED_ACK
    mov [rsp + MsgHdr_len], r14d
    mov rsi, rsp
    mov rdx, r13
    xor rcx, rcx
    xor r8d, r8d
    call channel_send
    add rsp, 16

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
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    sub rsp, 16
    mov rdi, [rbx + PolicyExternal.channel]
    test rdi, rdi
    jz .not_connected
    mov rsi, rsp
    mov rdx, r12
    mov rcx, r13
    xor r8d, r8d
    xor r9d, r9d
    call channel_recv
    test rax, rax
    js .out
    cmp word [rsp + MsgHdr_opcode], POLICY_OP_RESPONSE
    je .out
    mov rax, -(EPROTO)
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.not_connected:
    mov rax, -(ENOTCONN)
    jmp .out

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

    test rax, rax
    js .layout_out
    ; Policy processing is event-loop driven.  Consume an already available
    ; reply, but never deadlock the compositor waiting on an external client.
    sub rsp, 64
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 64
    call policy_external_receive_response
    cmp rax, -(EAGAIN)
    jne .layout_received
    xor rax, rax
.layout_received:
    add rsp, 64
.layout_out:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_external_send_layout_request
; ---------------------------------------------------------------------------
policy_external_send_layout_request:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r15, rsi
    mov r13, [r12 + Output.width]
    mov r14, [r12 + Output.height]
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get toplevels
    mov r12, [r12 + Output.toplevels]

    ; Native layout payload: output reference, dimensions, list head, count.
    sub rsp, 32
    mov [rsp], r15
    mov [rsp + 8], r13
    mov [rsp + 16], r14
    mov [rsp + 24], r12
    mov rdx, rsp
    mov rsi, POLICY_OP_LAYOUT
    mov rcx, 32
    mov rdi, rbx
    call policy_external_send_request
    add rsp, 32

    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; policy_external_configure
; ---------------------------------------------------------------------------
global policy_external_configure
policy_external_configure:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    sub rsp, 8
    mov [rsp], r12
    mov rdi, rbx
    mov rsi, POLICY_OP_CONFIGURE
    mov rdx, rsp
    mov rcx, 8
    call policy_external_send_request
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12
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

    sub rsp, 8
    mov [rsp], r12
    mov rdi, rbx
    mov rsi, POLICY_OP_FOCUS
    mov rdx, rsp
    mov rcx, 8
    call policy_external_send_request
    add rsp, 8
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

    sub rsp, 8
    mov [rsp], r12
    mov rdi, rbx
    mov rsi, POLICY_OP_NEW_WINDOW
    mov rdx, rsp
    mov rcx, 8
    call policy_external_send_request
    add rsp, 8
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

    sub rsp, 8
    mov [rsp], r12
    mov rdi, rbx
    mov rsi, POLICY_OP_CLOSE_WINDOW
    mov rdx, rsp
    mov rcx, 8
    call policy_external_send_request
    add rsp, 8
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

    sub rsp, 8
    mov [rsp], r12
    mov rdi, rbx
    mov rsi, POLICY_OP_WORKSPACE
    mov rdx, rsp
    mov rcx, 8
    call policy_external_send_request
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_external_tile_window
; ---------------------------------------------------------------------------
global policy_external_tile_window
policy_external_tile_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    sub rsp, 8
    mov [rsp], r12
    mov rdi, rbx
    mov rsi, POLICY_OP_TILE
    mov rdx, rsp
    mov rcx, 8
    call policy_external_send_request
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_external_window_configured
; ---------------------------------------------------------------------------
global policy_external_window_configured
policy_external_window_configured:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    sub rsp, 8
    mov [rsp], r12
    mov rdi, rbx
    mov rsi, POLICY_OP_CONFIGURED
    mov rdx, rsp
    mov rcx, 8
    call policy_external_send_request
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global policy_external_version
policy_external_version: dq 0x010000
