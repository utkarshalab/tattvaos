; UTM Task Manager - Constants & Limits
; Pure Assembly Implementation - Enterprise/Datacenter Grade

%ifndef _UTM_CONSTANTS_INC_
%define _UTM_CONSTANTS_INC_

; Maximum Limits
MAX_PROCESSES       equ 65536
MAX_THREADS         equ 262144
MAX_CPUS            equ 4096
MAX_NUMA_NODES      equ 256
MAX_DISKS           equ 1024
MAX_NET_IFACES      equ 256
MAX_THERMAL_ZONES   equ 128
MAX_FLIGHT_RECORDS  equ 360000
MAX_CONTAINERS      equ 65536
MAX_CGROUPS         equ 131072
MAX_GPUS            equ 64
MAX_ALERT_RULES     equ 4096
MAX_ALERT_EVENTS    equ 100000
MAX_AUDIT_ENTRIES   equ 1000000
MAX_CMDLINE_LEN     equ 8192
MAX_EXE_PATH_LEN    equ 4096
MAX_PROC_NAME_LEN   equ 512
MAX_USERS           equ 1024
MAX_ROLES           equ 64
MAX_API_ENDPOINTS   equ 256

; Sampling Rates
SAMPLE_RATE_HZ      equ 60
SAMPLE_NS           equ 16666667
AGG_1S_SAMPLES      equ 60
AGG_5S_SAMPLES      equ 300
AGG_60S_SAMPLES     equ 3600

; Process States
PROC_STATE_RUNNING  equ 0
PROC_STATE_SLEEPING equ 1
PROC_STATE_ZOMBIE   equ 2
PROC_STATE_STOPPED  equ 3
PROC_STATE_IDLE     equ 4
PROC_STATE_DEAD     equ 255

; Thermal Pressure Levels
THERMAL_NOMINAL     equ 0
THERMAL_FAIR        equ 1
THERMAL_SERIOUS     equ 2
THERMAL_CRITICAL    equ 3
THERMAL_EMERGENCY   equ 4

; Alert Severity Levels
ALERT_SEV_INFO      equ 0
ALERT_SEV_WARNING   equ 1
ALERT_SEV_CRITICAL  equ 2
ALERT_SEV_EMERGENCY equ 3

; RBAC Roles
ROLE_READONLY       equ 0
ROLE_OPERATOR       equ 1
ROLE_ADMIN          equ 2
ROLE_SUPERUSER      equ 3

; Flight Recorder Flags
FLIGHT_FLAG_ACTIVE  equ (1 << 0)
FLIGHT_FLAG_WRAPPED equ (1 << 1)
FLIGHT_FLAG_OVERFLOW equ (1 << 2)
FLIGHT_FLAG_TRIGGERED equ (1 << 3)

; Syscall Base
SYSCALL_UTM_BASE     equ 0x100

; Ring Buffer Magic Values
RING_MAGIC          equ 0x55544D524E47
FLIGHT_MAGIC        equ 0x55544D464C54
AUDIT_MAGIC         equ 0x55544D415544

; Scaling Factors
PERCENT_SCALE       equ 10000
MICRO_SCALE         equ 1000000
NANO_SCALE          equ 1000000000

; Page Size
PAGE_SIZE           equ 4096
PAGE_SHIFT          equ 12

; Tick Constants
TICK_NS_PER_TICK    equ 1000000

; Invalid Values
INVALID_PID         equ 0xFFFFFFFFFFFFFFFF
INVALID_TIMESTAMP   equ 0xFFFFFFFFFFFFFFFF
INVALID_PTR         equ 0

; Error Codes (negative)
UTM_ERR_INVAL       equ -1
UTM_ERR_NOMEM       equ -2
UTM_ERR_NOPROC      equ -3
UTM_ERR_PERM        equ -4
UTM_ERR_BUSY        equ -5
UTM_ERR_NOTSUPP     equ -6
UTM_ERR_OVERFLOW    equ -7
UTM_ERR_NOTFOUND    equ -8
UTM_ERR_EXIST       equ -9
UTM_ERR_IO          equ -10
UTM_ERR_TIMEOUT     equ -11
UTM_ERR_CONN        equ -12
UTM_ERR_AUTH        equ -13
UTM_ERR_CORRUPT     equ -14

%endif