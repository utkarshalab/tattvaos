; =============================================================================
; Tattva OS — security/usrauth/audit.asm
; =============================================================================
; L6 — Tamper-Evident Decision Log.
;
; Implements:
;   - Ring buffer of decision records (`usrauth_audit_record`)
;   - Hash chaining and verification (`usrauth_audit_verify_chain`)
;   - Query helpers (`usrauth_audit_get`, `usrauth_audit_stats`)
;
; Every decision is recorded with the REASON, not merely the outcome. A log
; that says "denied" is nearly useless during an incident; one that says
; "denied by type enforcement" versus "denied because the token epoch was
; stale" points straight at the cause. The distinct USRAUTH_DENY_* codes exist
; for this.
;
; ALLOWS are logged too. A log containing only denials cannot answer the
; question that actually matters after a breach — what did the attacker
; successfully reach.
;
; Each record embeds the hash of its predecessor, so altering or removing any
; entry breaks every hash after it. That makes tampering detectable without
; write-once storage. It does NOT make it preventable: an attacker who controls
; the log can rewrite the whole chain from the edit forward. Detection requires
; the head hash to be anchored somewhere they do not control — periodically
; sealed to the TPM, or replicated off-node.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

%define USRAUTH_AUDIT_SLOTS       512
%define USRAUTH_AUDIT_MASK        (USRAUTH_AUDIT_SLOTS - 1)

section .data
align 64

global usrauth_audit_log
usrauth_audit_log:
    times USRAUTH_AUDIT_SLOTS * usrauth_audit_t_size db 0

usrauth_audit_seq:       dq 0        ; Monotonic; never resets on wrap
usrauth_audit_head:      times 32 db 0   ; Hash of the most recent record
usrauth_audit_allows:    dq 0
usrauth_audit_denials:   dq 0
usrauth_audit_wrapped:   dq 0

section .text

global usrauth_audit_record
global usrauth_audit_get
global usrauth_audit_verify_chain
global usrauth_audit_head_hash
global usrauth_audit_stats

; -----------------------------------------------------------------------------
; usrauth_audit_record
;
; Appends a decision to the chain.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Object id
;   EDX = Object class
;   ECX = Verb bitmask
;   R8D = Verdict (USRAUTH_ALLOW or a USRAUTH_DENY_* code)
;
; Returns:
;   RAX = Sequence number assigned
; -----------------------------------------------------------------------------
align 32
usrauth_audit_record:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi                   ; Subject
    mov r13, rsi                    ; Object
    mov r14d, edx                   ; Class
    mov r15d, ecx                   ; Verb
    mov r11d, r8d                   ; Verdict

    ; Slot from the sequence number; the ring overwrites oldest first.
    mov rax, [usrauth_audit_seq]
    mov r10, rax                    ; Sequence for this record
    and rax, USRAUTH_AUDIT_MASK
    imul rax, usrauth_audit_t_size
    lea rbx, [usrauth_audit_log]
    add rbx, rax

    ; Note the wrap so a reader knows older entries were lost rather than
    ; silently presenting a partial history as complete.
    mov rax, [usrauth_audit_seq]
    cmp rax, USRAUTH_AUDIT_SLOTS
    jb .ar_fill
    inc qword [usrauth_audit_wrapped]

.ar_fill:
    mov [rbx + usrauth_audit_t.seq], r10
    mov dword [rbx + usrauth_audit_t.subject_handle], r12d
    mov [rbx + usrauth_audit_t.object_id], r13
    mov dword [rbx + usrauth_audit_t.object_class], r14d
    mov dword [rbx + usrauth_audit_t.verb], r15d
    mov dword [rbx + usrauth_audit_t.verdict], r11d

    push r11
    call mono_get_nanos
    pop r11
    mov [rbx + usrauth_audit_t.timestamp_ns], rax

    ; Chain to the previous head.
    lea rdi, [rbx + usrauth_audit_t.prev_hash]
    lea rsi, [usrauth_audit_head]
    mov rcx, 4
    rep movsq

    ; Hash covers the record with its own hash field zeroed, so the value is
    ; reproducible by a verifier.
    lea rdi, [rbx + usrauth_audit_t.hash]
    xor rax, rax
    mov rcx, 4
    rep stosq

    mov rdi, rbx
    mov rsi, usrauth_audit_t_size
    lea rdx, [rbx + usrauth_audit_t.hash]
    call sha256_hash

    ; New head.
    lea rdi, [usrauth_audit_head]
    lea rsi, [rbx + usrauth_audit_t.hash]
    mov rcx, 4
    rep movsq

    ; Tally by outcome.
    test r11d, r11d
    jz .ar_allow
    inc qword [usrauth_audit_denials]
    jmp .ar_done
.ar_allow:
    inc qword [usrauth_audit_allows]

.ar_done:
    inc qword [usrauth_audit_seq]

    mov rax, r10
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_audit_get
;
; Fetches a record by sequence number, if still resident in the ring.
;
; Inputs:
;   RDI = Sequence number
;
; Returns:
;   RAX = Record pointer, or 0 when evicted or not yet written
; -----------------------------------------------------------------------------
align 32
usrauth_audit_get:
    mov rax, [usrauth_audit_seq]
    cmp rdi, rax
    jae .ag_missing                 ; Not written yet

    ; Evicted once the ring has moved a full lap past it.
    sub rax, rdi
    cmp rax, USRAUTH_AUDIT_SLOTS
    ja .ag_missing

    mov rax, rdi
    and rax, USRAUTH_AUDIT_MASK
    imul rax, usrauth_audit_t_size
    lea rcx, [usrauth_audit_log]
    add rax, rcx
    ret

.ag_missing:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; usrauth_audit_verify_chain
;
; Recomputes hashes across the resident window and confirms each record links
; to its predecessor.
;
; Detects: modified fields, reordering, and removal. Does NOT detect a wholesale
; rewrite by an attacker holding the log — that requires an external anchor.
;
; Inputs:
;   RDI = First sequence number to check
;   RSI = Number of records to check
;
; Returns:
;   RAX = 0 when intact, else the sequence number of the first bad record
; -----------------------------------------------------------------------------
align 32
usrauth_audit_verify_chain:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64

    mov r12, rdi                    ; Current sequence
    mov r13, rsi                    ; Remaining

.vc_loop:
    test r13, r13
    jz .vc_ok

    mov rdi, r12
    call usrauth_audit_get
    test rax, rax
    jz .vc_next                     ; Evicted: nothing to verify
    mov rbx, rax

    ; Recompute this record's hash with the field zeroed.
    lea rdi, [rsp]
    lea rsi, [rbx + usrauth_audit_t.hash]
    mov rcx, 4
    rep movsq                       ; Save the stored hash

    lea rdi, [rbx + usrauth_audit_t.hash]
    xor rax, rax
    mov rcx, 4
    rep stosq

    mov rdi, rbx
    mov rsi, usrauth_audit_t_size
    lea rdx, [rsp + 32]
    call sha256_hash

    ; Restore the stored hash before comparing, so verification is read-only.
    lea rdi, [rbx + usrauth_audit_t.hash]
    lea rsi, [rsp]
    mov rcx, 4
    rep movsq

    lea rdi, [rbx + usrauth_audit_t.hash]
    lea rsi, [rsp + 32]
    mov rdx, 32
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .vc_bad

    ; Link check: this record's prev_hash must equal the predecessor's hash.
    test r12, r12
    jz .vc_next                     ; Genesis record has no predecessor

    mov rdi, r12
    dec rdi
    call usrauth_audit_get
    test rax, rax
    jz .vc_next                     ; Predecessor evicted

    lea rdi, [rbx + usrauth_audit_t.prev_hash]
    lea rsi, [rax + usrauth_audit_t.hash]
    mov rdx, 32
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .vc_bad

.vc_next:
    inc r12
    dec r13
    jmp .vc_loop

.vc_ok:
    xor rax, rax
    jmp .vc_return

.vc_bad:
    mov rax, r12
    test rax, rax
    jnz .vc_return
    mov rax, 1                      ; Never return 0 for a failure at seq 0

.vc_return:
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_audit_head_hash
;
; Returns the current chain head. Anchor this externally — sealed to the TPM or
; replicated off-node — or the chain proves nothing against an attacker who
; holds the log.
;
; Inputs:
;   RDI = Pointer to a 32-byte output buffer
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_audit_head_hash:
    lea rsi, [usrauth_audit_head]
    mov rcx, 4
    rep movsq
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; usrauth_audit_stats
;
; Inputs:
;   RDI = Pointer to four qwords: total, allows, denials, wraps
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_audit_stats:
    mov rax, [usrauth_audit_seq]
    mov [rdi], rax
    mov rax, [usrauth_audit_allows]
    mov [rdi + 8], rax
    mov rax, [usrauth_audit_denials]
    mov [rdi + 16], rax
    mov rax, [usrauth_audit_wrapped]
    mov [rdi + 24], rax
    xor eax, eax
    ret
