; ============================================================================
; Font Definitions — TrueType Font Rendering
; ============================================================================

%ifndef __FONT_INC__
%define __FONT_INC__

%include "inc/fixed.inc"

; Font struct
%define Font_TTF_DATA       0       ; pointer to TTF data
%define Font_TTF_SIZE       8       ; size of TTF data
%define Font_CMAP           16      ; cmap table offset
%define Font_GLYF           24      ; glyf table offset
%define Font_HEAD           32      ; head table offset
%define Font_HHEA           40      ; hhea table offset
%define Font_HMTX           48      ; hmtx table offset
%define Font_LOCA           56      ; loca table offset
%define Font_KERN           64      ; kern table offset
%define Font_UNITS_PER_EM   72      ; units per em
%define Font_ASCENT         76      ; ascent
%define Font_DESCENT        80      ; descent
%define Font_LINE_GAP       84      ; line gap
%define Font_SIZE           88

; Glyph metrics
%define GlyphMetrics_XMIN   0
%define GlyphMetrics_YMIN   4
%define GlyphMetrics_XMAX   8
%define GlyphMetrics_YMAX   12
%define GlyphMetrics_ADVANCE 16     ; advance width (fixed)
%define GlyphMetrics_LSB    20      ; left side bearing
%define GlyphMetrics_SIZE   24

; Font face (scaled font)
%define FontFace_FONT       0       ; base font
%define FontFace_SIZE       8       ; point size (fixed 16.16)
%define FontFace_SCALE_X    16      ; x scale
%define FontFace_SCALE_Y    24      ; y scale
%define FontFace_DPI        32      ; DPI
%define FontFace_HINTING    36      ; hinting mode
%define FontFace_SIZEOF     40

; Hinting modes
%define HINTING_NONE        0
%define HINTING_LIGHT       1
%define HINTING_NORMAL      2
%define HINTING_FULL        3

; Glyph cache entry
%define GlyphCache_CODEPOINT 0
%define GlyphCache_FACE      8
%define GlyphCache_METRICS   16
%define GlyphCache_BITMAP    24     ; rendered bitmap
%define GlyphCache_NEXT      32
%define GlyphCache_SIZE      40

; Text layout struct
%define TextLayout_FACE        0
%define TextLayout_MAX_WIDTH   8
%define TextLayout_FLAGS       12
%define TextLayout_RUNS        16
%define TextLayout_RUN_COUNT   24
%define TextLayout_RUN_CAP     28
%define TextLayout_SIZE        32

%define TEXT_FLAG_RTL          (1 << 0)
%define TEXT_FLAG_WRAP         (1 << 1)
%define TEXT_FLAG_ALIGN_LEFT   0
%define TEXT_FLAG_ALIGN_CENTER (1 << 2)
%define TEXT_FLAG_ALIGN_RIGHT  (1 << 3)
%define TEXT_FLAG_ALIGN_JUSTIFY (1 << 4)

; Run struct
%define Run_START       0
%define Run_LENGTH      4
%define Run_X           8
%define Run_Y           12
%define Run_ADVANCE     16
%define Run_ASCENT      20
%define Run_DESCENT     24
%define Run_SIZE        28

; Path verbs (for font outline)
%define VERB_MOVE       0
%define VERB_LINE       1
%define VERB_QUAD       2
%define VERB_CUBIC      3
%define VERB_CLOSE      4
%define VERB_QEND       5   ; end of quadratic segment

; Glyph flags (for glyf table)
%define GLYPH_ON_CURVE      (1 << 0)
%define GLYPH_X_SHORT       (1 << 1)
%define GLYPH_Y_SHORT       (1 << 2)
%define GLYPH_REPEAT        (1 << 3)
%define GLYPH_X_SAME        (1 << 4)
%define GLYPH_Y_SAME        (1 << 5)

; TTF table tags
%define TTAG_head       0x68656164
%define TTAG_hhea       0x68686561
%define TTAG_maxp       0x6D617870
%define TTAG_hmtx       0x686D7478
%define TTAG_loca       0x6C6F6361
%define TTAG_glyf       0x676C7966
%define TTAG_cmap       0x636D6170
%define TTAG_kern       0x6B65726E
%define TTAG_name       0x6E616D65
%define TTAG_post       0x706F7374
%define TTAG_OS_2       0x4F532F32
%define TTAG_GDEF       0x47444546
%define TTAG_GPOS       0x47504F53
%define TTAG_GSUB       0x47535542
%define TTAG_gasp       0x67617370
%define TTAG_PCLT       0x50434C54
%define TTAG_DSIG       0x44534947

; Glyph outline struct
%define GlyphOut_VERBS       0
%define GlyphOut_COORDS      8
%define GlyphOut_COUNT       16
%define GlyphOut_CAP         20
%define GlyphOut_XMIN        24
%define GlyphOut_YMIN        28
%define GlyphOut_XMAX        32
%define GlyphOut_YMAX        36
%define GlyphOut_SIZE        40

; Glyph edge struct
%define GLYPH_EDGE_X         0
%define GLYPH_EDGE_DX_DY     4
%define GLYPH_EDGE_Y_MAX     8
%define GLYPH_EDGE_NEXT      12
%define GLYPH_EDGE_SIZE      16

%endif ; __FONT_INC__