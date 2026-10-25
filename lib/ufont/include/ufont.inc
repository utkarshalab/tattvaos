; =============================================================================
; Utkarsha OS — lib/ufont/include/ufont.inc
; =============================================================================
; Layouts of the font library: a TrueType font's index (sfnt/sfnt.asm), font
; sets and their faces (match/fontset.asm), and the records of the shipped
; fonts (ufont_standard, fonts/).
; =============================================================================
%ifndef UFONT_INC
%define UFONT_INC

; UfontFont: a font's tables (pointers into the caller's bytes)
%define UfontFont_data          0
%define UfontFont_len           8
%define UfontFont_glyf          16
%define UfontFont_glyf_len      24
%define UfontFont_loca          32
%define UfontFont_loca_len      40
%define UfontFont_hmtx          48
%define UfontFont_hmtx_len      56
%define UfontFont_cmapt         64      ; the cmap table
%define UfontFont_cmapt_len     72
%define UfontFont_cmap          80      ; the subtable used
%define UfontFont_cmap_len      88
%define UfontFont_cmap_fmt      96      ; u32 4 or 12
%define UfontFont_upem          100     ; u32 units per em
%define UfontFont_nglyphs       104     ; u32
%define UfontFont_loca_fmt      108     ; u32 0 short, 1 long
%define UfontFont_nhm           112     ; u32 hmtx advances
%define UfontFont_ascent        116     ; i32 ascender (font units, up)
%define UfontFont_descent       120     ; i32 descender (font units, down: positive)
%define UfontFont_have          124     ; u8 tables found (bits)
%define UfontFont_SIZE          128

; UfontSet: faces by family, weight and style
%define UFONT_SET_MAX           32
%define UfontFace_family        0       ; family name (NUL-terminated, kept)
%define UfontFace_weight        8       ; u32 100 .. 900
%define UfontFace_italic        12      ; u32 1: italic
%define UfontFace_font          16      ; UfontFont*
%define UfontFace_SIZE          24
%define UfontSet_arena          0
%define UfontSet_count          8       ; u32
%define UfontSet_faces          16      ; UfontFace[UFONT_SET_MAX]
%define UfontSet_SIZE           (UfontSet_faces + UFONT_SET_MAX * UfontFace_SIZE)

; ufont_standard records: the fonts lib/ufont ships
%define UfontStd_file           0       ; file name (NUL-terminated)
%define UfontStd_family         8       ; family name
%define UfontStd_weight         16      ; u32
%define UfontStd_italic         20      ; u32
%define UfontStd_SIZE           24

%endif
