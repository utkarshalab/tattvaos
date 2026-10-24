%ifndef UCLOCK_INC
%define UCLOCK_INC
%define UCLOCK_API_VERSION 1
%define UCLOCK_IDLE 0
%define UCLOCK_RUNNING 1
%define UCLOCK_PAUSED 2
%define UCLOCK_EXPIRED 3
%define UCLOCK_INVALID -1
%define UCLOCK_RANGE -2
%define UCLOCK_STATE -3
%define UCLOCK_FULL -4
%define UCLOCK_NOT_FOUND -5
struc uclock_sources
 .monotonic: resq 1
 .realtime: resq 1
endstruc
struc uclock_sample
 .monotonic_ns: resq 1
 .utc_seconds: resq 1
 .nanoseconds: resq 1
endstruc
struc uclock_stopwatch
 .state: resq 1
 .elapsed: resq 1
 .anchor: resq 1
 .last: resq 1
 .lap_count: resq 1
 .laps: resq 32
endstruc
struc uclock_countdown
 .state: resq 1
 .remaining: resq 1
 .anchor: resq 1
 .last: resq 1
endstruc
struc uclock_alarm
 .id: resq 1
 .due: resq 1
 .period: resq 1
 .enabled: resq 1
endstruc
struc uclock_alarms
 .next_id: resq 1
 .records: resb 32*uclock_alarm_size
endstruc
struc uclock_notification
 .id: resq 1
 .scheduled: resq 1
 .observed: resq 1
 .missed: resq 1
endstruc
%endif
