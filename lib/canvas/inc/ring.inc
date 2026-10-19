; ============================================================================
; Ring Buffer — Bounded Single-Producer Single-Consumer Ring
; ============================================================================

%ifndef __RING_INC__
%define __RING_INC__

; Ring struct offsets
%define Ring_buffer    0
%define Ring_capacity  8
%define Ring_head      16
%define Ring_tail      24
%define Ring_size      32

%endif ; __RING_INC__