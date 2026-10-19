; ============================================================================
; Canvas Error Codes — Negative values returned in rax
; Matches Tattva kernel errno values
; ============================================================================

%ifndef __ERRORS_INC__
%define __ERRORS_INC__

; Success
%define ESUCCESS        0

; Standard Errors (positive values, returned as negative in rax)
%define EPERM           1       ; Operation not permitted
%define ENOENT          2       ; No such file/directory/entry
%define ESRCH           3       ; No such process/task
%define EINTR           4       ; Interrupted system call
%define EIO             5       ; I/O error
%define ENXIO           6       ; No such device/address
%define E2BIG           7       ; Argument list too long
%define ENOEXEC         8       ; Exec format error
%define EBADF           9       ; Bad file descriptor
%define ECHILD          10      ; No child processes
%define EAGAIN          11      ; Try again / resource temporarily unavailable
%define ENOMEM          12      ; Out of memory
%define EACCES          13      ; Permission denied
%define EFAULT          14      ; Bad address
%define ENOTBLK         15      ; Block device required
%define EBUSY           16      ; Device or resource busy
%define EEXIST          17      ; File exists
%define EXDEV           18      ; Cross-device link
%define ENODEV          19      ; No such device
%define ENOTDIR         20      ; Not a directory
%define EISDIR          21      ; Is a directory
%define EINVAL          22      ; Invalid argument
%define ENFILE          23      ; File table overflow
%define EMFILE          24      ; Too many open files
%define ENOTTY          25      ; Not a typewriter
%define ETXTBSY         26      ; Text file busy
%define EFBIG           27      ; File too large
%define ENOSPC          28      ; No space left on device
%define ESPIPE          29      ; Illegal seek
%define EROFS           30      ; Read-only file system
%define EMLINK          31      ; Too many links
%define EPIPE           32      ; Broken pipe
%define EDOM            33      ; Math argument out of domain
%define ERANGE          34      ; Math result not representable

; Extended Errors
%define EDEADLK         35      ; Resource deadlock would occur
%define ENAMETOOLONG    36      ; File name too long
%define ENOLCK          37      ; No record locks available
%define ENOSYS          38      ; Function not implemented
%define ENOTEMPTY       39      ; Directory not empty
%define ELOOP           40      ; Too many symbolic links
%define EWOULDBLOCK     EAGAIN  ; Operation would block
%define ENOMSG          42      ; No message of desired type
%define EIDRM           43      ; Identifier removed
%define ECHRNG          44      ; Channel number out of range
%define EL2NSYNC        45      ; Level 2 not synchronized
%define EL3HLT          46      ; Level 3 halted
%define EL3RST          47      ; Level 3 reset
%define ELNRNG          48      ; Link number out of range
%define EUNATCH         49      ; Protocol driver not attached
%define ENOCSI          50      ; No CSI structure available
%define EL2HLT          51      ; Level 2 halted
%define EBADE           52      ; Invalid exchange
%define EBADR           53      ; Invalid request descriptor
%define EXFULL          54      ; Exchange full
%define ENOANO          55      ; No anode
%define EBADRQC         56      ; Invalid request code
%define EBADSLT         57      ; Invalid slot
%define EDEADLOCK       EDEADLK ; File locking deadlock
%define EBFONT          59      ; Bad font file format
%define ENOSTR          60      ; Not a stream device
%define ENODATA         61      ; No data available
%define ETIME           62      ; Timer expired
%define ENOSR           63      ; Out of streams resources
%define ENONET          64      ; Machine is not on the network
%define ENOPKG          65      ; Package not installed
%define EREMOTE         66      ; Object is remote
%define ENOLINK         67      ; Link has been severed
%define EADV            68      ; Advertise error
%define ESRMNT          69      ; Srmount error
%define ECOMM           70      ; Communication error on send
%define EPROTO          71      ; Protocol error
%define EMULTIHOP       72      ; Multihop attempted
%define EDOTDOT         73      ; RFS specific error
%define EBADMSG         74      ; Not a data message
%define EOVERFLOW       75      ; Value too large for data type
%define ENOTUNIQ        76      ; Name not unique on network
%define EBADFD          77      ; File descriptor in bad state
%define EREMCHG         78      ; Remote address changed
%define ELIBACC         79      ; Cannot access needed shared library
%define ELIBBAD         80      ; Accessing corrupted shared library
%define ELIBSCN         81      ; .lib section in a.out corrupted
%define ELIBMAX         82      ; Too many shared libraries
%define ELIBEXEC        83      ; Cannot exec shared library
%define EILSEQ          84      ; Illegal byte sequence
%define ERESTART        85      ; Interrupted system call should be restarted
%define ESTRPIPE        86      ; Streams pipe error
%define EUSERS          87      ; Too many users
%define ENOTSOCK        88      ; Socket operation on non-socket
%define EDESTADDRREQ    89      ; Destination address required
%define EMSGSIZE        90      ; Message too long
%define EPROTOTYPE      91      ; Protocol wrong type for socket
%define ENOPROTOOPT     92      ; Protocol not available
%define EPROTONOSUPPORT 93      ; Protocol not supported
%define ESOCKTNOSUPPORT 94      ; Socket type not supported
%define EOPNOTSUPP      95      ; Operation not supported on transport endpoint
%define EPFNOSUPPORT    96      ; Protocol family not supported
%define EAFNOSUPPORT    97      ; Address family not supported
%define EADDRINUSE      98      ; Address already in use
%define EADDRNOTAVAIL   99      ; Cannot assign requested address
%define ENETDOWN        100     ; Network is down
%define ENETUNREACH     101     ; Network is unreachable
%define ENETRESET       102     ; Network dropped connection
%define ECONNABORTED    103     ; Software caused connection abort
%define ECONNRESET      104     ; Connection reset by peer
%define ENOBUFS         105     ; No buffer space available
%define EISCONN         106     ; Transport endpoint already connected
%define ENOTCONN        107     ; Transport endpoint not connected
%define ESHUTDOWN       108     ; Cannot send after transport endpoint shutdown
%define ETOOMANYREFS    109     ; Too many references
%define ETIMEDOUT       110     ; Connection timed out
%define ECONNREFUSED    111     ; Connection refused
%define EHOSTDOWN       112     ; Host is down
%define EHOSTUNREACH    113     ; No route to host
%define EALREADY        114     ; Operation already in progress
%define EINPROGRESS     115     ; Operation now in progress
%define ESTALE          116     ; Stale file handle
%define EUCLEAN         117     ; Structure needs cleaning
%define ENOTNAM         118     ; Not a XENIX named type file
%define ENAVAIL         119     ; No XENIX semaphores available
%define EISNAM          120     ; Is a XENIX named type file
%define EREMOTEIO       121     ; Remote I/O error
%define EDQUOT          122     ; Quota exceeded
%define ENOMEDIUM       123     ; No medium found
%define EMEDIUMTYPE     124     ; Wrong medium type
%define ECANCELED       125     ; Operation canceled
%define ENOKEY          126     ; Required key not available
%define EKEYEXPIRED     127     ; Key has expired
%define EKEYREVOKED     128     ; Key has been revoked
%define EKEYREJECTED    129     ; Key was rejected by service
%define EOWNERDEAD      130     ; Owner died
%define ENOTRECOVERABLE 131     ; State not recoverable
%define ERFKILL         132     ; Operation not possible due to RF-kill
%define EHWPOISON       133     ; Memory page has hardware error
%define ENOTSUP 95      ; Operation not supported

; Data transfer limits
%define CLIPBOARD_MAX_SIZE     (1024 * 1024)  ; 1MB

; Input grab
%define GRAB_POINTER     1

; Canvas-Specific Errors (1000+ range)
%define ECWP_VERSION    1000    ; CWP version mismatch
%define ECWP_OPCODE     1001    ; Unknown opcode
%define ECWP_OBJECT     1002    ; Invalid object handle
%define ECWP_HANDLE     1003    ; Invalid handle in message
%define ECWP_PAYLOAD    1004    ; Payload size mismatch
%define ECWP_CAP        1005    ; Capability denied
%define ECWP_SEQ        1006    ; Sequence error
%define ECWP_FULL       1007    ; Channel full (flow control)
%define ECWP_PARSE      1008    ; Wire parse error

%define EBUF_FORMAT     1100    ; Unsupported pixel format
%define EBUF_SIZE       1101    ; Buffer size mismatch
%define EBUF_BUSY       1102    ; Buffer in use
%define EBUF_NODMA      1103    ; Buffer not DMA-able

%define EFENCE_WAIT     1200    ; Fence wait failed
%define EFENCE_SIGNAL   1201    ; Fence signal failed
%define EFENCE_TIMEOUT  1202    ; Fence wait timeout

%define ESURF_ROLE      1300    ; Surface role conflict
%define ESURF_COMMIT    1301    ; Commit failed
%define ESURF_DAMAGE    1302    ; Invalid damage region

%define EOUT_MODE       1400    ; Unsupported mode
%define EOUT_SCALE      1401    ; Unsupported scale factor

%define EINPUT_DEVICE   1500    ; Input device error
%define EINPUT_GRAB     1501    ; Device grab failed

%define ECLIP_BOARD     1600    ; Clipboard error
%define ECLIP_MIME      1601    ; MIME type not supported
%define ECLIP_SIZE      1602    ; Data too large

%define ESEC_PROFILE    1700    ; Invalid trust profile
%define ESEC_CAP        1701    ; Capability not granted
%define ESEC_TOKEN      1702    ; Invalid capability token
%define ESEC_AUDIT      1703    ; Audit log failed

%define EQUOTA_MEM      1800    ; Memory quota exceeded
%define EQUOTA_SURF     1801    ; Surface quota exceeded
%define EQUOTA_RATE     1802    ; Rate limit exceeded

%define EGPU_UNSUPPORTED 1900   ; GPU family not supported
%define EGPU_CMD        1901    ; GPU command error
%define EGPU_MEM        1902    ; GPU memory error

%define ECOLOR_ICC      2000    ; ICC profile error
%define ECOLOR_HDR      2001    ; HDR metadata error

%define EREMOTE_TLS     2100    ; TLS handshake failed
%define EREMOTE_CODEC   2101    ; Codec error

; Error Macros
%macro IS_ERROR 1
    ; %1 = register, sets flags: negative = error
    test %1, %1
    js %%is_error
    clc
    ret
%%is_error:
    stc
    ret
%endmacro

%macro RETURN_ERROR 1
    ; %1 = error code (positive), returns negative in rax
    mov rax, -(%1)
    ret
%endmacro

%macro CHECK_ERROR 1
    ; %1 = register with return value, jumps to error handler if negative
    test %1, %1
    js %%error
    ret
%%error:
%endmacro

%endif ; __ERRORS_INC__