; ============================================================================
; Client Events — Public Event API
; ============================================================================

%ifndef __EVENTS_INC__
%define __EVENTS_INC__

; Event types
; Event types
%define INPUT_EVENT_KEY      1
%define INPUT_EVENT_POINTER  2
%define INPUT_EVENT_TOUCH    3
%define INPUT_EVENT_REL      4
%define INPUT_EVENT_ABS      5
%define INPUT_EVENT_SYN      6

; canvas_event_poll
;   IN: rdi = conn, rsi = out_event* — OUT: rax = 1 event, 0 none
extern canvas_event_poll

; canvas_event_type
;   IN: rdi = event* — OUT: rax = type
extern canvas_event_type

; canvas_event_time
;   IN: rdi = event* — OUT: rax = timestamp
extern canvas_event_time

%endif ; __EVENTS_INC__