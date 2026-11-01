; ============================================================================
; Ring Buffer — Bounded Single-Producer Single-Consumer Ring
; ============================================================================

%ifndef __RING_INC__
%define __RING_INC__

; Ring struct offsets
struc Ring
    .buffer:                  resq 1
    .capacity:                resq 1
    .mask:                    resq 1
    .head:                    resq 1
    .tail:                    resq 1
    .element_size:            resq 1
    .arena:                   resq 1
endstruc

%endif ; __RING_INC__