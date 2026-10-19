; ============================================================================
; GPU Acceleration — AMD GFX9 (RDNA/CDNA) Renderer
; ============================================================================

%ifndef __GPU_RENDER_INC__
%define __GPU_RENDER_INC__

%include "inc/fixed.inc"

; GPU command types
%define GPU_CMD_CLEAR       0
%define GPU_CMD_DRAW_RECT   1
%define GPU_CMD_DRAW_PATH   2
%define GPU_CMD_GRADIENT    3
%define GPU_CMD_IMAGE       4
%define GPU_CMD_COMPOSITE   5
%define GPU_CMD_BLIT        6

; GPU pipeline states
%define GPU_PIPE_GRAPHICS   0
%define GPU_PIPE_COMPUTE    1

; Shader stages
%define GPU_SHADER_VS       0
%define GPU_SHADER_PS       1
%define GPU_SHADER_CS       2

; Resource types
%define GPU_RES_BUFFER      0
%define GPU_RES_TEXTURE_2D  1
%define GPU_RES_SAMPLER     2
%define GPU_RES_CONSTANT    3

; Blend states
%define GPU_BLEND_ZERO      0
%define GPU_BLEND_ONE       1
%define GPU_BLEND_SRC_ALPHA 2
%define GPU_BLEND_DST_ALPHA 3
%define GPU_BLEND_INV_SRC_ALPHA 4
%define GPU_BLEND_INV_DST_ALPHA 5

; GPU renderer struct
%define GPU_DEV          0
%define GPU_CMD_RING     8
%define GPU_COMP_RING    16
%define GPU_SHADER_CACHE 24
%define GPU_PIPELINE_CACHE 32
%define GPU_DESC_HEAP    40
%define GPU_HEAP_PTR     48
%define GPU_HEAP_SIZE    56
%define GPU_FRAME_FENCE  64
%define GPU_STATS        72
%define GPU_RENDERER_SIZE 80

; GPU command buffer entry
%define GPU_CMD_TYPE     0
%define GPU_CMD_SIZE     4
%define GPU_CMD_DATA     8

%endif ; __GPU_RENDER_INC__