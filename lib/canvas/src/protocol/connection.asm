; ============================================================================
; Client Connection — Connection Management, Authentication, Event Loop
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/protocol.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; ClientConn Struct
; ============================================================================
%define ClientConn_SERVER_CHAN   0
%define ClientConn_TX_RING       8
%define ClientConn_RX_RING       16
%define ClientConn_HANDLE_TX     24
%define ClientConn_HANDLE_RX     32
%define ClientConn_CAPS_WANTED   40
%define ClientConn_CAPS_GRANTED  48
%define ClientConn_NEXT_OBJ      56
%define ClientConn_ARENA         64
%define ClientConn_SIZE          72

; ============================================================================
; canvas_connect
;   Accept new client connection
; ============================================================================
global canvas_connect
canvas_connect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi       ; server
    mov r12, rsi       ; channel
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate client connection
    mov rdi, 72  ; ClientConn_SIZE
    mov rsi, [rbx + Server_ARENA]
    call arena_alloc
    test rax, rax
    jz .oom

    mov r13, rax        ; client_conn
    mov r14, rbx        ; server
    mov r15, r12        ; channel

    ; Initialize client connection
    mov qword [r13 + ClientConn_SERVER_CHAN], r15
    mov qword [r13 + ClientConn_TX_RING], 0
    mov qword [r13 + ClientConn_RX_RING], 0
    mov qword [r13 + ClientConn_HANDLE_TX], 0
    mov qword [r13 + ClientConn_HANDLE_RX], 0
    mov dword [r13 + ClientConn_CAPS_WANTED], 0
    mov dword [r13 + ClientConn_CAPS_GRANTED], 0
    mov dword [r13 + ClientConn_NEXT_OBJ], 1
    mov qword [r13 + ClientConn_ARENA], [rbx + Server_ARENA]

    ; Allocate TX ring buffer
    mov rdi, [rbx + Server_ARENA]
    mov rsi, 65536
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r13 + ClientConn_TX_RING], rax

    ; Initialize TX ring
    mov qword [rax + RingBuffer_BUFFER], rax
    add rax, 4096
    mov qword [rax + RingBuffer_READ_POS], 0
    mov qword [rax + RingBuffer_WRITE_POS], 0
    mov qword [rax + RingBuffer_CAPACITY], 65536
    mov qword [rax + RingBuffer_MASK], 65535

    ; Allocate RX ring buffer
    mov rdi, [rbx + Server_ARENA]
    mov rsi, 65536
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r13 + ClientConn_RX_RING], rax

    ; Initialize RX ring
    mov qword [rax + RingBuffer_BUFFER], rax
    add rax, 4096
    mov qword [rax + RingBuffer_READ_POS], 0
    mov qword [rax + RingBuffer_WRITE_POS], 0
    mov qword [rax + RingBuffer_CAPACITY], 65536
    mov qword [rax + RingBuffer_MASK], 65535

    ; Allocate handle tables
    call .alloc_handle_tables

    ; Send initial events (version, etc.)
    call .send_initial_events

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -ENOMEM
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.alloc_handle_tables:
    ; Allocate TX handle table
    mov rdi, [rbx + Server_ARENA]
    mov rsi, 4096 * 8  ; 4096 handles * 8 bytes
    call arena_alloc
    test rax, rax
    jz .fail
    mov [r13 + ClientConn_HANDLE_TX], rax

    ; Allocate RX handle table
    mov rdi, [rbx + Server_ARENA]
    mov rsi, 4096 * 8
    call arena_alloc
    test rax, rax
    jz .fail
    mov [r13 + ClientConn_HANDLE_RX], rax

    xor rax, rax
    ret

.fail:
    mov rax, -ENOMEM
    ret

.send_initial_events:
    ; The first object is always the display; global enumeration is requested
    ; explicitly through DISPLAY_GET_REGISTRY.
    mov dword [r13 + ClientConn_NEXT_OBJ], OBJECT_ID_DISPLAY + 1
    xor eax, eax
    ret

; ============================================================================
; canvas_disconnect
;   Disconnect client
; ============================================================================
global canvas_disconnect
canvas_disconnect:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Destroy all client objects
    call .destroy_objects

    ; Free ring buffers
    mov rax, [rbx + ClientConn_TX_RING]
    test rax, rax
    jz .tx_done
    ; arena_free would be called here
.tx_done:
    mov rax, [rbx + ClientConn_RX_RING]
    test rax, rax
    jz .rx_done
.rx_done:

    ; Free handle tables
    mov rax, [rbx + ClientConn_HANDLE_TX]
    test rax, rax
    jz .tx_ht_done
    ; arena_free
.tx_ht_done:
    mov rax, [rbx + ClientConn_HANDLE_RX]
    test rax, rax
    jz .rx_ht_done
.rx_ht_done:

    ; Free client connection struct
    ; arena_free would be called here

    xor rax, rax
    leave
    ret

; ============================================================================
; canvas_process_events
;   Process incoming events for client
; ============================================================================
global canvas_process_events
canvas_process_events:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Read messages from RX ring
    mov rdi, [rbx + ClientConn_RX_RING]
    call wire_read_message
    test rax, rax
    jnz .no_message

    ; Validate message
    mov rdi, rax
    call wire_validate_message
    test rax, rax
    jnz .invalid_message

    ; Dispatch message
    call .dispatch_message

    ; Process next
    jmp canvas_process_events

.no_message:
    xor rax, rax
    leave
    ret

.invalid_message:
    ; Send protocol error
    call .send_protocol_error
    xor rax, rax
    leave
    ret

; ============================================================================
; .dispatch_message
;   Dispatch message to handler
; ============================================================================
.dispatch_message:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi       ; message buffer
    ASSERT_PTR rbx

    ; Get object and opcode
    movzx r12, word [rdi + MESSAGE_OPCODE_OFFSET]
    mov r13, [rdi + MESSAGE_SENDER_OFFSET]  ; object_id

    ; Resolve object
    call handle_resolve
    test rax, rax
    jz .bad_object

    ; Dispatch based on interface
    mov r12, [rax + Object_INTERFACE_ID]
    mov r13d, word [rbx + MESSAGE_OPCODE_OFFSET]

    ; Dispatch table (simplified)
    cmp r12, INTERFACE_DISPLAY
    je .dispatch_display
    cmp r12, INTERFACE_SURFACE
    je .dispatch_surface
    cmp r12, INTERFACE_SEAT
    je .dispatch_seat
    cmp r12, INTERFACE_POINTER
    je .dispatch_pointer
    cmp r12, INTERFACE_KEYBOARD
    je .dispatch_keyboard
    cmp r12, INTERFACE_TOUCH
    je .dispatch_touch
    cmp r12, INTERFACE_OUTPUT
    je .dispatch_output
    cmp r12, INTERFACE_SHELL_SURFACE
    je .dispatch_shell_surface
    cmp r12, INTERFACE_LAYER_SURFACE
    je .dispatch_layer_surface
    cmp r12, INTERFACE_POPUP
    je .dispatch_popup
    cmp r12, INTERFACE_DATA_DEVICE
    je .dispatch_data_device
    cmp r12, INTERFACE_DATA_SOURCE
    je .dispatch_data_source
    cmp r12, INTERFACE_DRAG
    je .dispatch_drag
    cmp r12, INTERFACE_TEXT_INPUT
    je .dispatch_text_input
    cmp r12, INTERFACE_LAYER_SURFACE
    je .dispatch_layer_surface
    cmp r12, INTERFACE_LAYER
    je .dispatch_layer
    cmp r12, INTERFACE_LAYER_SHELL
    je .dispatch_layer_shell

    ; Unknown interface
    mov rax, -ENOTSUP
    EPILOGUE_RESTORE rbx
    ret

.bad_object:
    mov rax, -ENOENT
    EPILOGUE_RESTORE rbx
    ret

; Legacy per-interface labels retained for source compatibility.
.dispatch_display:
    jmp .dispatch_done
.dispatch_surface:
    jmp .dispatch_done
.dispatch_seat:
    jmp .dispatch_done
.dispatch_pointer:
    jmp .dispatch_done
.dispatch_keyboard:
    jmp .dispatch_done
.dispatch_touch:
    jmp .dispatch_done
.dispatch_output:
    jmp .dispatch_done
.dispatch_shell_surface:
    jmp .dispatch_done
.dispatch_layer_surface:
    jmp .dispatch_done
.dispatch_popup:
    jmp .dispatch_done
.dispatch_data_device:
    jmp .dispatch_done
.dispatch_data_source:
    jmp .dispatch_done
.dispatch_drag:
    jmp .dispatch_done
.dispatch_text_input:
    jmp .dispatch_done
.dispatch_layer_surface:
    jmp .dispatch_done
.dispatch_layer:
    jmp .dispatch_done
.dispatch_layer_shell:
    jmp .dispatch_done

.dispatch_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global connection_version
connection_version: dq 0x010000
