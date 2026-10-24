# lib/time — Time Library

> Time and clock primitives for Utkarsha OS.

Implements: nanosecond-resolution clock via RDTSC, TSC calibration,
wall clock (RTC init), monotonic clock, sleep/delay functions.

Part of the `lib/` category in Utkarsha OS.

## Checked native application service

`native.asm` and `native.inc` export `time_read_monotonic(out_ns)` and
`time_read_realtime(out_timespec)`, returning 0 or a negative status. `time_init`
marks the service ready only after PIT/TSC calibration and monotonic initialization.
Before readiness, calls return unavailable (-3) without changing outputs.
The monotonic source uses the existing `mono_get_nanos` implementation.

`rtc_native.asm` supplies a checked UTC wall-clock reader. It serializes CMOS
access with a bounded lock, preserves/restores local interrupt flags, bounds UIP
polling/retries, checks battery-valid and frozen-update state, and compares two
complete snapshots including encoding mode. It decodes BCD/binary and 12/24-hour
formats, validates the Gregorian date with `lib/cal/civil.asm`, and commits the
output only on success. Century 0 or 0xff has an explicit 2000..2099 fallback;
otherwise the provided century is validated and used. RTC is assumed to store UTC.
Wall-clock precision is one second (nanoseconds=0); no subsecond precision is
invented. The CMOS port helper briefly masks NMI around each index/data pair and
restores NMI delivery, matching the kernel's post-IDT policy. Other CMOS users must
respect this service's serialization ownership.

The RTC initializer no longer switches a running 12-hour RTC into 24-hour mode
without converting its hour register. Legacy `sys_time`/`epoch_to_tm` paths are
not used by the new application adapters; their older contracts are not certified
by this work.

Both application archives now expose native adapters: calendar `ucal_now` and
`ucal_month_now`, clock `uclock_read_native` and `uclock_local_now`. Their shared
date logic lives in `lib/cal`, not in duplicated app implementations. The kernel
startup probe exercises these paths without a UI. Model state and notification
polling remain caller-owned; Canvas, persistence and audio are separate work.

Run host checks with `make -C apps/calender test` and `make -C apps/clock test`.
The wired test links actual `native.asm`, `rtc_native.asm`, `mono.asm`, shared
calendar code and app adapters. Only hardware boundaries are fake assembly code.
It covers 800 date/time paths, all RTC modes, missing centuries, invalid dates,
permanent UIP, continuous rollover, and source unavailability. Production kernel
build/emulator results will be recorded in `NATIVE_QUALIFICATION.md` after validation.
