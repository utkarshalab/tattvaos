%ifndef GUARD_DIST_URAFT_RAFT_ASM
%define GUARD_DIST_URAFT_RAFT_ASM
; =============================================================================
; File     : dist/uraft/raft.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Raft consensus — leader election, log replication for
;              distributed Tattva OS clusters.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; raft_init — Initialize Raft consensus module
; Input:  none
; Output: rax = 0 on success
; -----------------------------------------------------------------------------
global raft_init
raft_init:
    ret

; -----------------------------------------------------------------------------
; raft_elect — Start leader election
; Input:  none
; Output: rax = 0 if elected leader, non-zero if follower
; -----------------------------------------------------------------------------
global raft_elect
raft_elect:
    ret

%endif ; GUARD_DIST_URAFT_RAFT_ASM