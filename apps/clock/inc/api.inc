%ifndef UCLOCK_API_INC
%define UCLOCK_API_INC
%include "apps/clock/inc/clock.inc"
; Native assembly calling convention: RDI,RSI,RDX,RCX,R8,R9 arguments; RAX result.
; Preserve RBX,RBP,R12..R15; RSP aligned to 16 bytes before CALL; DF clear.
extern uclock_read
extern uclock_stopwatch_init
extern uclock_stopwatch_start
extern uclock_stopwatch_pause
extern uclock_stopwatch_read
extern uclock_stopwatch_lap
extern uclock_countdown_init
extern uclock_countdown_start
extern uclock_countdown_poll
extern uclock_countdown_pause
extern uclock_countdown_resume
extern uclock_duration_parts
extern uclock_alarms_init
extern uclock_alarm_put
extern uclock_alarm_get
extern uclock_alarm_delete
extern uclock_alarm_poll
extern uclock_native_sources
extern uclock_read_native
extern uclock_local_now
%endif
