; ============================================================================
; log.inc — Log Categories (src/core/log.asm)
; ============================================================================
; Levels are LOG_ERROR to LOG_DEBUG in inc/ut.inc. log_error, log_warn,
; log_info, log_debug: edi = LOG_CAT_*, rsi = message, edx = its length.

%ifndef LOG_INC
%define LOG_INC

%define LOG_CAT_CORE        0
%define LOG_CAT_SERVER      1
%define LOG_CAT_CLIENT      2           ; connecting, leaving, refused
%define LOG_CAT_INPUT       3
%define LOG_CAT_OUTPUT      4           ; outputs added, removed, scaled
%define LOG_CAT_RENDER      5
%define LOG_CAT_SHELL       6
%define LOG_CAT_SESSION     7           ; locked, unlocked, the lid
%define LOG_CAT_SECURITY    8
%define LOG_CAT_DATA        9
%define LOG_CAT_ALL         -1          ; log_set_level: every category

%ifndef LOG_IMPL
extern log_init
extern log_set_level
extern log_set_sink
extern log_set_clock
extern log_write
extern log_error
extern log_warn
extern log_info
extern log_debug
%endif

%endif
