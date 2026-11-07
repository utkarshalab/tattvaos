; =============================================================================
; Utkarsha OS — lib/io/i2c/i2c.inc
; =============================================================================
; Messages, limits and errors for I2C host controllers. Plan:
; lib/io/i2c/ROADMAP.md.
; =============================================================================

%ifndef LIB_IO_I2C_I2C_INC
%define LIB_IO_I2C_I2C_INC

%define I2C_MAX_CTRL        4       ; AMD laptops have up to four

; One message of a transfer. Messages of one transfer go to one target
; and are joined by repeated starts; the last ends with a stop.
struc i2c_msg
    .addr:      resw 1          ; 7-bit address, or 10-bit with I2C_M_TEN
    .flags:     resw 1          ; I2C_M_*
    .len:       resd 1          ; bytes (1 or more)
    .buf:       resq 1
endstruc                        ; 16 bytes

%define I2C_M_READ          (1 << 0)
%define I2C_M_TEN           (1 << 1)    ; 10-bit address

; errors (negative in EAX)
%define I2C_EIO             5       ; the transfer was aborted (data not
                                    ; acknowledged, arbitration lost...)
%define I2C_ENXIO           6       ; nobody answered at that address
%define I2C_EBUSY           16
%define I2C_ENODEV          19      ; not a controller this driver knows
%define I2C_EINVAL          22
%define I2C_ENOSPC          28
%define I2C_ETIMEDOUT       110

%endif ; LIB_IO_I2C_I2C_INC
