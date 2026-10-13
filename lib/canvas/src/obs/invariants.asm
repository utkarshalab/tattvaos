; ============================================================================
; Invariants — Scene-Graph Invariant Checks (debug builds, after commit)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define INV_OK              0
%define INV_ZORDER_CYCLE    1
%define INV_DANGLING_PARENT 2
%define INV_BAD_GEOMETRY    3
%define INV_STALE_HANDLE    4

section .text


; ---------------------------------------------------------------------------
; invariants_check_all
;   IN: rdi = server* — OUT: rax = INV_* code
; ---------------------------------------------------------------------------
global invariants_check_all
invariants_check_all:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rdi, rbx
    call invariants_check_surfaces
    test rax, rax
    jnz .fail
    mov rdi, rbx
    call invariants_check_zorder
    test rax, rax
    jnz .fail
    mov rdi, rbx
    call invariants_check_subsurfaces
    test rax, rax
    jnz .fail
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret
.fail:
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; invariants_check_surfaces — every surface has valid geometry + client
; ---------------------------------------------------------------------------
global invariants_check_surfaces
invariants_check_surfaces:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    ; TODO: iterate surface table
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; invariants_check_zorder — z-order is a strict total order (no cycles)
; ---------------------------------------------------------------------------
global invariants_check_zorder
invariants_check_zorder:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; TODO: walk rbtree, verify sorted + unique
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; invariants_check_subsurfaces — every subsurface parent resolves + no cycles
; ---------------------------------------------------------------------------
global invariants_check_subsurfaces
invariants_check_subsurfaces:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; TODO: walk subsurface lists with depth cap
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; invariants_assert — trap with code in debug builds
; ---------------------------------------------------------------------------
global invariants_assert
invariants_assert:
    PROLOGUE
    test rdi, rdi
    jz .ok
    int3
.ok:
    xor rax, rax
    leave
    ret

section .data
global invariants_version
invariants_version: dq 0x010000
