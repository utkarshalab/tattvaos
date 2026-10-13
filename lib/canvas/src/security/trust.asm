; ============================================================================
; Trust Profiles — Declarative Capability Bundles
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define TrustProfile_size    56
%define PROFILE_TRUSTED    0
%define PROFILE_STANDARD   1
%define PROFILE_SANDBOXED  2
%define PROFILE_REMOTE     3
%define PROFILE_KIOSK      4
%define PROFILE_CUSTOM     5
%define PROFILE_FLAG_NO_PROMPTS     (1 << 0)
%define PROFILE_FLAG_UNLIMITED_MEM  (1 << 1)
%define PROFILE_FLAG_NO_AUDIT       (1 << 2)
%define PROMPT_NEVER   0
%define PROMPT_PRIVILEGED 1
%define PROMPT_ALL     2

section .text

struc TrustProfile
    .name:          resq 1
    .caps:          resq 1
    .quota_mem:     resq 1
    .quota_surfs:   resd 1
    .quota_buffers: resd 1
    .rate_msg_sec:  resq 1
    .rate_bytes_sec: resq 1
    .prompts:       resb 1
    .flags:         resd 1
endstruc




; ---------------------------------------------------------------------------
; trust_init
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

    ; Load profiles from config
    call trust_load_profiles

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; trust_load_profiles
; ---------------------------------------------------------------------------
trust_load_profiles:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Load from conf/profiles/*.profile
    ; For now, create default profiles

    call trust_create_default_profiles

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; trust_create_default_profiles
; ---------------------------------------------------------------------------
trust_create_default_profiles:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Trusted profile
    call trust_create_profile
    test rax, rax
    js .fail

    ; Standard profile
    call trust_create_profile
    test rax, rax
    js .fail

    ; Sandboxed profile
    call trust_create_profile
    test rax, rax
    js .fail

    ; Remote profile
    call trust_create_profile
    test rax, rax
    js .fail

    ; Kiosk profile
    call trust_create_profile
    test rax, rax
    js .fail

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.fail:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; trust_create_profile
;   IN: rdi = server*, rsi = arena, rdx = profile_type
; ---------------------------------------------------------------------------
trust_create_profile:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, r12
    mov rsi, TrustProfile_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Fill based on type
    cmp r13d, PROFILE_TRUSTED
    je .trusted
    cmp r13d, PROFILE_STANDARD
    je .standard
    cmp r13d, PROFILE_SANDBOXED
    je .sandboxed
    cmp r13d, PROFILE_REMOTE
    je .remote
    cmp r13d, PROFILE_KIOSK
    je .kiosk

    jmp .custom

.trusted:
    mov qword [rbx + TrustProfile.name], trusted_name
    mov qword [rbx + TrustProfile.caps], 0xFFFFFFFFFFFFFFFF
    mov qword [rbx + TrustProfile.quota_mem], 0
    mov dword [rbx + TrustProfile.quota_surfs], 0xFFFFFFFF
    mov dword [rbx + TrustProfile.quota_buffers], 0xFFFFFFFF
    mov qword [rbx + TrustProfile.rate_msg_sec], 0
    mov qword [rbx + TrustProfile.rate_bytes_sec], 0
    mov byte [rbx + TrustProfile.prompts], PROMPT_NEVER
    jmp .done

.standard:
    mov qword [rbx + TrustProfile.name], standard_name
    mov qword [rbx + TrustProfile.caps], STANDARD_CAPS
    mov qword [rbx + TrustProfile.quota_mem], 64 * 1024 * 1024
    mov dword [rbx + TrustProfile.quota_surfs], 256
    mov dword [rbx + TrustProfile.quota_buffers], 64
    mov qword [rbx + TrustProfile.rate_msg_sec], 1000
    mov qword [rbx + TrustProfile.rate_bytes_sec], 10 * 1024 * 1024
    mov byte [rbx + TrustProfile.prompts], PROMPT_PRIVILEGED
    jmp .done

.sandboxed:
    mov qword [rbx + TrustProfile.name], sandboxed_name
    mov qword [rbx + TrustProfile.caps], CORE_CAPS | CAP_SEAT | CAP_POINTER | CAP_KEYBOARD | CAP_TOUCH | CAP_TABLET | CAP_SHELL
    mov qword [rbx + TrustProfile.quota_mem], 16 * 1024 * 1024
    mov dword [rbx + TrustProfile.quota_surfs], 64
    mov dword [rbx + TrustProfile.quota_buffers], 16
    mov qword [rbx + TrustProfile.rate_msg_sec], 100
    mov qword [rbx + TrustProfile.rate_bytes_sec], 1024 * 1024
    mov byte [rbx + TrustProfile.prompts], PROMPT_ALL
    jmp .done

.remote:
    mov qword [rbx + TrustProfile.name], remote_name
    mov qword [rbx + TrustProfile.caps], STANDARD_CAPS | CAP_REMOTE
    mov qword [rbx + TrustProfile.quota_mem], 32 * 1024 * 1024
    mov dword [rbx + TrustProfile.quota_surfs], 128
    mov dword [rbx + TrustProfile.quota_buffers], 32
    mov qword [rbx + TrustProfile.rate_msg_sec], 500
    mov qword [rbx + TrustProfile.rate_bytes_sec], 5 * 1024 * 1024
    mov byte [rbx + TrustProfile.prompts], PROMPT_ALL
    jmp .done

.kiosk:
    mov qword [rbx + TrustProfile.name], kiosk_name
    mov qword [rbx + TrustProfile.caps], CORE_CAPS | CAP_SEAT | CAP_POINTER | CAP_KEYBOARD | CAP_TOUCH | CAP_TABLET | CAP_SHELL
    mov qword [rbx + TrustProfile.quota_mem], 8 * 1024 * 1024
    mov dword [rbx + TrustProfile.quota_surfs], 1
    mov dword [rbx + TrustProfile.quota_buffers], 2
    mov qword [rbx + TrustProfile.rate_msg_sec], 50
    mov qword [rbx + TrustProfile.rate_bytes_sec], 512 * 1024
    mov byte [rbx + TrustProfile.prompts], PROMPT_NEVER
    jmp .done

.custom:
    ; For custom, caller must fill in
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.done:
    ; Add to profile list
    mov rax, [rdi + Server.trust_profiles]
    mov [rbx + TrustProfile.next], rax
    mov [rdi + Server.trust_profiles], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; trust_get_profile
; ---------------------------------------------------------------------------
global trust_get_profile
trust_get_profile:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Server.trust_profiles]
.find_loop:
    test rax, rax
    jz .not_found
    mov r12, [rax + TrustProfile.name]
    mov rdi, r12
    mov rsi, rsi
    call str_compare
    test rax, rax
    jz .found
    mov rax, [rax + TrustProfile.next]
    jmp .find_loop

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.found:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; trust_assign_profile
; ---------------------------------------------------------------------------
global trust_assign_profile
trust_assign_profile:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [r12 + Client.trust_profile], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .rodata
trusted_name:    db "trusted", 0
standard_name:   db "standard", 0
sandboxed_name:  db "sandboxed", 0
remote_name:     db "remote", 0
kiosk_name:      db "kiosk", 0

section .data
global trust_version
trust_version: dq 0x010000
