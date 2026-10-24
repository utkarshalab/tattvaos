%ifndef UCAL_INC
%define UCAL_INC
%define UCAL_API_VERSION 1
%define UCAL_EVENT_ALL_DAY 1
%define UCAL_INVALID -1
%define UCAL_RANGE -2
%define UCAL_FULL -3
%define UCAL_NOT_FOUND -4
%define UCAL_UNAVAILABLE -5
%define UCAL_EVENTS 64
struc ucal_date
 .year: resq 1
 .month: resq 1
 .day: resq 1
 .hour: resq 1
 .minute: resq 1
 .second: resq 1
 .weekday: resq 1
 .yearday: resq 1
endstruc
struc ucal_month
 .year: resq 1
 .month: resq 1
 .week_start: resq 1
 .days: resq 1
 .first: resq 1
 .cells: resq 42
endstruc
struc ucal_event
 .id: resq 1
 .start: resq 1
 .end: resq 1
 .flags: resq 1
 .title: resb 128
endstruc
struc ucal_store
 .next_id: resq 1
 .events: resb UCAL_EVENTS*ucal_event_size
endstruc
%endif
