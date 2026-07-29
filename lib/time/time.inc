; =============================================================================
; Tattva OS — lib/time/time.inc
; =============================================================================
; Master Time Constants, Hardware Port Definitions & Data Schemas.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef TIME_INC
%define TIME_INC

; -----------------------------------------------------------------------------
; CMOS RTC Hardware I/O Ports
; -----------------------------------------------------------------------------
%define CMOS_ADDR_PORT      0x70
%define CMOS_DATA_PORT      0x71

%define RTC_SECONDS         0x00
%define RTC_MINUTES         0x02
%define RTC_HOURS           0x04
%define RTC_WEEKDAY         0x06
%define RTC_DAY             0x07
%define RTC_MONTH           0x08
%define RTC_YEAR            0x09
%define RTC_CENTURY         0x32
%define RTC_STATUS_A        0x0A
%define RTC_STATUS_B        0x0B

; -----------------------------------------------------------------------------
; Time Structures (64-bit aligned)
; -----------------------------------------------------------------------------
struc timespec_t
    .tv_sec:    resq 1      ; Seconds since UNIX Epoch
    .tv_nsec:   resq 1      ; Nanoseconds (0..999,999,999)
endstruc

struc tm_t
    .tm_sec:    resd 1      ; Seconds [0..60]
    .tm_min:    resd 1      ; Minutes [0..59]
    .tm_hour:   resd 1      ; Hour [0..23]
    .tm_mday:   resd 1      ; Day of month [1..31]
    .tm_mon:    resd 1      ; Month [0..11]
    .tm_year:   resd 1      ; Year since 1900
    .tm_wday:   resd 1      ; Day of week [0..6] (Sunday = 0)
    .tm_yday:   resd 1      ; Day of year [0..365]
    .tm_isdst:  resd 1      ; DST flag
endstruc

%endif ; TIME_INC
