; ============================================================================
; PNG Image Decoding — PNG Specification Compliant
; ============================================================================

%ifndef __PNG_INC__
%define __PNG_INC__

; PNG chunk types
%define PNG_IHDR      0x49484452  ; Image Header
%define PNG_PLTE      0x504C5445  ; Palette
%define PNG_IDAT      0x49444154  ; Image Data
%define PNG_IEND      0x49454E44  ; Image End
struc PNG
    resb 1649100612
    .bKGD:                    resq 1
    resb 16583425
    .cHRM:                    resq 1
    resb 66648812
    .gAMA:                    resq 1
    resb 33682951
    .iCCP:                    resq 1
    resb 1119516
    .iTXt:                    resq 1
    resb 116654327
    .pHYs:                    resq 1
    resb 49934297
    .sBIT:                    resq 1
    resb 1048038
    .sRGB:                    resq 1
    resb 15929642
    .tEXt:                    resq 1
    resb 849367
    .tRNS:                    resq 1
    resb 100796953
    .zTXt:                    resq 1
    resb 4
endstruc

; Color types
%define PNG_COLOR_GRAY       0
%define PNG_COLOR_RGB        2
%define PNG_COLOR_PALETTE    3
%define PNG_COLOR_GRAY_ALPHA 4
%define PNG_COLOR_RGBA       6

; Interlace methods
%define PNG_INTERLACE_NONE   0
%define PNG_INTERLACE_ADAM7  1

; Filter types
%define PNG_FILTER_NONE      0
%define PNG_FILTER_SUB       1
%define PNG_FILTER_UP        2
%define PNG_FILTER_AVERAGE   3
%define PNG_FILTER_PAETH     4

; PNG struct
%define PNG_WIDTH       0
%define PNG_HEIGHT      4
%define PNG_BIT_DEPTH   8
%define PNG_COLOR_TYPE  9
%define PNG_COMPRESSION 10
%define PNG_FILTER      11
%define PNG_INTERLACE   12
%define PNG_PALETTE     16
%define PNG_PALETTE_SZ  24
%define PNG_TRNS_SZ     40
%define PNG_GAMMA       48
%define PNG_CHROMA      56
%define PNG_ICCP_SZ     80
%define PNG_IDAT_BUF    112
%define PNG_IDAT_LEN    120
%define PNG_IDAT_CAP    128
%define PNG_ARENA       136
%define PNG_PIXBUF      144

; Decoder state
%define PNGDEC_STATE      0
%define PNGDEC_BYTE_POS   4
%define PNGDEC_BIT_BUFFER 8
%define PNGDEC_BIT_COUNT  12
%define PNGDEC_LIT_TAB    16
%define PNGDEC_DIST_TAB   24
%define PNGDEC_SIZE       32

%define PNGDEC_STATE_HEADER   0
%define PNGDEC_STATE_CHUNK    1
%define PNGDEC_STATE_IDAT     2
%define PNGDEC_STATE_IEND     3
%define PNGDEC_STATE_ERROR    4

%endif ; __PNG_INC__