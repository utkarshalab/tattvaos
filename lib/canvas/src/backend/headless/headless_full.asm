; ============================================================================
; Headless Backend — Complete Implementation
; Frames kept in memory, no display hardware
; ============================================================================
; An output's framebuffer is a memory region of BGRA pixels, read by whoever
; wants the frame (tests, remote sharing). A new or resized framebuffer is
; wholly damaged, so the next composite paints all of it.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/fixed.inc"
%include "inc/image.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern fence_signal
extern region_add_rect
extern region_init

section .text

; ---------------------------------------------------------------------------
; headless_init
;   Initialize headless backend
;   IN:  rdi = backend* (arena and server already set), rsi = config*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global headless_init
headless_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov r13, [rbx + Backend.arena]
    mov r14, [rbx + Backend.server]

    ; Zero backend state
    mov rdi, rbx
    mov rcx, Backend_size
    xor eax, eax
    rep stosb

    mov [rbx + Backend.arena], r13
    mov [rbx + Backend.server], r14
    mov [rbx + Backend.config], r12

    ; Create virtual frame clock
    mov rdi, r13
    mov rsi, FrameClock_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Backend.frame_clock], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; headless_framebuffer
;   Give an output a framebuffer of width x height, freeing any old one, and
;   damage all of it
;   IN:  rdi = output*, rsi = width, rdx = height
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
headless_framebuffer:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 24                         ; a rect; 16-byte aligned
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx

    mov rdi, [rbx + Output.fb_region]
    test rdi, rdi
    jz .allocate
    call ut_mem_free
    mov qword [rbx + Output.fb_region], 0
.allocate:
    lea rdi, [r12 * 4]
    imul rdi, r13
    xor esi, esi
    call ut_mem_alloc
    test rax, rax
    js .out
    mov [rbx + Output.framebuffer], rax
    mov [rbx + Output.fb_region], r8
    mov [rbx + Output.width], r12d
    mov [rbx + Output.height], r13d
    lea rax, [r12 * 4]
    mov [rbx + Output.stride], rax

    mov qword [rsp], 0                  ; x, y
    mov [rsp + 8], r12d
    mov [rsp + 12], r13d
    mov rdi, [rbx + Output.damage]
    mov rsi, rsp
    call region_add_rect
.out:
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; headless_deinit
;   Deinitialize headless backend
;   IN:  rdi = backend*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global headless_deinit
headless_deinit:
    PROLOGUE_SAVE rbx
    sub rsp, 8
    mov rbx, [rdi + Backend.outputs]
    mov qword [rdi + Backend.outputs], 0
    mov qword [rdi + Backend.output_count], 0
.next:
    test rbx, rbx
    jz .done
    mov rdi, [rbx + Output.fb_region]
    test rdi, rdi
    jz .no_framebuffer
    call ut_mem_free
    mov qword [rbx + Output.fb_region], 0
.no_framebuffer:
    mov rbx, [rbx + Output.next]
    jmp .next
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; headless_modeset
;   Set display mode on virtual output
;   IN:  rdi = controller*, rsi = output*, rdx = mode*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global headless_modeset
headless_modeset:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rsi
    mov r12, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Validate mode
    mov esi, [r12 + Mode.width]
    mov edx, [r12 + Mode.height]
    test esi, esi
    jz .bad_mode
    test edx, edx
    jz .bad_mode

    cmp esi, [rbx + Output.width]
    jne .resize
    cmp edx, [rbx + Output.height]
    je .done
.resize:
    mov rdi, rbx
    call headless_framebuffer
    test rax, rax
    js .out
.done:
    mov [rbx + Output.current_mode], r12
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12
    ret
.bad_mode:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; headless_flip
;   Page flip: the frame is already in memory, only the fence remains
;   IN:  rdi = controller*, rsi = output*, rdx = buffer*, rcx = fence*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global headless_flip
headless_flip:
    test rcx, rcx
    jz .done
    mov rdi, [rdi + Backend.server]
    mov rsi, rcx
    sub rsp, 8
    call fence_signal
    add rsp, 8
.done:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; headless_vblank_wait
;   Wait for vblank: there is no display to wait for
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global headless_vblank_wait
headless_vblank_wait:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; headless_hotplug
;   Handle hotplug events (simulated)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global headless_hotplug
headless_hotplug:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; headless_cursor
;   Set cursor (no-op for headless)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global headless_cursor
headless_cursor:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; headless_create_virtual_output
;   Create a virtual output for headless backend, last in the output list
;   IN:  rdi = backend*, rsi = width, rdx = height, rcx = format (BGRA only)
;   OUT: rax = output*, 0 on error
; ---------------------------------------------------------------------------
global headless_create_virtual_output
headless_create_virtual_output:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    ; Allocate output structure
    mov rdi, [rbx + Backend.arena]
    mov rsi, Output_size
    call arena_alloc
    test rax, rax
    jz .fail
    mov r14, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, Output_size
    rep stosb
    mov [r14 + Output.backend], rbx
    mov [r14 + Output.controller], rbx
    mov byte [r14 + Output.connected], 1

    mov rdi, [rbx + Backend.arena]
    call region_init
    test rax, rax
    jz .fail
    mov [r14 + Output.damage], rax

    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call headless_framebuffer
    test rax, rax
    js .fail

    ; Last in the list; the server's list is the backend's
    lea rcx, [rbx + Backend.outputs]
.find_end:
    mov rax, [rcx]
    test rax, rax
    jz .append
    lea rcx, [rax + Output.next]
    jmp .find_end
.append:
    mov [rcx], r14
    inc qword [rbx + Backend.output_count]
    mov rax, [rbx + Backend.server]
    test rax, rax
    jz .linked
    mov rcx, [rbx + Backend.outputs]
    mov [rax + Server.outputs], rcx
.linked:
    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.fail:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global headless_backend_version
headless_backend_version: dq 0x010100
