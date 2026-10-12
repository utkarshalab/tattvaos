; ============================================================================
; Font Shared Definitions
; ============================================================================

%ifndef __FONT_INC__
%define __FONT_INC__

; Table tags (BE)
%define TTAG_cmap  0x70616D63
%define TTAG_glyf  0x66796C67
%define TTAG_head  0x64616568
%define TTAG_hhea  0x61656868
%define TTAG_hmtx  0x78746D68
%define TTAG_kern  0x6E72656B
%define TTAG_loca  0x61636F6C
%define TTAG_maxp  0x7078616D
%define TTAG_name  0x656D616E

; Glyph flags
%define GLYPH_ON_CURVE     0x01
%define GLYPH_X_SHORT      0x02
%define GLYPH_Y_SHORT      0x04
%define GLYPH_REPEAT       0x08
%define GLYPH_X_SAME       0x10
%define GLYPH_Y_SAME       0x20

; Outline verbs (verb records: verb u8, x i32, y i32)
%define VERB_MOVE   0
%define VERB_LINE   1
%define VERB_QUAD   2
%define VERB_QEND   3
%define VERB_CLOSE  4

; Outline verbs
%define VERB_MOVE   0
%define VERB_LINE   1
%define VERB_QUAD   2
%define VERB_CUBIC  3
%define VERB_CLOSE  4

%endif ; __FONT_INC__
