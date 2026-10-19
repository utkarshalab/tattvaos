; ============================================================================
; Trust Profiles — Declarative Capability Bundles
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"
%include "inc/caps.inc"

section .text

; ---------------------------------------------------------------------------
; trust_init
;   Initialize trust profile subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global trust_init
trust_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.trust_profiles], 0
    mov qword [rbx + Server.arena], r12

    ; Load built-in profiles
    call trust_create_default_profiles

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; trust_load_profiles
;   Return the number of profiles currently loaded. Built-ins are installed
;   during trust_init; persistent configuration can add profiles through
;   trust_create_profile before clients are admitted.
; ---------------------------------------------------------------------------
global trust_load_profiles
trust_load_profiles:
    PROLOGUE_SAVE rbx
    ASSERT_PTR rdi
    mov rbx, [rdi + Server.trust_profiles]
    xor rax, rax
.count:
    test rbx, rbx
    jz .done
    inc rax
    mov rbx, [rbx + TrustProfile.next]
    jmp .count
.done:
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; trust_create_default_profiles
;   Create built-in trust profiles
; ---------------------------------------------------------------------------
global trust_create_default_profiles
trust_create_default_profiles:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx
    
    ; Create trusted profile
    mov rdi, [rbx + Server.arena]
    mov rsi, TrustProfile_SIZE
    call arena_alloc
    test rax, rax
    jz .fail
    mov r12, rax
    
    mov qword [r12 + TrustProfile.name], trusted_name
    mov qword [r12 + TrustProfile.caps], -1  ; all capabilities
    mov qword [r12 + TrustProfile.quota_mem], 0  ; unlimited
    mov dword [r12 + TrustProfile.quota_surfs], -1
    mov dword [r12 + TrustProfile.quota_buffers], -1
    mov qword [r12 + TrustProfile.rate_msg_sec], 0
    mov qword [r12 + TrustProfile.rate_bytes_sec], 0
    mov byte [r12 + TrustProfile.prompts], PROMPT_NEVER
    mov dword [r12 + TrustProfile.flags], PROFILE_FLAG_NO_PROMPTS | PROFILE_FLAG_UNLIMITED_MEM | PROFILE_FLAG_NO_AUDIT
    
    ; Add to server's trust_profiles list
    mov rax, [rbx + Server.trust_profiles]
    mov [r12 + TrustProfile.next], rax
    mov [rbx + Server.trust_profiles], r12
    
    ; Create standard profile
    mov rdi, [rbx + Server.arena]
    mov rsi, TrustProfile_SIZE
    call arena_alloc
    test rax, rax
    jz .fail
    mov r13, rax
    
    mov qword [r13 + TrustProfile.name], standard_name
    mov qword [r13 + TrustProfile.caps], CAP_DISPLAY | CAP_BUFFER | CAP_SURFACE | CAP_PRESENT | CAP_OUTPUT | CAP_SEAT | CAP_INPUT | CAP_CLIPBOARD
    mov qword [r13 + TrustProfile.quota_mem], 512 * 1024 * 1024
    mov dword [r13 + TrustProfile.quota_surfs], 64
    mov dword [r13 + TrustProfile.quota_buffers], 32
    mov qword [r13 + TrustProfile.rate_msg_sec], 1000
    mov qword [r13 + TrustProfile.rate_bytes_sec], 10 * 1024 * 1024
    mov byte [r13 + TrustProfile.prompts], PROMPT_PRIVILEGED
    mov dword [r13 + TrustProfile.flags], 0
    
    mov rax, [rbx + Server.trust_profiles]
    mov [r13 + TrustProfile.next], rax
    mov [rbx + Server.trust_profiles], r13
    
    ; Create sandboxed profile
    mov rdi, [rbx + Server.arena]
    mov rsi, TrustProfile_SIZE
    call arena_alloc
    test rax, rax
    jz .fail
    mov r14, rax
    
    mov qword [r14 + TrustProfile.name], sandboxed_name
    mov qword [r14 + TrustProfile.caps], CAP_DISPLAY | CAP_BUFFER | CAP_SURFACE | CAP_PRESENT
    mov qword [r14 + TrustProfile.quota_mem], 128 * 1024 * 1024
    mov dword [r14 + TrustProfile.quota_surfs], 16
    mov dword [r14 + TrustProfile.quota_buffers], 8
    mov qword [r14 + TrustProfile.rate_msg_sec], 100
    mov qword [r14 + TrustProfile.rate_bytes_sec], 1024 * 1024
    mov byte [r14 + TrustProfile.prompts], PROMPT_ALL
    mov dword [r14 + TrustProfile.flags], 0
    
    mov rax, [rbx + Server.trust_profiles]
    mov [r14 + TrustProfile.next], rax
    mov [rbx + Server.trust_profiles], r14
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.fail:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; trust_create_profile
;   Create custom trust profile
;   IN: rdi=server*, rsi=name, rdx=caps, rcx=memory quota,
;       r8=surface quota, r9=buffer quota, r10=messages/sec,
;       r11=bytes/sec
;   OUT: rax=TrustProfile*, negative error
; ---------------------------------------------------------------------------
global trust_create_profile
trust_create_profile:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp], r9
    mov [rsp + 8], r10
    mov [rsp + 16], r11
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, r12
    call trust_get_profile
    test rax, rax
    jnz .exists

    mov rdi, [rbx + Server.arena]
    mov rsi, TrustProfile_SIZE
    call arena_alloc
    test rax, rax
    jz .create_oom
    mov rdi, rax
    mov [rdi + TrustProfile.caps], r13
    mov [rdi + TrustProfile.quota_mem], r14
    mov dword [rdi + TrustProfile.quota_surfs], r15d
    mov eax, [rsp]
    mov [rdi + TrustProfile.quota_buffers], eax
    mov rax, [rsp + 8]
    mov [rdi + TrustProfile.rate_msg_sec], rax
    mov rax, [rsp + 16]
    mov [rdi + TrustProfile.rate_bytes_sec], rax
    mov byte [rdi + TrustProfile.prompts], PROMPT_PRIVILEGED
    mov dword [rdi + TrustProfile.flags], 0
    mov [rsp + 24], rdi

    ; Profiles own their names; callers may release configuration buffers.
    mov rdi, r12
    call str_len
    test rax, rax
    jz .bad_name
    inc rax
    mov r15, rax
    mov rdi, [rbx + Server.arena]
    mov rsi, r15
    call arena_alloc
    test rax, rax
    jz .create_oom
    mov r13, rax
    mov rdi, r13
    mov rsi, r12
    mov rdx, r15
    call memcopy

    mov rdi, [rsp + 24]
    mov [rdi + TrustProfile.name], r13
    mov rax, [rbx + Server.trust_profiles]
    mov [rdi + TrustProfile.next], rax
    mov [rbx + Server.trust_profiles], rdi
    mov rax, rdi
    jmp .create_done
.exists:
    mov rax, -(EEXIST)
    jmp .create_done
.create_oom:
    mov rax, -(ENOMEM)
    jmp .create_done
.bad_name:
    mov rax, -(EINVAL)
.create_done:
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; trust_get_profile
;   Get profile by name
;   IN: rdi=server*, rsi=NUL-terminated name
;   OUT: rax=TrustProfile* or 0
; ---------------------------------------------------------------------------
global trust_get_profile
trust_get_profile:
    PROLOGUE_SAVE rbx, r12
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov rbx, [rdi + Server.trust_profiles]
    mov r12, rsi
.find:
    test rbx, rbx
    jz .not_found
    mov rdi, [rbx + TrustProfile.name]
    mov rsi, r12
    call str_cmp
    test rax, rax
    jz .found
    mov rbx, [rbx + TrustProfile.next]
    jmp .find
.found:
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12
    ret
.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data

trusted_name:     db "trusted", 0
standard_name:    db "standard", 0
sandboxed_name:   db "sandboxed", 0

global trust_version
trust_version: dq 0x010000
