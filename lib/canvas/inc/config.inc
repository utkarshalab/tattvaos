; ============================================================================
; Config — settings files read against a schema (core/config, DEV-12)
; ============================================================================
; A schema is a ConfigSchema: its key count, then a ConfigKey each, made by
; CONFIG_KEY. config_parse reads text of [section] headers and key = value
; lines into a settings structure, each value checked against its key.

%ifndef __CONFIG_INC__
%define __CONFIG_INC__

; value types
%define CONFIG_INT      1               ; decimal, within [a, b]
%define CONFIG_BOOL     2               ; true yes on 1 / false no off 0
%define CONFIG_ENUM     3               ; one of a's names: its index
%define CONFIG_STRING   4               ; bare or "quoted", at most a - 1 bytes

; why a line was not taken (ConfigResult.reason)
%define CONFIG_E_SYNTAX     1           ; not a header, key = value, comment or blank
%define CONFIG_E_SECTION    2           ; no such section (its keys passed over)
%define CONFIG_E_KEY        3           ; no such key in its section
%define CONFIG_E_VALUE      4           ; not of the key's type
%define CONFIG_E_RANGE      5           ; a number outside the key's range
%define CONFIG_E_LONG       6           ; a string longer than the key holds
%define CONFIG_E_TWICE      7           ; a key given again

%define CONFIG_MAX_KEYS     64          ; in a schema
%define CONFIG_MAX_STRING   256         ; a string key's capacity at most
%define CONFIG_SECTION_LEN  16          ; names with their NUL
%define CONFIG_KEY_LEN      24

struc ConfigKey
    .section:   resb CONFIG_SECTION_LEN ; "" before any header
    .key:       resb CONFIG_KEY_LEN
    .type:      resd 1
    .offset:    resd 1                  ; of its value in the settings
    .a:         resq 1                  ; INT the least; ENUM its names (each
                                        ; NUL-terminated, "" after the last);
                                        ; STRING its capacity, NUL included
    .b:         resq 1                  ; INT the most
    .default:   resq 1                  ; INT, BOOL, ENUM the value; STRING a
                                        ; NUL-terminated string
endstruc

struc ConfigSchema
    .count:     resq 1
    .keys:                              ; ConfigKey[count]
endstruc

struc ConfigResult
    .errors:    resd 1                  ; lines not taken
    .line:      resd 1                  ; the first of them, from 1
    .reason:    resd 1                  ; and why: CONFIG_E_*
    .pad:       resd 1
endstruc

; CONFIG_KEY "section", "key", type, offset, a, b, default
%macro CONFIG_KEY 7
%if %strlen(%1) >= CONFIG_SECTION_LEN || %strlen(%2) >= CONFIG_KEY_LEN
    %error "config: a section or key name too long"
%endif
    db %1
    times CONFIG_SECTION_LEN - %strlen(%1) db 0
    db %2
    times CONFIG_KEY_LEN - %strlen(%2) db 0
    dd %3, %4
    dq %5, %6, %7
%endmacro

%endif
