; =============================================================================
; Utkarsha OS — lib/ufont/layout/shape.inc
; =============================================================================
; The state of one ufont_shape call, shared by the layout/ sources: every
; internal routine takes it in r15. It lives in the caller's arena.
; =============================================================================
%ifndef UFONT_SHAPE_INC
%define UFONT_SHAPE_INC

%define MAX_NESTING     64
%define MAX_CONTEXT     64
%define MAX_FEATURES    96              ; features the plan can hold
%define MAX_PAUSES      32              ; pauses per table
%define MAX_LOOKUPS     2048            ; lookup entries per table in the plan

; the buffer
%define S_FONT          0               ; UfontFont*
%define S_ARENA         8
%define S_INFO          16              ; GI records
%define S_OUT           24              ; GI records (the output side)
%define S_LEN           32              ; u32
%define S_OUTLEN        36              ; u32
%define S_IDX           40              ; u32
%define S_CAP           44              ; u32 records both arrays hold
%define S_HAVEOUT       48              ; u8
%define S_SERIAL        49              ; u8 ligature serial
%define S_ERR           50              ; u8 out of memory
%define S_SHAPER        51              ; u8 0 default, 1 Indic
%define S_POS           56              ; GPOS_* records
; the plan
%define S_GMASK         64              ; u32 global mask
%define S_NFEATS        68              ; u32
%define S_FEATS         72              ; FM_* records
%define S_LK            80              ; [2] LK_* arrays (GSUB, GPOS)
%define S_NLK           96              ; [2] u32
%define S_ST            104             ; [2] ST_* arrays
%define S_NST           120             ; [2] u32
%define S_CHOSEN        128             ; [2] u32 the script tag found (0xFFFF none)
%define S_LS            136             ; [2] langsys (0: none)
%define S_FI            152             ; the builder's FI_* records
%define S_NFI           160             ; u32
%define S_CUR           164             ; [2] u32 current stage
%define S_PA            176             ; [2] PA_* arrays
%define S_NPA           192             ; [2] u32
; applying lookups
%define S_TABLE         200             ; GSUB / GPOS
%define S_TEND          208             ; its end
%define S_GPOS          216             ; u8 1 in GPOS
%define S_AZWNJ         217             ; u8
%define S_AZWJ          218             ; u8
%define S_PERSYL        219             ; u8
%define S_LPROPS        220             ; u32 lookup props
%define S_LMASK         224             ; u32
%define S_NEST          228             ; u32 nesting left
%define S_LASTBASE      232             ; i32
%define S_LASTBASEUNTIL 236             ; u32
%define S_HASATTACH     240             ; u8
; GDEF
%define S_CLASSDEF      248             ; glyph class definition (0: none)
%define S_MARKATTACH    256             ; mark attachment classes (0: none)
%define S_MARKSETS      264             ; mark glyph sets (0: none)
%define S_NMARKSETS     272             ; u32
%define S_GDEFEND       280
; the run
%define S_SCRIPT        288             ; u32 script index (ucd_scripts)
%define S_LANG          292             ; u32 language system tag (0: default)
%define S_KERNMASK      296             ; u32
%define S_SR            304             ; [2] script record found (0: none)
; the Indic shaper
%define S_IOLD          320             ; u8 old spec
%define S_IZERO         321             ; u8 zero-context would-substitute
%define S_IBROKEN       322             ; u8 a broken cluster seen
%define S_IVIRAMA       324             ; u32 virama glyph (0: none, -1 not loaded)
%define S_IMASK         328             ; [17] u32 feature masks (indic_features order)
%define S_OPS           400             ; i32 lookup recursions left (a runaway font's limit)
%define S_MAXLEN        404             ; u32 records the buffer may grow to
%define S_DUMMY         448             ; a record written when memory runs out
%define S_SIZE          480

; plan records
%define FI_TAG          0               ; builder features
%define FI_SEQ          4
%define FI_MAX          8
%define FI_FLAGS        12
%define FI_DEFAULT      16
%define FI_STAGE        20              ; [2]
%define FI_SIZE         28

%define FM_TAG          0               ; compiled features
%define FM_MASK         4
%define FM_MASK1        8
%define FM_STAGE        12              ; [2]
%define FM_INDEX        20              ; [2] feature index (-1: not in the table)
%define FM_FLAGS        28
%define FM_SIZE         32

%define LK_INDEX        0               ; lookups
%define LK_MASK         4
%define LK_AZWNJ        8               ; u8
%define LK_AZWJ         9               ; u8
%define LK_PERSYL       10              ; u8
%define LK_SIZE         12

%define ST_LAST         0               ; stages: lookups end, pause
%define ST_PAUSE        8
%define ST_SIZE         16

%define PA_STAGE        0               ; builder pauses
%define PA_FUNC         8
%define PA_SIZE         16

; the skipping iterator (on the stack of whoever matches)
%define SK_IDX          0               ; i32 position
%define SK_NUM          4               ; items still to match
%define SK_END          8
%define SK_MASK         12
%define SK_PROPS        16              ; lookup props it matches with
%define SK_FLAGS        20              ; SKF_*
%define SK_SYL          24              ; syllable it stays in (0: any)
%define SK_MTYPE        28              ; MT_*
%define SK_MDATA        32              ; the values (big-endian u16), one per item
%define SK_MBASE        40              ; class definition / base of coverage offsets
%define SK_ARR          48              ; the records prev() walks
%define SK_SIZE         56
%define SKF_ZWNJ        1               ; ZWNJ may be skipped
%define SKF_ZWJ         2
%define SKF_HIDDEN      4
%define SKF_PERSYL      8

%define MT_NONE         0
%define MT_GLYPH        1               ; the glyph is the value
%define MT_CLASS        2               ; its class (MB_BASE's class definition) is
%define MT_COVERAGE     3               ; it is in the coverage at MB_BASE + value

; a matcher: what a sequence of items must be
%define MB_TYPE         0
%define MB_COUNT        4
%define MB_DATA         8
%define MB_BASE         16
%define MB_SIZE         24

; feature flags
%define F_GLOBAL        0x01
%define F_HAS_FALLBACK  0x02
%define F_MANUAL_ZWNJ   0x04
%define F_MANUAL_ZWJ    0x08
%define F_MANUAL_JOINERS 0x0C
%define F_RANDOM        0x20
%define F_PER_SYLLABLE  0x40
%define GLOBAL_MASK     0x80000000

; lookup flags
%define LF_IGNORE_FLAGS 0x0E
%define LF_FILTER_SET   0x10
%define LF_ATTACH_TYPE  0xFF00

; a big-endian u16 / u32, zero-extended
%macro BE16 2
    movzx %1, word %2
    bswap %1
    shr %1, 16
%endmacro
%macro BE32 2
    mov %1, %2
    bswap %1
%endmacro

%endif
