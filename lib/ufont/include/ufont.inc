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
%define UfontFont_arena         128     ; the arena it was opened with (its cache lives there)
%define UfontFont_cache         136     ; outline records by glyph (0: none decoded yet)
%define UfontFont_gdef          144     ; OpenType layout tables (0: absent)
%define UfontFont_gdef_len      152
%define UfontFont_gsub          160
%define UfontFont_gsub_len      168
%define UfontFont_gpos          176
%define UfontFont_gpos_len      184
%define UfontFont_kern          192     ; the legacy kern table
%define UfontFont_kern_len      200
%define UfontFont_cmap14        208     ; cmap format 14 (variation sequences; 0: none)
%define UfontFont_cmap14_len    216
%define UfontFont_SIZE          224

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

; ---------------------------------------------------------------- shaping (layout/)
; UfontGlyph: one glyph of a shaped run (ufont_shape's output), font units,
; y up as OpenType has it
%define UfontGlyph_glyph        0       ; u32 glyph id
%define UfontGlyph_cluster      4       ; u32 index of the first character it stands for
%define UfontGlyph_xa           8       ; i32 x advance
%define UfontGlyph_ya           12      ; i32 y advance
%define UfontGlyph_xo           16      ; i32 x offset
%define UfontGlyph_yo           20      ; i32 y offset
%define UfontGlyph_SIZE         24

; the shaping buffer's glyph records (layout code only)
%define GI_CP           0       ; u32 the character
%define GI_GLYPH        4       ; u32
%define GI_CLUSTER      8       ; u32
%define GI_MASK         12      ; u32 features that apply to it
%define GI_PROPS        16      ; u16 glyph props: class bits, high byte mark attachment class
%define GI_LIG          18      ; u8 ligature id (3 bits) | is-base (0x10) | component (4 bits)
%define GI_SYL          19      ; u8 syllable (Indic: serial << 4 | type)
%define GI_GC           20      ; u8 general category
%define GI_MCC          21      ; u8 modified combining class (marks)
%define GI_UF           22      ; u8 UF_* below
%define GI_CAT          23      ; u8 Indic category
%define GI_POS          24      ; u8 Indic position
%define GI_SPACE        25      ; u8 space fallback type
%define GI_SIZE         32

%define UF_IGN          0x01    ; default ignorable
%define UF_ZWNJ         0x02
%define UF_ZWJ          0x04
%define UF_HIDDEN       0x08    ; ignorable that GSUB does not skip
%define UF_CONT         0x10    ; continues the grapheme

; glyph props
%define GP_BASE         0x02
%define GP_LIGATURE     0x04
%define GP_MARK         0x08
%define GP_SUBSTITUTED  0x10
%define GP_LIGATED      0x20
%define GP_MULTIPLIED   0x40
%define GP_PRESERVE     0x70

; positions
%define GPOS_XA         0       ; i32
%define GPOS_YA         4
%define GPOS_XO         8
%define GPOS_YO         12
%define GPOS_CHAIN      16      ; i32 offset to the glyph it is attached to
%define GPOS_TYPE       20      ; u32 1 mark, 2 cursive
%define GPOS_SIZE       24

; general categories (HarfBuzz's order)
%define GC_CC 0
%define GC_CF 1
%define GC_CN 2
%define GC_LO 7
%define GC_MC 10
%define GC_ME 11
%define GC_MN 12
%define GC_ZS 29

%endif
