; ============================================================================
; sfnt.inc — TrueType font index (src/font/sfnt.asm) and font sets
; (src/font/fontset.asm)
; ============================================================================
%ifndef SFNT_INC
%define SFNT_INC

; SfntFont: a font's tables (pointers into the caller's data)
%define SF_DATA         0
%define SF_LEN          8
%define SF_GLYF         16
%define SF_GLYF_LEN     24
%define SF_LOCA         32
%define SF_LOCA_LEN     40
%define SF_HMTX         48
%define SF_HMTX_LEN     56
%define SF_CMAPT        64              ; the cmap table
%define SF_CMAPT_LEN    72
%define SF_CMAP         80              ; the subtable used
%define SF_CMAP_LEN     88
%define SF_CMAP_FMT     96              ; u32 4 or 12
%define SF_UPEM         100             ; u32 units per em
%define SF_NGLYPHS      104             ; u32
%define SF_LOCA_FMT     108             ; u32 0 short, 1 long
%define SF_NHM          112             ; u32 hmtx advances
%define SF_ASC          116             ; i32 ascender (font units, up)
%define SF_DESC         120             ; i32 descender (font units, down: positive)
%define SF_HAVE         124             ; u8 tables found (bits)
%define SF_SIZE         128

; FontSet: faces by family, weight and style
%define FONTSET_MAX     32
%define FC_NAME         0               ; family name (NUL-terminated)
%define FC_WEIGHT       8               ; u32 100 .. 900
%define FC_ITALIC       12              ; u32 1: italic
%define FC_FONT         16              ; SfntFont*
%define FC_SIZE         24
%define FS_ARENA        0
%define FS_COUNT        8               ; u32
%define FS_FACES        16              ; FC_SIZE x FONTSET_MAX
%define FS_SIZE         (FS_FACES + FONTSET_MAX * FC_SIZE)

; fontset_standard records: the fonts Canvas ships
%define FSTD_FILE       0               ; file name (NUL-terminated)
%define FSTD_FAMILY     8               ; family name
%define FSTD_WEIGHT     16              ; u32
%define FSTD_ITALIC     20              ; u32
%define FSTD_SIZE       24

%endif
