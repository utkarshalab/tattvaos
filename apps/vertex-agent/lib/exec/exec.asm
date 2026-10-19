%ifndef GUARD_VERTEX_EXEC_ASM
%define GUARD_VERTEX_EXEC_ASM
; =============================================================================
; vertex-agent — Exec/Attach Handler
; =============================================================================
; Exec: Run command in running container (CRI: Exec)
; Attach: Attach to running container's stdin/stdout/stderr (CRI: Attach)
; PortForward: Forward local port to pod (CRI: PortForward)
; Uses PTY pairs + fiber stream multiplexing
; =============================================================================

[BITS 64]

%include "lib/ulib/ring.inc"
%include "lib/ulog/ulog.inc"
%include "kernel/sched/fiber.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_exec_init — Initialize exec handler
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_exec_init
vertex_exec_init:
    push rbx
    push r12

    ; Exec session map (exec_id -> exec_session)
    mov rdi, 1024
    call map_create
    test rax, rax
    jz .fail
    mov [exec_session_map], rax

    ; Attach session map
    mov rdi, 512
    call map_create
    test rax, rax
    jz .fail
    mov [attach_session_map], rax

    ; Port forward session map
    mov rdi, 256
    call map_create
    test rax, rax
    jz .fail
    mov [portfwd_session_map], rax

    pop r12
    pop rbx
    mov rax, 1
    ret

.fail:
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_exec_create — Create exec session (CRI: Exec)
; Inputs:
;   RDI = container_id
;   RSI = exec_config (BXP: cmd, args, env, tty, stdin, stdout, stderr)
; Returns: RAX = exec_id, or 0
; -----------------------------------------------------------------------------
global vertex_exec_create
vertex_exec_create:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi      ; container_id
    mov r13, rsi      ; exec_config

    ; 1. Find container
    mov rdi, [container_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail
    mov rbx, rax      ; container_state

    ; 2. Check container is running
    cmp dword [rbx + container_state.status], CONTAINER_RUNNING
    jne .fail_not_running

    ; 3. Parse exec config
    call vertex_exec_parse_config
    test rax, rax
    jz .fail

    ; 4. Generate exec ID
    call vertex_gen_uuid
    mov r14, rax      ; exec_id

    ; 5. Create PTY pair
    call vertex_pty_create_pair
    test rax, rax
    jz .fail_pty
    mov r12, rax      ; master_fd
    mov r13, rdx      ; slave_fd

    ; 6. Spawn exec fiber in container's namespace
    ;    Entry = user command, with slave_fd as stdin/stdout/stderr
    mov rdi, exec_fiber_entry
    mov rsi, r13      ; slave_fd
    mov rdx, PRIO_HIGH
    mov rcx, FIBER_RESTART_NEVER
    call fiber_create
    test rax, rax
    jz .fail_fiber
    mov rbx, rax      ; exec_fiber

    ; 7. Set exec fiber's subject = container subject (same capabilities)
    mov rdi, rbx
    mov rsi, [container_subject]
    call fiber_set_subject

    ; 8. Store exec session
    call vertex_exec_store_session

    ; 9. Return exec_id
    mov rax, r14
    jmp .done

.fail_fiber:
    call vertex_pty_close
.fail_pty:
.fail_not_running:
.fail:
    xor rax, rax

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_exec_start — Start exec session (CRI: Exec start)
; Inputs: RDI = exec_id, RSI = stdin_stream, RDX = stdout_stream, RCX = stderr_stream
; -----------------------------------------------------------------------------
global vertex_exec_start
vertex_exec_start:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi      ; exec_id
    mov r13, rsi      ; stdin stream
    mov r14, rdx      ; stdout stream
    mov r15, rcx      ; stderr stream

    mov rdi, [exec_session_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail

    ; Store stream handles
    mov [rax + exec_session.stdin], r13
    mov [rax + exec_session.stdout], r14
    mov [rax + exec_session.stderr], r15

    ; Start the fiber
    mov rdi, [rax + exec_session.fiber]
    call fiber_resume

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rax, 1
    ret

.fail:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_exec_resize — Resize PTY (CRI: Exec resize)
; Inputs: RDI = exec_id, RSI = height, RDX = width
; -----------------------------------------------------------------------------
global vertex_exec_resize
vertex_exec_resize:
    push rbx

    mov rdi, [exec_session_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail

    ; Send SIGWINCH to exec fiber
    mov rdi, [rax + exec_session.fiber]
    mov rsi, SIGWINCH
    call fiber_signal

    ; Update PTY winsize
    mov rdi, [rax + exec_session.master_fd]
    mov rsi, rsi      ; height
    mov rdx, rdx      ; width
    call vertex_pty_set_winsize

    pop rbx
    mov rax, 1
    ret

.fail:
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_attach — Attach to container (CRI: Attach)
; Inputs:
;   RDI = container_id
;   RSI = stdin_stream, RDX = stdout_stream, RCX = stderr_stream
;   R8 = tty (bool), R9 = detach_keys
; -----------------------------------------------------------------------------
global vertex_attach
vertex_attach:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi      ; container_id
    mov r13, rsi      ; stdin
    mov r14, rdx      ; stdout
    mov r15, rcx      ; stderr

    ; 1. Find container
    mov rdi, [container_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail

    ; 2. Generate attach ID
    call vertex_gen_uuid
    mov rbx, rax

    ; 3. Get container's existing PTY (from main process)
    mov rdi, [rax + container_state.pty_master]
    test rdi, rdi
    jz .fail_no_pty

    ; 4. Create attach session (multiplex streams)
    call vertex_attach_create_session

    ; 5. Start stream multiplexing fiber
    mov rdi, vertex_attach_mux_fiber
    mov rsi, rbx
    mov rdx, PRIO_HIGH
    mov rcx, FIBER_RESTART_NEVER
    call fiber_create

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rax, rbx
    ret

.fail_no_pty:
.fail:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_port_forward — Port forward (CRI: PortForward)
; Delegates to network manager
; -----------------------------------------------------------------------------
global vertex_port_forward
vertex_port_forward:
    ; Handled by vertex_network_port_forward
    jmp vertex_network_port_forward


; -----------------------------------------------------------------------------
; Exec fiber entry
; -----------------------------------------------------------------------------
exec_fiber_entry:
    ; RDI = slave_fd (PTY)
    ; RSI = exec_config (cmd, args, env)

    ; 1. Make slave_fd controlling terminal
    call vertex_pty_make_controlling

    ; 2. Dup slave_fd to stdin/stdout/stderr
    mov rdi, rdi
    mov rsi, 0
    call sys_dup2
    mov rsi, 1
    call sys_dup2
    mov rsi, 2
    call sys_dup2

    ; 3. Close original slave_fd
    call sys_close

    ; 4. Exec user command
    ;    (In unikernel: direct call to command fiber entry)
    call vertex_exec_user_command

    ; 5. Exit with return code
    call fiber_exit

    ret


; -----------------------------------------------------------------------------
; Attach mux fiber
; -----------------------------------------------------------------------------
vertex_attach_mux_fiber:
    ; Multiplex container PTY <-> client streams
    ; Uses ring buffers for bidirectional copy
    ret


; -----------------------------------------------------------------------------
; PTY operations
; -----------------------------------------------------------------------------

vertex_pty_create_pair:
    ; Returns: RAX = master_fd, RDX = slave_fd
    xor rax, rax
    ret

vertex_pty_close:
    ret

vertex_pty_make_controlling:
    ret

vertex_pty_set_winsize:
    ret


; -----------------------------------------------------------------------------
; Data structures
; -----------------------------------------------------------------------------
struc exec_session
    .exec_id          resq 1
    .container_id     resq 1
    .fiber            resq 1
    .master_fd        resq 1
    .slave_fd         resq 1
    .stdin            resq 1
    .stdout           resq 1
    .stderr           resq 1
    .tty              resb 1
    .exit_code        resd 1
    .started_ns       resq 1
endstruc

struc attach_session
    .attach_id        resq 1
    .container_id     resq 1
    .mux_fiber        resq 1
    .stdin_ring       resq 1
    .stdout_ring      resq 1
    .stderr_ring      resq 1
    .detach_keys      resq 1
endstruc

section .data
align 8
exec_session_map:       dq 0
attach_session_map:     dq 0
portfwd_session_map:    dq 0

container_map:          dq 0        ; from container.asm
container_subject:      dq 0

%endif ; GUARD_VERTEX_EXEC_ASM