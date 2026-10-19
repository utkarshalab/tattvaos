; ============================================================================
; CWP Protocol Constants
; ============================================================================

%ifndef __CWP_INC__
%define __CWP_INC__

; Protocol version
%define CWP_VERSION_MAJOR    1
%define CWP_VERSION_MINOR    0
%define CWP_VERSION          ((CWP_VERSION_MAJOR << 16) | CWP_VERSION_MINOR)

; Message header size
%define CWP_HDR_SIZE         12

; Maximum payload size (from channel.inc)
%define MAX_PAYLOAD_SIZE     65536

; Message flags
%define CWP_MSG_FLAG_NEED_ACK      0x0001
%define CWP_MSG_FLAG_HAS_HANDLES   0x0002
%define CWP_MSG_FLAG_IS_EVENT      0x0004
%define CWP_MSG_FLAG_TRANSACTION   0x0008

; Object types
%define CWP_OBJ_DISPLAY            1
%define CWP_OBJ_OUTPUT             2
%define CWP_OBJ_SURFACE            3
%define CWP_OBJ_REGION             4
%define CWP_OBJ_BUFFER             5
%define CWP_OBJ_CALLBACK           6
%define CWP_OBJ_SEAT               7
%define CWP_OBJ_POINTER            8
%define CWP_OBJ_KEYBOARD           9
%define CWP_OBJ_TOUCH             10
%define CWP_OBJ_TABLET_TOOL       11
%define CWP_OBJ_TABLET_PAD        12
%define CWP_OBJ_DATA_DEVICE       13
%define CWP_OBJ_DATA_SOURCE       14
%define CWP_OBJ_DATA_OFFER        15
%define CWP_OBJ_COMPOSITOR        16
%define CWP_OBJ_SUB_COMPOSITOR    17
%define CWP_OBJ_SHELL             18
%define CWP_OBJ_SHELL_SURFACE     19
%define CWP_OBJ_POOL              20
%define CWP_OBJ_SHM               21
%define CWP_OBJ_INPUT_METHOD      22
%define CWP_OBJ_TEXT_INPUT        23
%define CWP_OBJ_ACCESSIBILITY     24

; Opcode ranges (per object type)
%define CWP_OP_DISPLAY_BASE        0x0000
%define CWP_OP_OUTPUT_BASE         0x0100
%define CWP_OP_SURFACE_BASE        0x0200
%define CWP_OP_REGION_BASE         0x0300
%define CWP_OP_BUFFER_BASE         0x0400
%define CWP_OP_CALLBACK_BASE       0x0500
%define CWP_OP_SEAT_BASE           0x0600
%define CWP_OP_POINTER_BASE        0x0700
%define CWP_OP_KEYBOARD_BASE       0x0800
%define CWP_OP_TOUCH_BASE          0x0900
%define CWP_OP_TABLET_BASE         0x0A00
%define CWP_OP_DATA_BASE           0x0B00
%define CWP_OP_COMPOSITOR_BASE     0x0C00
%define CWP_OP_SHELL_BASE          0x0D00
%define CWP_OP_SHM_BASE            0x0E00
%define CWP_OP_INPUT_METHOD_BASE   0x0F00
%define CWP_OP_ACCESSIBILITY_BASE  0x1000

; Error codes (matching errors.inc)
%define CWP_ERR_INVALID_OBJECT     1
%define CWP_ERR_INVALID_METHOD     2
%define CWP_ERR_NO_MEMORY          3
%define CWP_ERR_IMPLEMENTATION     4
%define CWP_ERR_POST_DEADLINE      5
%define CWP_ERR_DEAD_OBJECT        6

%endif ; __CWP_INC__