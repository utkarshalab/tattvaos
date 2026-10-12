; ============================================================================
; AMD DCN (Display Core Next) Register Definitions
; Covers DCN 1.0 through 3.5 (Raven Ridge to Phoenix)
; ============================================================================

%ifndef __DCN_REGS_INC__
%define __DCN_REGS_INC__

; ============================================================================
; Register Base Offsets (per IP instance)
; ============================================================================

; DCE (Display Controller Engine) - legacy
%define DCE_BASE                    0x00000000

; DCN (Display Core Next) - per pipe/plane
%define DCN_BASE                    0x00000000

; ============================================================================
; CRTC Registers (per CRTC instance, stride 0x100)
; ============================================================================
%define CRTC_BASE                   0x00000000
%define CRTC_STRIDE                 0x100

%define CRTC_CONTROL                (CRTC_BASE + 0x0000)
%define CRTC_STATUS                 (CRTC_BASE + 0x0010)
%define CRTC_HTOTAL                 (CRTC_BASE + 0x0020)
%define CRTC_H_TOTAL                (CRTC_BASE + 0x0020)
%define CRTC_H_START                (CRTC_BASE + 0x0030)
%define CRTC_H_SYNC_A_START         (CRTC_BASE + 0x0030)
%define CRTC_H_END                  (CRTC_BASE + 0x0040)
%define CRTC_H_SYNC_A_END           (CRTC_BASE + 0x0040)
%define CRTC_VTOTAL                 (CRTC_BASE + 0x0050)
%define CRTC_V_TOTAL                (CRTC_BASE + 0x0050)
%define CRTC_V_START                (CRTC_BASE + 0x0060)
%define CRTC_V_SYNC_A_START         (CRTC_BASE + 0x0060)
%define CRTC_V_END                  (CRTC_BASE + 0x0070)
%define CRTC_V_SYNC_A_END           (CRTC_BASE + 0x0070)
%define CRTC_H_SYNC_POLARITY        (CRTC_BASE + 0x0080)
%define CRTC_V_SYNC_POLARITY        (CRTC_BASE + 0x0090)
%define CRTC_PIXEL_CLOCK            (CRTC_BASE + 0x00A0)
%define CRTC_DOUBLE_BUFFER_CONTROL  (CRTC_BASE + 0x00B0)
%define CRTC_UPDATE_LOCK            (CRTC_BASE + 0x00C0)
%define CRTC_V_SYNC_NOM             (CRTC_BASE + 0x00D0)
%define CRTC_V_SYNC_NOM_MAX         (CRTC_BASE + 0x00E0)
%define CRTC_V_SYNC_NOM_MIN         (CRTC_BASE + 0x00F0)

%define CRTC_INTERLACE_CONTROL      (CRTC_BASE + 0x0100)
%define CRTC_BLANK_CONTROL          (CRTC_BASE + 0x0110)
%define CRTC_BLANK_DATA_COLOR       (CRTC_BASE + 0x0120)
%define CRTC_OVERSCAN_LEFT_RIGHT    (CRTC_BASE + 0x0130)
%define CRTC_OVERSCAN_TOP_BOTTOM    (CRTC_BASE + 0x0140)

; CRTC_CONTROL bits
%define CRTC_CONTROL_ENABLE              (1 << 0)
%define CRTC_CONTROL_DISABLE             (0 << 0)
%define CRTC_CONTROL_MASTER_ENABLE       (1 << 1)
%define CRTC_CONTROL_DISPLAY_ENABLE      (1 << 2)

; CRTC_STATUS bits
%define CRTC_STATUS_ENABLED              (1 << 0)
%define CRTC_STATUS_VSYNC_ACTIVE         (1 << 1)
%define CRTC_STATUS_HSYNC_ACTIVE         (1 << 2)

; ============================================================================
; Plane Registers (per plane instance, stride 0x100)
; ============================================================================
%define PLANE_BASE                    0x1000
%define PLANE_STRIDE                  0x100

%define PLANE_CONTROL                 (PLANE_BASE + 0x0000)
%define PLANE_SURFACE_ADDRESS         (PLANE_BASE + 0x0010)
%define PLANE_SURFACE_ADDRESS_HIGH    (PLANE_BASE + 0x0018)
%define PLANE_SURFACE_ADDRESS_NEXT    (PLANE_BASE + 0x0020)
%define PLANE_SURFACE_ADDRESS_NEXT_HIGH (PLANE_BASE + 0x0028)
%define PLANE_SIZE                    (PLANE_BASE + 0x0030)
%define PLANE_SOURCE_SIZE             (PLANE_BASE + 0x0040)
%define PLANE_SOURCE_POSITION         (PLANE_BASE + 0x0050)
%define PLANE_STRIDE                  (PLANE_BASE + 0x0060)
%define PLANE_FORMAT                  (PLANE_BASE + 0x0070)
%define PLANE_TILING_INFO             (PLANE_BASE + 0x0080)
%define PLANE_ALPHA                   (PLANE_BASE + 0x0090)
%define PLANE_SCALE_FACTOR            (PLANE_BASE + 0x00A0)
%define PLANE_SOURCE_SCALE_FACTOR     (PLANE_BASE + 0x00B0)
%define PLANE_COLOR_MATRIX            (PLANE_BASE + 0x00C0)
%define PLANE_GAMUT_REMAP             (PLANE_BASE + 0x00D0)

; PLANE_CONTROL bits
%define PLANE_CONTROL_ENABLE              (1 << 0)
%define PLANE_CONTROL_UPDATE              (1 << 1)
%define PLANE_CONTROL_DISABLE             (0 << 0)

; PLANE_FORMAT values (matches DRM format modifiers)
%define PLANE_FORMAT_BGRA8888             0x41524742
%define PLANE_FORMAT_BGR8888              0x34325242
%define PLANE_FORMAT_RGB565               0x35364247
%define PLANE_FORMAT_XRGB2101010          0x33305258
%define PLANE_FORMAT_XBGR2101010          0x33304258

; ============================================================================
; Cursor Registers (per CRTC, stride 0x100)
; ============================================================================
%define CURSOR_BASE                   0x2000
%define CURSOR_STRIDE                 0x100

%define CURSOR_CONTROL                (CURSOR_BASE + 0x0000)
%define CURSOR_SURFACE_ADDRESS        (CURSOR_BASE + 0x0010)
%define CURSOR_SURFACE_ADDRESS_HIGH   (CURSOR_BASE + 0x0018)
%define CURSOR_SIZE                   (CURSOR_BASE + 0x0020)
%define CURSOR_POSITION               (CURSOR_BASE + 0x0030)
%define CURSOR_HOTSPOT                (CURSOR_BASE + 0x0040)

; CURSOR_CONTROL bits
%define CURSOR_CONTROL_ENABLE           (1 << 0)
%define CURSOR_CONTROL_64x64            (1 << 1)
%define CURSOR_CONTROL_128x128          (1 << 2)
%define CURSOR_CONTROL_256x256          (1 << 3)

; ============================================================================
; DCC (Display Compression) Registers
; ============================================================================
%define DCC_BASE                      0x3000

%define DCC_CONTROL                   (DCC_BASE + 0x0000)
%define DCC_SURFACE_ADDRESS           (DCC_BASE + 0x0010)
%define DCC_SURFACE_ADDRESS_HIGH      (DCC_BASE + 0x0018)
%define DCC_SURFACE_SIZE              (DCC_BASE + 0x0020)
%define DCC_SURFACE_PITCH             (DCC_BASE + 0x0030)
%define DCC_INDEPENDENT_64B_BLOCKS    (DCC_BASE + 0x0040)

; ============================================================================
; DMCU (Display Microcontroller Unit) Registers
; ============================================================================
%define DMCU_BASE                     0x4000

%define DMCU_CONTROL                  (DMCU_BASE + 0x0000)
%define DMCU_STATUS                   (DMCU_BASE + 0x0010)
%define DMCU_MAILBOX                  (DMCU_BASE + 0x0020)
%define DMCU_FIRMWARE_VERSION         (DMCU_BASE + 0x0030)

; ============================================================================
; Link Encoder (PHY) Registers
; ============================================================================
%define LINK_BASE                     0x5000
%define LINK_STRIDE                   0x100

%define LINK_CONTROL                  (LINK_BASE + 0x0000)
%define LINK_STATUS                   (LINK_BASE + 0x0010)
%define LINK_DP_LINK_TRAINING         (LINK_BASE + 0x0020)
%define LINK_DP_LANE_COUNT            (LINK_BASE + 0x0030)
%define LINK_DP_LINK_RATE             (LINK_BASE + 0x0040)
%define LINK_HDMI_TMDS_CONTROL        (LINK_BASE + 0x0050)

; ============================================================================
; Stream Encoder Registers
; ============================================================================
%define STREAM_BASE                   0x6000
%define STREAM_STRIDE                 0x100

%define STREAM_CONTROL                (STREAM_BASE + 0x0000)
%define STREAM_SOURCE_SELECT          (STREAM_BASE + 0x0010)
%define STREAM_DP_STREAM_ATTRIBUTES   (STREAM_BASE + 0x0020)
%define STREAM_HDMI_INFOFRAME         (STREAM_BASE + 0x0030)

; ============================================================================
; Audio Endpoint Registers
; ============================================================================
%define AUDIO_BASE                    0x7000
%define AUDIO_STRIDE                  0x100

%define AUDIO_CONTROL                 (AUDIO_BASE + 0x0000)
%define AUDIO_CHANNEL_ALLOCATION      (AUDIO_BASE + 0x0010)
%define AUDIO_SAMPLE_RATE             (AUDIO_BASE + 0x0020)
%define AUDIO_LAYOUT                  (AUDIO_BASE + 0x0030)

; ============================================================================
; HDCP Registers
; ============================================================================
%define HDCP_BASE                     0x8000

%define HDCP_CONTROL                  (HDCP_BASE + 0x0000)
%define HDCP_STATUS                   (HDCP_BASE + 0x0010)
%define HDCP_KEY_SELECTION            (HDCP_BASE + 0x0020)
%define HDCP_ENCRYPTION_STATUS        (HDCP_BASE + 0x0030)

; ============================================================================
; Global Registers
; ============================================================================
%define GLOBAL_BASE                   0xF000

%define MASTER_UPDATE_LOCK            (GLOBAL_BASE + 0x0000)
%define MASTER_UPDATE_MODE            (GLOBAL_BASE + 0x0010)
%define GLOBAL_SYNC                   (GLOBAL_BASE + 0x0020)
%define GLOBAL_CRC                    (GLOBAL_BASE + 0x0030)

%define INTERRUPT_CONTROL             (GLOBAL_BASE + 0x0100)
%define INTERRUPT_STATUS              (GLOBAL_BASE + 0x0110)
%define INTERRUPT_MASK                (GLOBAL_BASE + 0x0120)
%define INTERRUPT_ACK                 (GLOBAL_BASE + 0x0130)

; ============================================================================
; DCN Version-Specific Register Offsets
; ============================================================================

; DCN 1.0 (Raven Ridge, Picasso) - base offsets as above
%define DCN10_CRTC_STRIDE             0x100
%define DCN10_PLANE_STRIDE            0x100
%define DCN10_CURSOR_STRIDE           0x100

; DCN 2.0 (Renoir, Lucienne) - same as 1.0
%define DCN20_CRTC_STRIDE             0x100
%define DCN20_PLANE_STRIDE            0x100
%define DCN20_CURSOR_STRIDE           0x100

; DCN 3.0 (Rembrandt) - some register moves
%define DCN30_CRTC_STRIDE             0x100
%define DCN30_PLANE_STRIDE            0x100
%define DCN30_CURSOR_STRIDE           0x100
%define DCN30_NEW_PLANE_REGS          1

; DCN 3.1 (Phoenix, Hawk Point)
%define DCN31_CRTC_STRIDE             0x100
%define DCN31_PLANE_STRIDE            0x100

; DCN 3.2, 3.5
%define DCN32_CRTC_STRIDE             0x100
%define DCN35_CRTC_STRIDE             0x100

; ============================================================================
; Family Detection
; ============================================================================

%define DCN_FAMILY_UNKNOWN    0
%define DCN_FAMILY_DCN10      0x1000
%define DCN_FAMILY_DCN20      0x2000
%define DCN_FAMILY_DCN21      0x2100
%define DCN_FAMILY_DCN30      0x3000
%define DCN_FAMILY_DCN31      0x3100
%define DCN_FAMILY_DCN32      0x3200
%define DCN_FAMILY_DCN35      0x3500

%endif ; __DCN_REGS_INC__