%ifndef TIME_NATIVE_INC
%define TIME_NATIVE_INC
%include "lib/time/time.inc"
%define TIME_NATIVE_INVALID -1
%define TIME_NATIVE_UNAVAILABLE -3
; time_init owns initialization after successful TSC calibration.
; time_read_monotonic(rdi=out u64 ns) -> 0 or negative status.
; time_read_realtime(rdi=out timespec_t) -> 0 or negative status.
extern time_read_monotonic,time_read_realtime
%endif
