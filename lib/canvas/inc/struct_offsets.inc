; ============================================================================
; Common Struct Offsets — Seat, Pointer, Focus, Surface, Buffer, etc.
; Defines both dot and underscore notation for compatibility
; ============================================================================

%ifndef __STRUCT_OFFSETS_INC__
%define __STRUCT_OFFSETS_INC__

; Seat

; All-caps aliases for Seat

; Pointer

; Focus

; Surface

; SurfaceState

; Buffer

; Client

; ClientConn

; Output

; Controller

; Backend

; Mode (extended)

; Mode (basic)

; Mode flags
%define MODE_FLAG_HSYNC_POSITIVE   (1 << 0)
%define MODE_FLAG_VSYNC_POSITIVE   (1 << 1)
%define MODE_FLAG_INTERLACED       (1 << 2)
%define MODE_FLAG_DBLSCAN          (1 << 3)
%define MODE_FLAG_CSYNC            (1 << 4)
%define MODE_FLAG_PCSYNC           (1 << 5)

; Config

; FrameClock

; List

; ListNode

; Arena

; Server

; All-caps aliases for Server

; Clipboard

; All-caps aliases for Clipboard

; DnD

; All-caps aliases for DnD

; Limits

; ClientLimits

; Transfer

; Server additional fields

; Region

; TrustProfile

; GpuDevice

; PixBuf — layout written by pixbuf_create (lib/ugfx/core/pixbuf.asm, see lib/ugfx/include/ugfx.inc). "size" is
; the pixel-data size field; PixBuf_size is the whole object.

; Pixbuf (lowercase alias)

; HuffDec

; PngImage

; Rect

; All-caps aliases for Rect
%define RECT_W 16
%define RECT_H 24

; Cursor

; Grab

; Keyboard

; Pointer
; Pointer embeds InputDevice (64 bytes) so every input device can share the
; intrusive Seat.devices list without overlapping pointer-specific state.

; InputSource

; Tablet
; Tablet embeds InputDevice.

; Touch
; Touch also embeds InputDevice.

; TouchSlot

; FaultDump

; Metrics

; ProtoLog

; ProtoLogEntry

; Recorder

; Replayer

; ClientStats

; FrameTimeline

; FrameMark

; Trace

; TraceEvent

; Server DPMS fields

; FrameCtx

; LayoutEngine

; All-caps aliases for LayoutEngine
%define LAYOUT_ENGINE_ROOT 0
%define LAYOUT_ENGINE_NODE_COUNT 8
%define LAYOUT_ENGINE_GAP_SIZE 16
%define LAYOUT_ENGINE_MASTER_RATIO 24
%define LAYOUT_ENGINE_SMART_GAPS 32
%define LAYOUT_ENGINE_SMART_BORDERS 40
%define LAYOUT_ENGINE_SERVER 48

; LayoutNode

; Toplevel

; Policy

; PolicyExternal

; PolicyKiosk

; State flags
%define STATE_FLAG_FULLSCREEN    (1 << 0)
%define STATE_FLAG_MAXIMIZED     (1 << 1)
%define STATE_FLAG_TILED         (1 << 2)
%define STATE_FLAG_FLOATING      (1 << 3)
%define STATE_FLAG_MODAL         (1 << 4)

; VirtualOutput

; RfbClient

; CrpServer

; CrpSession

; RfbServer

; RfbServer (full)

; RfbClient (full)

; GpuRenderer

; GpuDevice

; Renderer (software renderer)

; FrameCtx

; Render capabilities
%define RENDER_CAP_BLEND         (1 << 0)
%define RENDER_CAP_SCALE         (1 << 1)
%define RENDER_CAP_TRANSFORM     (1 << 2)
%define RENDER_CAP_DIRECT_SCANOUT (1 << 3)

; Gate

; AuditEntry

; TrustProfile

; Prompt modes
%define PROMPT_NEVER      0
%define PROMPT_PRIVILEGED 1
%define PROMPT_ALL        2

; Profile types
%define PROFILE_TRUSTED    0
%define PROFILE_STANDARD   1
%define PROFILE_SANDBOXED  2
%define PROFILE_REMOTE     3
%define PROFILE_KIOSK      4
%define PROFILE_CUSTOM     5

; Profile flags
%define PROFILE_FLAG_NO_PROMPTS     (1 << 0)
%define PROFILE_FLAG_UNLIMITED_MEM  (1 << 1)
%define PROFILE_FLAG_NO_AUDIT       (1 << 2)

; AuditLog

; Prompt

; PromptOption

; Token

; Object

; Fence (full)

; WaitQueue

; ListNode

; IdleManager

; KioskSession

; LockScreen

; Session

; Multiseat

; PowerManager

; SeatSession

; UserSession

; Configure

; Decoration

; DecorationDrawState

; DecorationButton

; Button states
%define BUTTON_STATE_NORMAL     0
%define BUTTON_STATE_HOVER      1
%define BUTTON_STATE_PRESSED    2
%define BUTTON_STATE_DISABLED   3

; Layer

; MoveResize

; Popup

; Rule

; Theme

; ThemeColors

; Toplevel

; Workspace

; IMEBridge

; IMEInfo

; PreeditString

; PreeditAttribute

; Shortcut

; TextInput

; ============================================================================
; Compositor Structs
; ============================================================================

; Damage

; DamageRect

; Output

; All-caps aliases for Output
%define OUTPUT_DAMAGE 112
%define OUTPUT_FRAME_CLOCK 232

; SurfaceState (additional fields for compositor)

; All-caps aliases for SurfaceState
%define SURFACE_STATE_BUFFER 0
%define SURFACE_STATE_DAMAGE 8
%define SURFACE_STATE_PENDING 16
%define SURFACE_STATE_BUF_X 24
%define SURFACE_STATE_BUF_Y 32
%define SURFACE_STATE_INPUT 36
%define SURFACE_STATE_OPAQUE 44
%define SURFACE_STATE_WIDTH 48
%define SURFACE_STATE_HEIGHT 56
%define SURFACE_STATE_TRANSFORM 64
%define SURFACE_STATE_SCALE 72
%define SURFACE_STATE_FRAME_CBS 80
%define SURFACE_STATE_SUBSURFACES 88
%define SURFACE_STATE_STRIDE 96

; FrameClock

; All-caps aliases for FrameClock
%define FRAME_CLOCK_CALLBACKS 0
%define FRAME_CLOCK_NEXT_VBLANK 8
%define FRAME_CLOCK_REFRESH_NS 16

; Compositor

; All-caps aliases for Compositor

; RenderEntry

; All-caps aliases for RenderEntry
%define RENDER_ENTRY_SURFACE 0
%define RENDER_ENTRY_X 8
%define RENDER_ENTRY_Y 16
%define RENDER_ENTRY_Z 24
%define RENDER_ENTRY_ALPHA 28
%define RENDER_ENTRY_TRANSFORM 32
%define RENDER_ENTRY_CLIP 40
%define RENDER_ENTRY_NEXT 48

; FrameCallback

; ============================================================================
; Shell Structs
; ============================================================================

; Shell

; All-caps aliases for Shell
%define SHELL_ACTIVE_WS_IDX 60
%define SHELL_CLIPBOARD 108
%define SHELL_PRIMARY_SELECTION 112
%define SHELL_DRAG_SOURCE 116
%define SHELL_DRAG_ICON 120
%define SHELL_DRAG_ACTIONS 124
%define SHELL_DRAG_SERIAL 128

; Toplevel

; All-caps aliases for Toplevel

; Decoration

; All-caps aliases for Decoration

; DecorationButton

; All-caps aliases for DecorationButton
%define DECOR_BTN_RECT 0
%define DECOR_BTN_TYPE 16
%define DECOR_BTN_STATE 20
%define DECOR_BTN_CALLBACK 24
%define DECOR_BTN_USER_DATA 32
%define DECOR_BTN_NEXT 40

; Workspace

; All-caps aliases for Workspace

; Layer

; Popup

; All-caps aliases for Popup

; Configure

; All-caps aliases for Configure

; DecorationDrawState

; All-caps aliases for DecorationDrawState
%define DECORATION_DRAW_FB 0
%define DECORATION_DRAW_STRIDE 8
%define DECORATION_DRAW_WIDTH 16
%define DECORATION_DRAW_HEIGHT 20
%define DECORATION_DRAW_TITLE_BG 24
%define DECORATION_DRAW_BORDER 28
%define DECORATION_DRAW_BTN_BG 32
%define DECORATION_DRAW_BTN_FG 36
%define DECORATION_DRAW_INACTIVE 40

; LayoutEngine

; All-caps aliases for LayoutEngine
%define LAYOUT_ENGINE_ROOT 0
%define LAYOUT_ENGINE_NODE_COUNT 8
%define LAYOUT_ENGINE_GAP_SIZE 16
%define LAYOUT_ENGINE_MASTER_RATIO 24
%define LAYOUT_ENGINE_SMART_GAPS 32
%define LAYOUT_ENGINE_SMART_BORDERS 40
%define LAYOUT_ENGINE_SERVER 48

; LayoutNode

; All-caps aliases for LayoutNode
%define LAYOUT_NODE_TYPE 0
%define LAYOUT_NODE_LEFT 8
%define LAYOUT_NODE_RIGHT 16
%define LAYOUT_NODE_PARENT 24
%define LAYOUT_NODE_RECT 32
%define LAYOUT_NODE_CLIENT 40
%define LAYOUT_NODE_RATIO 48
%define LAYOUT_NODE_IS_MASTER 56
%define LAYOUT_NODE_TOPLEVEL 64
%define LAYOUT_NODE_X 72
%define LAYOUT_NODE_Y 80
%define LAYOUT_NODE_WIDTH 88
%define LAYOUT_NODE_HEIGHT 96
%define LAYOUT_NODE_GAP 104

; Policy

; All-caps aliases for Policy

; Theme

; All-caps aliases for Theme

; ThemeColors

; All-caps aliases for ThemeColors
%define THEME_COLOR_BG 0
%define THEME_COLOR_FG 4
%define THEME_COLOR_ACCENT 8
%define THEME_COLOR_BORDER 12
%define THEME_COLOR_TITLE_BG 16
%define THEME_COLOR_TITLE_FG 20
%define THEME_COLOR_BTN_BG 24
%define THEME_COLOR_BTN_FG 28
%define THEME_COLOR_BTN_HOVER_BG 32
%define THEME_COLOR_BTN_HOVER_FG 36
%define THEME_COLOR_BTN_PRESSED_BG 40
%define THEME_COLOR_BTN_PRESSED_FG 44

; ---------------------------------------------------------------------------
; Shared object layouts: one struc per object. A layout used by a single
; module lives in that module; one owned by a subsystem header lives there.
; ---------------------------------------------------------------------------

struc Arena
    .base:                    resq 1
    .cursor:                  resq 1
    .limit:                   resq 1
    .parent:                  resq 1
endstruc

struc AuditEntry
    .timestamp:               resq 1
    .client_id:               resq 1
    .action:                  resd 1
    .capability:              resq 1
    .result:                  resd 1
    .details_len:             resq 1
    .details:                 resq 1
endstruc

struc AuditLog
    .buffer:                  resq 1
    .capacity:                resq 1
    .head:                    resq 1
    .tail:                    resq 1
    .element_size:            resq 1
    .count:                   resq 1
endstruc

; Fields are qwords so that a dword store and a qword read agree; the header
; is zeroed when created.
struc Buffer
    .handle:                  resq 1
    .generation:              resq 1
    .width:                   resq 1
    .height:                  resq 1
    .stride:                  resq 1
    .format:                  resq 1
    .modifier:                resq 1
    .base:                    resq 1
    .dma_addr:                resq 1
    .size:                    resq 1
    .acquire_fence:           resq 1
    .release_fence:           resq 1
    .timeline:                resq 1
    .acquire_point:           resq 1
    .release_point:           resq 1
    .state:                   resq 1
    .refcount:                resq 1
    .client_id:               resq 1
    .gpu_bo:                  resq 1
    .client:                  resq 1
    .client_next:             resq 1    ; the client's buffers
    .region:                  resq 1    ; the pixels' memory region
endstruc

struc Client
    .id:                      resq 1
    .trust_profile:           resq 1
    .caps:                    resq 1
    .arena:                   resq 1
    .obj_table:               resq 1
    .tx_ring:                 resq 1
    .rx_ring:                 resq 1
    .handle_tx:               resq 1
    .handle_rx:               resq 1
    .quota:                   resq 1
    .next_obj:                resq 1
    resb 16
    .last_ping:               resq 1
    .state:                   resb 1
    resb 7
    .ping_serial:             resq 1
    .ratelimit:               resq 1
    .verified:                resb 1
    resb 7
    .region:                  resq 1
    .surfaces:                resq 1    ; its Surfaces, through client_next
    .buffers:                 resq 1    ; its Buffers, through client_next
    .server:                  resq 1
    .next_client:             resq 1    ; Server.client_list
    .regions:                 resq 1    ; its ClientRegions (server/regions)
    .fences:                  resq 1    ; its Fences (server/fence)
    .timelines:               resq 1    ; its Timelines (server/timeline)
    resb 64
endstruc

struc ClientConn
    .server_chan:             resq 1
    .tx_ring:                 resq 1
    .rx_ring:                 resq 1
    .handle_tx:               resq 1
    .handle_rx:               resq 1
    .caps_wanted:             resq 1
    .caps_granted:            resq 1
    .next_obj:                resq 1
    .arena:                   resq 1
    .region_handle:           resq 1
    .buffer_count:            resq 1
    .clip_len:                resq 1
    .clip_mime_len:           resq 1
    .present_valid:           resq 1
    .present_info:            resq 1
    resb 40
    .arena_state:             resq 1
endstruc

struc ClientLimits
    .clipboard_bytes:         resq 1
    .selection_bytes:         resq 1
    .dnd_bytes:               resq 1
    .messages_sent:           resq 1
    .bytes_sent:              resq 1
    .last_reset:              resq 1
endstruc

struc ClientStats
    .client_id:               resq 1
    .frames:                  resq 1
    .commits:                 resq 1
    .damages:                 resq 1
    .events_in:               resq 1
    .events_out:              resq 1
    .bytes_in:                resq 1
    .bytes_out:               resq 1
    .last_commit:             resq 1
    .last_present:            resq 1
    .commit_to_present_ns:    resq 1
    .mem_bytes:               resq 1
    .last_reset:              resq 1
    .proto_errors:            resq 1
endstruc

; The clipboard and the primary selection (src/data/clipboard.asm), at
; Server.clipboard: what each offers, and the pastes under way
%define CLIP_SELECTIONS     2
%define CLIP_TYPES          4
%define CLIP_TYPE_LEN       32
%define CLIP_TRANSFERS      8
%define CLIP_CHUNK          120         ; bytes in one data request or event
%define CLIP_MAX            16384       ; bytes in one paste, and held
struc ClipOffer
    .owner:                   resq 1    ; Client*, 0: none, or the server's own
    .count:                   resd 1    ; types offered, 0: nothing
    .held_len:                resd 1    ; the server's own data's length
    .held:                    resq 1    ; the server's own data, CLIP_MAX
    .types:                   resb 128  ; CLIP_TYPES x CLIP_TYPE_LEN
endstruc
struc ClipTransfer
    .serial:                  resd 1    ; 0: a free slot
    .sent:                    resd 1    ; bytes so far
    .receiver:                resq 1    ; Client* pasting
    .owner:                   resq 1    ; Client* asked for the data
endstruc
struc ClipboardState
    .offers:                  resb 304  ; CLIP_SELECTIONS ClipOffer
    .transfers:               resb 192  ; CLIP_TRANSFERS ClipTransfer
    .next_serial:             resd 1
    resb 4
endstruc
%if ClipOffer_size * CLIP_SELECTIONS != 304 || ClipTransfer_size * CLIP_TRANSFERS != 192 || CLIP_TYPES * CLIP_TYPE_LEN != 128
    %error "ClipboardState: its sizes must follow ClipOffer, ClipTransfer, CLIP_*"
%endif

struc Compositor
    .server:                  resq 1
    .renderer:                resq 1
    .arena:                   resq 1
    .damage_ring:             resq 1
    .frame_seq:               resq 1
    .cursor:                  resq 1
    .cursor_x:                resq 1
    .cursor_y:                resq 1
    .bg_color:                resq 1
    .damage:                  resq 1
    .frame_clock:             resq 1
    .outputs:                 resq 1
    .render_list:             resq 1
    .drawn:                   resq 1    ; surfaces drawn, ever (for tests)
    .cursor_on:               resq 1    ; 1: the software cursor is drawn
    .cursor_hidden:           resq 1    ; 1: hidden while typing, until a move
endstruc

struc Configure
    .serial:                  resq 1
    .surface:                 resq 1
    .width:                   resd 1
    .height:                  resd 1
    .states:                  resd 1
    .callback:                resq 1
    .user_data:               resq 1
    .ack_callback:            resq 1
    .next:                    resq 1
    resb 4
endstruc

struc Controller
    .state:                   resq 1
    .pci_dev:                 resq 1
    .mmio_base:               resq 1
    .fb_base:                 resq 1
    .fb_size:                 resq 1
    .family:                  resq 1
    .outputs:                 resq 1
    .output_count:            resq 1
    .state_size:              resq 1
    .family_detected:         resb 1
    resb 7
    .irq:                     resq 1
endstruc

struc CrpServer
    .server:                  resq 1
    .listener:                resq 1
    .port:                    resd 1
    .sessions:                resq 1
    .voutput:                 resq 1
    .running:                 resb 1
endstruc

struc CrpSession
    .server:                  resq 1
    .conn:                    resq 1
    .view_only:               resb 1
    .seq:                     resq 1
    .next:                    resq 1
endstruc

struc Cursor
    .pixbuf:                  resq 1
    .hotspot_x:               resq 1
    .hotspot_y:               resq 1
    .delay:                   resq 1
    .next_frame:              resq 1
    .current:                 resq 1
endstruc

struc Damage
    .rects:                   resq 1
    .count:                   resq 1
    .capacity:                resq 1
    .arena:                   resq 1
endstruc

struc DamageRect
    .x:                       resd 1
    .y:                       resd 1
    .w:                       resd 1
    .h:                       resq 1
    resb 4
endstruc

struc Decoration
    .toplevel:                resq 1
    .mode:                    resq 1
    .theme:                   resq 1
    .buttons:                 resq 1
    .button_count:            resd 1
    .titlebar_h:              resd 1
    .border_w:                resq 1
    .frame_cb:                resq 1
    .render_data:             resq 1
    .border_width:            resd 1
    resb 4
    .frame_callback:          resq 1
    .renderer_data:           resq 1
    .titlebar_height:         resd 1
    resb 4
endstruc

struc DecorationButton
    .rect:                    resq 1
    resb 8
    .type:                    resd 1
    .state:                   resd 1
    .callback:                resq 1
    .user_data:               resq 1
endstruc

struc DecorationDrawState
    .framebuffer:             resq 1
    .stride:                  resq 1
    .width:                   resd 1
    .height:                  resd 1
    .titlebar_color:          resd 1
    .border_color:            resd 1
    .button_bg_color:         resd 1
    .button_fg_color:         resd 1
    .inactive_alpha:          resd 1
    resb 4
endstruc

struc DnD
    .seat:                    resq 1
    .source_client:           resq 1
    .source_surface:          resq 1
    .target_client:           resq 1
    .target_surface:          resq 1
    .drag_icon:               resq 1
    .grab:                    resq 1
    .offered_mimes:           resq 1
    .mime_count:              resq 1
    .selected_mime:           resq 1
    .selected_mime_len:       resq 1
    .action:                  resd 1
    .actions:                 resd 1
    .serial:                  resq 1
    .state:                   resd 1
    resb 4
endstruc

struc FaultDump
    .time_ns:                 resq 1
    .fault_code:              resq 1
    .client_id:               resq 1
    .object:                  resq 1
    .opcode:                  resd 1
    .rax:                     resq 1
    .rcx:                     resq 1
    .rsi:                     resq 1
    .rbp:                     resq 1
    .r8:                      resd 1
    .r9:                      resd 1
    .r10:                     resd 1
    .r11:                     resd 1
    .r12:                     resd 1
    .r13:                     resd 1
    .r14:                     resd 1
    .r15:                     resd 1
    .rip:                     resq 1
    .rflags:                  resq 1
    resb 4
    .rbx:                     resq 1
    .rdi:                     resq 1
    .rdx:                     resq 1
    .rsp:                     resq 1
endstruc

struc Fence
    .handle:                  resd 1
    .generation:              resd 1
    .type:                    resd 1
    .signaled:                resd 1
    .waiters:                 resq 1
    .client_id:               resq 1
    resb 4
    .arena:                   resq 1
    resb 4
    .lock:                    resq 1
    .client:                  resq 1    ; whose it is
    .next:                    resq 1    ; Client.fences
    .state:                   resd 1
    resb 4
    .timeline:                resq 1
    .value:                   resq 1
endstruc

struc Focus
    .seat:                    resq 1
    .surface:                 resq 1
    .serial:                  resq 1
    .keys:                    resq 1
    .modifiers:               resd 1
endstruc

struc FrameCallback
    .surface:                 resq 1
    .seq:                     resq 1
    .timestamp:               resq 1
    .next:                    resq 1
endstruc

struc FrameClock
    .output:                  resq 1
    .refresh_ns:              resq 1
    .next_vblank:             resq 1
    .phase:                   resq 1
    .callbacks:               resq 1
endstruc

struc FrameMark
    .time_ns:                 resq 1
    .frame_number:            resq 1
    .flags:                   resq 1
    .frame_seq:               resq 1
    .composite_start:         resq 1
    .composite_end:           resq 1
    .flip_time:               resq 1
    .vblank_time:             resq 1
    .present_time:            resq 1
    .damage_bytes:            resq 1
endstruc

struc FrameTimeline
    .server:                  resq 1
    .marks:                   resq 1
    .capacity:                resq 1
    .count:                   resq 1
    .head:                    resq 1
    .seq:                     resq 1
endstruc

struc Gate
    .server:                  resq 1
    .audit_log:               resq 1
endstruc

struc GpuDevice
    .server:                  resq 1
    .fence_mgr:               resq 1
    .mem:                     resq 1
    .mem_mgr:                 resq 1
    .ring_gfx:                resq 1
    .ring_compute:            resq 1
    .ring_sdma:               resq 1
    .mmio_base:               resq 1
    .mmio_size:               resq 1
    .family:                  resd 1
    resb 4
    .enabled:                 resq 1
    .gtt_heap:                resq 1
    .vram_heap:               resq 1
endstruc

struc GpuRenderer
    .base:                    resq 1
    .gpu:                     resq 1
    .sw_fallback:             resb 1
    resb 7
endstruc

struc Grab
    .next:                    resq 1
    .type:                    resq 1
    .seat:                    resq 1
    .owner:                   resq 1
    .serial:                  resq 1
    .cursor:                  resq 1
    .surface:                 resq 1
    .confine:                 resq 1
endstruc

struc HuffDec
    .state:                   resq 1
    .bitstate:                resq 1
    .literal_table:           resq 1
    .distance_table:          resq 1
    resb 272
endstruc

struc HuffTable
    .counts:                  resb 16
    .symbols:                 resb 256
    .max_syms:                resd 1
    .codes:                   resb 1024
    .sizes:                   resb 256
endstruc

struc IMEBridge
    .seat:                    resq 1
    .active_ime:              resq 1
    .available_imes:          resq 1
    .ime_count:               resd 1
    .focused_text_input:      resq 1
    resb 4
endstruc

struc IMEInfo
    .name:                    resq 1
    .engine:                  resq 1
    .capabilities:            resq 1
    .language:                resq 1
    resb 8
endstruc

struc IdleManager
    .server:                  resq 1
    .idle_timeout:            resq 1
    .warning_time:            resq 1
    .timer:                   resq 1
    .callbacks:               resq 1
    .inhibit_count:           resd 1
    resb 4
endstruc

struc InputSource
    .type:                    resq 1
    .name:                    resq 1
    .init:                    resq 1
    .deinit:                  resq 1
    .start:                   resq 1
    .stop:                    resq 1
    .get_device:              resq 1
    .grab:                    resq 1
    .next:                    resq 1
    .virtual:                 resq 1
    .virtual_ring:            resq 1
    .virtual_size:            resq 1
endstruc

struc Keyboard
    resb 64
    .keymap:                  resq 1
    .modifiers:               resd 1
    .leds:                    resd 1
    .repeat:                  resq 1
    .pressed_keys:            resq 1
    .pressed_count:           resd 1
    .repeat_key:              resd 1
    .repeat_timer:            resq 1
    .repeat_rate:             resd 1
    .repeat_delay:            resq 1
    resb 4
endstruc

struc KioskSession
    .session:                 resq 1
    .allowed_app_id:          resq 1
    .restart_on_exit:         resb 1
    .allow_exit:              resb 7
    .lock_screen:             resq 1
    .watchdog_timer:          resq 1
endstruc

struc Layer
    .surface:                 resq 1
    .shell:                   resq 1
    .output:                  resq 1
    .layer:                   resq 1
    .namespace:               resq 1
    .anchor:                  resq 1
    .exclusive_zone:          resd 1
    .keyboard_int:            resd 1
    .width:                   resd 1
    .height:                  resd 1
    .margin_top:              resd 1
    .margin_right:            resd 1
    .margin_bottom:           resd 1
    .margin_left:             resd 1
    .next:                    resq 1
    .keyboard_interactivity:  resq 1
endstruc

struc LayoutEngine
    .root:                    resq 1
    .node_count:              resq 1
    .gap_size:                resq 1
    .master_ratio:            resq 1
    .smart_gaps:              resq 1
    .smart_borders:           resq 1
    .server:                  resq 1
endstruc

struc LayoutNode
    .type:                    resq 1
    .left:                    resq 1
    .right:                   resq 1
    .parent:                  resq 1
    .rect:                    resq 1
    .client:                  resq 1
    .ratio:                   resq 1
    .is_master:               resq 1
    .toplevel:                resq 1
    .x:                       resq 1
    .y:                       resq 1
    .width:                   resq 1
    .height:                  resq 1
    .gap:                     resd 1
    resb 4
endstruc

struc Limits
    .clipboard_max:           resq 1
    .selection_max:           resq 1
    .dnd_max:                 resq 1
    .offer_mimes_max:         resq 1
    .rate_msg_per_sec:        resq 1
    .rate_bytes_per_sec:      resq 1
    .per_client_limits:       resq 1
endstruc

struc List
    .head:                    resq 1
    .tail:                    resq 1
    .count:                   resq 1
endstruc

struc ListNode
    .prev:                    resq 1
    .next:                    resq 1
    .data:                    resq 1
endstruc

struc LockScreen
    .session:                 resq 1
    .surface:                 resq 1
    .password_hash:           resq 1
    .attempts:                resd 1
    .max_attempts:            resd 1
    .lock_time:               resq 1
    .unlock_callback:         resq 1
    .user_data:               resq 1
    .state:                   resq 1
    .next:                    resq 1
endstruc

struc Metrics
    .server:                  resq 1
    .frames:                  resq 1
    .dropped:                 resq 1
    .commits:                 resq 1
    .presents:                resq 1
    .input_events:            resq 1
    .proto_errors:            resq 1
    .faults:                  resq 1
    .last_fps_time:           resq 1
    .last_frames:             resq 1
    .fps:                     resq 1
endstruc

struc MoveResize
    .seat:                    resq 1
    .toplevel:                resq 1
    .type:                    resd 1
    .edges:                   resd 1
    .start_x:                 resd 1
    .start_y:                 resd 1
    .initial_x:               resd 1
    .initial_y:               resd 1
    .surface_x:               resd 1
    .surface_y:               resd 1
    .grab_serial:             resq 1
    .grab_time:               resq 1
endstruc

struc Multiseat
    .server:                  resq 1
    .seats:                   resq 1
    .seat_count:              resq 1
    .default_seat:            resq 1
endstruc

struc Object
    .interface_id:            resw 1
    .version:                 resw 1
    .refcount:                resq 1
    .data_ptr:                resd 1
    .client_id:               resq 1
endstruc

struc PixBuf
    .width:                   resq 1
    .height:                  resq 1
    .stride:                  resq 1
    .format:                  resq 1
    .data:                    resq 1
    .size:                    resq 1
    .refcount:                resq 1
    .arena:                   resq 1
endstruc

struc Pixbuf
    .width:                   resq 1
    .height:                  resq 1
    .format:                  resq 1
    .stride:                  resq 1
    .data:                    resq 1
    resb 8
endstruc

struc PngImage
    .width:                   resd 1
    .height:                  resd 1
    .bit_depth:               resb 1
    .color_type:              resb 1
    .channels:                resb 1
    .compression:             resb 1
    .filter:                  resb 1
    .interlace:               resb 3
    .idat_buf:                resq 1
    .idat_len:                resq 1
    .idat_cap:                resq 1
    .arena:                   resq 1
    .idat_buf_ptr:            resq 1
    .pixbuf:                  resq 1
    .palette:                 resq 1
    .palette_entries:         resq 1
    .transparency:            resq 1
    .transparency_len:        resq 1
endstruc

struc Pointer
    resb 24
    .seat:                    resq 1
    resb 32
    .x:                       resd 1
    .y:                       resd 1
    .buttons:                 resd 1
    .serial:                  resd 1
    .focus:                   resq 1
    .constraint:              resq 1
    .accel:                   resq 1
    .grab:                    resq 1
    .confined:                resb 1
    .locked:                  resb 3
    .lock_x:                  resd 1
    .lock_y:                  resq 1
    .cursor:                  resq 1
endstruc

struc Policy
    .server:                  resq 1
    .layout:                  resq 1
    .configure:               resq 1
    .focus_change:            resq 1
    .new_window:              resq 1
    .close_window:            resq 1
    .tile_window:             resq 1
    .window_configured:       resq 1
    .kiosk_allowed_app:       resq 1
    .type:                    resq 1
    .workspace_changed:       resq 1
    .ws_changed:              resq 1
endstruc

struc PolicyExternal
    .base:                    resq 1
    .server:                  resq 1
    .client:                  resq 1
    .channel:                 resq 1
    .capabilities:            resq 1
    .pending_requests:        resq 1
    resb 8
endstruc

struc PolicyKiosk
    .base:                    resq 1
    .server:                  resq 1
    .data:                    resq 1
    .allowed_app_id:          resq 1
    .allow_exit:              resb 1
    .auto_restart:            resb 1
    resb 6
endstruc

struc Popup
    .surface:                 resq 1
    .shell:                   resq 1
    .parent:                  resq 1
    .position:                resd 1
    .x:                       resd 1
    .y:                       resd 1
    .width:                   resd 1
    .height:                  resd 1
    .constrain:               resd 1
    .next:                    resq 1
endstruc

struc PowerManager
    .server:                  resq 1
    .inhibit_mask:            resq 1
    .suspend_callback:        resq 1
    .resume_callback:         resq 1
    .battery_level:           resq 1
    .ac_connected:            resb 1
    .suspending:              resb 1
    resb 6
endstruc

struc PreeditAttribute
    .type:                    resd 1
    .start:                   resd 1
    .end:                     resd 1
    .color:                   resd 1
endstruc

struc PreeditString
    .text:                    resq 1
    .text_len:                resq 1
    .cursor:                  resd 1
    .selection_start:         resd 1
    .selection_end:           resq 1
    .attributes:              resq 1
    .attr_count:              resd 1
    resb 4
endstruc

struc Prompt
    .client:                  resq 1
    .message:                 resq 1
    .message_len:             resq 1
    .capability:              resq 1
    .options:                 resq 1
    .option_count:            resd 1
    .callback:                resq 1
    .user_data:               resq 1
    .timeout:                 resq 1
    .state:                   resd 1
endstruc

struc PromptOption
    .text:                    resq 1
    .text_len:                resq 1
    .action:                  resd 1
    .value:                   resq 1
    resb 4
endstruc

struc ProtoLog
    .server:                  resq 1
    .buf:                     resq 1
    .capacity:                resq 1
    .write_pos:               resq 1
    .count:                   resq 1
    .enabled:                 resq 1
    .dropped:                 resq 1
endstruc

struc ProtoLogEntry
    .time_ns:                 resq 1
    .dir:                     resd 1
    .opcode:                  resd 1
    .client_id:               resq 1
    .obj:                     resq 1
    .flags:                   resd 1
    .len:                     resd 1
    .payload_off:             resq 1
    .payload:                 resq 1
endstruc

struc Quota
    .max_mem:                 resq 1
    .used_mem:                resq 1
    .max_surfs:               resd 1
    .used_surfs:              resd 1
    .max_bufs:                resd 1
    .used_bufs:               resd 1
    .max_objs:                resd 1
    .used_objs:               resd 1
    .client:                  resq 1
endstruc

struc Recorder
    .server:                  resq 1
    .active:                  resb 1
    resb 7
    .path:                    resq 1
    .path_len:                resq 1
    .frames:                  resq 1
    .msg_count:               resq 1
    .bytes:                   resq 1
    .start_time:              resq 1
    .file:                    resq 1
endstruc

struc Region
    .rects:                   resq 1
    .count:                   resq 1
    .capacity:                resq 1
    .arena:                   resq 1
endstruc

struc RenderEntry
    .surface:                 resq 1
    .x:                       resq 1
    .y:                       resq 1
    .z:                       resd 1
    .alpha:                   resd 1
    .transform:               resq 1
    .clip:                    resq 1
    .next:                    resq 1
endstruc

struc Renderer
    .backend:                 resq 1
    .arena:                   resq 1
    .begin_frame:             resq 1
    .render_surface:          resq 1
    .render_rect:             resq 1
    .end_frame:               resq 1
    .flush:                   resq 1
    .caps:                    resq 1
    .blend_fn:                resq 1
endstruc

struc Replayer
    .server:                  resq 1
    .active:                  resq 1
    .frames_total:            resq 1
    .frames_done:             resq 1
    .mismatches:              resq 1
    .expected_crc:            resq 1
endstruc

struc RfbClient
    .server:                  resq 1
    .conn:                    resq 1
    .width:                   resd 1
    .height:                  resd 1
    .shared:                  resq 1
    .encodings:               resq 1
    .enc_count:               resq 1
    .next:                    resq 1
endstruc

struc RfbServer
    .server:                  resq 1
    .listener:                resq 1
    .port:                    resq 1
    .clients:                 resq 1
    .client_count:            resq 1
    .voutput:                 resq 1
    .running:                 resb 1
    resb 7
endstruc

struc Rule
    .pattern_type:            resq 1
    .pattern:                 resq 1
    .action:                  resq 1
    .action_data:             resq 1
    .priority:                resd 1
    .enabled:                 resd 1
    .next:                    resq 1
endstruc

struc Seat
    .id:                      resq 1
    .capabilities:            resq 1
    .pointer:                 resq 1
    .keyboard:                resq 1
    .touch:                   resq 1
    .name:                    resq 1
    .tablet:                  resq 1
    .focus:                   resq 1
    .grab:                    resq 1
    .keymap:                  resq 1
    .repeat:                  resq 1
    .pointer_accel:           resq 1
    .constraints:             resq 1
    .cursor:                  resq 1
    .devices:                 resq 1
    .next:                    resq 1
    .session:                 resq 1
    .session_session:         resq 1
    .shell:                   resq 1
    .ime_bridge:              resq 1
    .ime_arena:               resq 1
    .arena:                   resq 1
    .pointer_focus:           resq 1
    .keyboard_focus:          resq 1
    .selection_source:        resq 1
    .selection_serial:        resq 1
    .drag_source:             resq 1
    .drag_icon:               resq 1
    .drag_actions:            resq 1
endstruc

struc SeatSession
    .seat:                    resq 1
    .user_id:                 resq 1
    .active:                  resb 1
    .locked:                  resb 7
    .lock_surface:            resq 1
    .idle_timer:              resq 1
    .idle_timeout:            resq 1
    .inhibit_count:           resq 1
    .power_inhibit:           resq 1
endstruc

struc Server
    .arena:                   resq 1
    .backend:                 resq 1
    .clipboard:               resq 1    ; ClipboardState (data/clipboard)
    .primary_selection:       resq 1    ; unused: a selection is an index
    .dnd:                     resq 1
    .seat:                    resq 1
    .outputs:                 resq 1
    .clients:                 resq 1
    .accounting:              resq 1
    .containment:             resq 1
    .quotas:                  resq 1
    .ratelimits:              resq 1
    .scheduler:               resq 1
    .watchdog:                resq 1
    .client_registry:         resq 1
    .gpu:                     resq 1
    .cursors:                 resq 1
    .cursor_theme:            resq 1
    .focus:                   resq 1
    .grabs:                   resq 1
    .grab_count:              resq 1
    .surfaces:                resq 1
    .z_order_tree:            resq 1
    .input_sources:           resq 1
    .seats:                   resq 1
    .seat_count:              resq 1
    .default_seat:            resq 1
    .debug:                   resq 1
    .faultdump:               resq 1
    .metrics:                 resq 1
    .protolog:                resq 1
    .recorder:                resq 1
    .replayer:                resq 1
    .client_stats:            resq 1
    .layout_bounds:           resq 1
    .policy:                  resq 1
    .crp:                     resq 1
    .rfb:                     resq 1
    .gpu_renderer:            resq 1
    .cap_table:               resq 1
    .gate:                    resq 1
    .isolation:               resq 1
    .audit_log:               resq 1
    .verifier:                resq 1
    .prompts:                 resq 1
    .prompt_count:            resq 1
    .trust_profiles:          resq 1
    .buffer_table:            resq 1
    .buffer_pool:             resq 1
    .token_key:               resq 1
    .damage_region:           resq 1
    .fence_table:             resq 1
    .region_table:            resq 1
    .surface_table:           resq 1
    .timeline_table:          resq 1
    .idle_manager:            resq 1
    .kiosk_sessions:          resq 1
    .lock_screens:            resq 1
    .power_manager:           resq 1
    .multiseat:               resq 1
    .configure_serial:        resq 1
    .configure_list:          resq 1
    .user_sessions:           resq 1
    .session_count:           resq 1
    .next_session_id:         resq 1
    .decoration_theme:        resq 1
    .layers:                  resq 1
    .layer_count:             resq 1
    .move_resize:             resq 1
    .popups:                  resq 1
    .rules:                   resq 1
    .rules_count:             resq 1
    .theme:                   resq 1
    .toplevels:               resq 1
    .subsurface:              resq 1
    .shortcuts:               resq 1
    .text_inputs:             resq 1
    .a11y_events:             resq 1
    .a11y_reader_hooks:       resq 1
    .a11y_tree:               resq 1
    .caps:                    resq 1
    .controller:              resq 1
    .dpms_off_timeout:        resq 1
    .dpms_state:              resq 1
    .dpms_suspend_timeout:    resq 1
    .dpms_timeout:            resd 1
    resb 4
    .fb_base:                 resq 1
    .fb_size:                 resq 1
    .frame_timeline:          resq 1
    .irq:                     resq 1
    .magnifier:               resq 1
    .mmio_base:               resq 1
    .mmio_size:               resq 1
    .next_client_id:          resq 1
    .client_list:             resq 1    ; every client, newest first
    .compositor:              resq 1
    .dispatch:                resq 1
    .output_count:            resq 1
    .pci_dev:                 resq 1
    .sticky_keys:             resq 1
    .trace:                   resq 1
    .transfer_count:          resq 1
    .transfers:               resq 1
    .input_seat:              resq 1    ; the active seat: all input goes to it
    .greeter:                 resq 1    ; the login screen, stepped each turn
    .taskbar:                 resq 1    ; the built-in taskbar, likewise
    .spare_taskbars:          resq 1    ; stopped ones, for the next to use
    .locked:                  resq 1    ; 1 while the login screen is up
    .focus_seq:               resq 1    ; the last Window.focus_seq given
    .stack:                   resq 1    ; every surface shown, bottom to top
    .windows:                 resq 1    ; every Window, newest first
    .window_seq:              resq 1    ; the last Window.number given
    .window_active:           resq 1    ; the number the window list last said
    .window_lists:            resq 8    ; WINDOW_LIST_MAX subscribed Client*s
    .workspace:               resq 1    ; the one shown, 0 to WORKSPACES - 1
endstruc

; One raw input event, as a source hands it to input_submit
struc RawInput
    .type:                    resd 1    ; INPUT_* in inc/event.inc
    .code:                    resd 1
    .value:                   resd 1
    .device:                  resd 1
    .time:                    resq 1    ; monotonic ns; 0: stamped on arrival
endstruc

%define INPUT_QUEUE_LEN       256       ; a power of two

; A seat: one pointer and one keyboard, their focus, and the queue of raw
; events waiting for the next turn (src/input/input.asm)
struc InputSeat
    .server:                  resq 1
    .pointer_focus:           resq 1    ; Surface* under the pointer, 0: none
    .keyboard_focus:          resq 1    ; Surface*, 0: none
    .time:                    resq 1    ; of the event being delivered
    .repeat_next:             resq 1    ; when the held key repeats next, ns
    .repeat_delay:            resq 1    ; from a press to its first repeat, ns
    .repeat_interval:         resq 1    ; between repeats, ns; 0: no repeat
    .repeat_key:              resd 1    ; the key repeating, 0: none
    .moving:                  resq 1    ; Surface* an Alt+drag holds, 0: none
    .move_dx:                 resd 1    ; moving: the pointer's place on it;
    .move_dy:                 resd 1    ; resizing: where the pointer started
    .move_mode:               resd 1    ; MOVE_MOVE or MOVE_RESIZE
    .bar:                     resq 1    ; Surface* whose title bar the pointer is on
    .bar_part:                resd 1    ; which part: TITLEBAR_*
    .bar_pad:                 resd 1
    .resize_w:                resd 1    ; its size when the resize started
    .resize_h:                resd 1
    .move_pad:                resd 1
    .x:                       resd 1    ; pointer, output pixels
    .y:                       resd 1
    .buttons:                 resd 1    ; held buttons, bit n = button n
    .head:                    resd 1    ; next event to deliver
    .tail:                    resd 1    ; next free slot
    .dropped:                 resd 1    ; events lost to a full queue
    .mods:                    resd 1    ; held modifiers, MOD_* in inc/input.inc
    .locks:                   resd 1    ; MOD_CAPS, MOD_NUM
    .keys:                    resb 32   ; held keycodes 0-255, a bit each
    .queue:                   resb INPUT_QUEUE_LEN * RawInput_size
endstruc

struc Session
    .id:                      resq 1
    .user:                    resq 1
    .state:                   resq 1
    .lock_screen:             resq 1
    .kiosk_session:           resq 1
    .seat:                    resq 1
endstruc

struc Shell
    .server:                  resq 1
    .seat:                    resq 1
    .arena:                   resq 1
    .toplevels:               resq 1
    .popups:                  resq 1
    .layers:                  resq 1
    .workspaces:              resq 1
    .active_ws:               resq 1
    .workspace_count:         resq 1
    .configure_list:          resq 1
    .configure_count:         resq 1
    .policy:                  resq 1
    .theme:                   resq 1
    .outputs:                 resq 1
endstruc

struc Shortcut
    .keysym:                  resd 1
    .modifiers:               resd 1
    .action:                  resd 1
    .action_data:             resq 1
    .client:                  resq 1
    .next:                    resq 1
endstruc

; One side of a surface's double-buffered state; embedded twice in Surface.
struc SurfaceState
    .buffer:                  resq 1    ; buffer handle, 0: none
    .buf_x:                   resd 1
    .buf_y:                   resd 1
    .damage:                  resq 1
    .opaque:                  resq 1
    .input:                   resq 1
    .scale:                   resq 1
    .subsurfaces:             resq 1
    .frame_cbs:               resq 1
    .transform:               resd 1
    .pending:                 resd 1
    .width:                   resd 1
    .height:                  resd 1
    .stride:                  resd 1
    resd 1
endstruc

struc Surface
    .id:                      resq 1
    .role:                    resq 1
    .role_data:               resq 1
    .output:                  resq 1
    .z_order:                 resq 1
    .client:                  resq 1
    .client_next:             resq 1    ; the client's surfaces
    .z_order_next:            resq 1
    .z_order_prev:            resq 1
    .frame_seq:               resq 1
    .buffer:                  resq 1
    .damage:                  resq 1
    .format:                  resq 1
    .width:                   resq 1
    .height:                  resq 1
    .stride:                  resq 1
    .subsurfaces:             resq 1
    .cb_free:                 resq 1    ; spent frame callback nodes
    .current:                 resb SurfaceState_size
    .pending:                 resb SurfaceState_size
    .window:                  resq 1    ; Window* when it is a toplevel, else 0
    .fence_wait:              resq 1    ; 1: a commit waits for an acquire fence
    .cursor_shape:            resq 1    ; cw_pointer.shape while the pointer is over it
endstruc

; A surface with a shell role (src/shell/window.asm): a toplevel window,
; a popup or a layer
%define WINDOW_NAME_MAX 63              ; bytes of a title or app id
%define ROLE_TOPLEVEL   0
%define ROLE_POPUP      1
%define ROLE_LAYER      2

; Stacking levels, bottom to top; a surface with no role is at LEVEL_NORMAL
%define LEVEL_BACKGROUND    -2
%define LEVEL_BOTTOM        -1
%define LEVEL_NORMAL        0
%define LEVEL_TOP           1
%define LEVEL_FULLSCREEN    2           ; a fullscreen window, over panels
%define LEVEL_POPUP         3
%define LEVEL_OVERLAY       4

; A window's states (Window.state; configure's states)
%define WINDOW_MAXIMIZED    1
%define WINDOW_FULLSCREEN   2
%define WINDOW_MINIMIZED    4           ; not told to the client

; What an Alt+drag does (InputSeat.move_mode)
%define MOVE_MOVE       1
%define MOVE_RESIZE     2
%define RESIZE_MIN      16              ; the smallest a resize asks for
%define WINDOW_LIST_MAX 8               ; clients watching the window list
%define WORKSPACES      4               ; Super+1 to Super+4

; Server-drawn title bars (src/shell/titlebar.asm)
%define TITLEBAR_H      24              ; above the window, its width
%define TITLEBAR_BUTTON 16              ; a square button
%define TITLEBAR_MARGIN 4               ; buttons from the edges and each other
%define TITLEBAR_BAR    1               ; the parts of a bar
%define TITLEBAR_CLOSE  2
%define TITLEBAR_MAXIMIZE 3
%define TITLEBAR_MINIMIZE 4

; Layer anchors (proto/canvas-shell.cwp)
%define ANCHOR_TOP      1
%define ANCHOR_BOTTOM   2
%define ANCHOR_LEFT     4
%define ANCHOR_RIGHT    8

struc Window
    .server:                  resq 1
    .surface:                 resq 1
    .next:                    resq 1    ; Server.windows (toplevels), newest first
    .parent:                  resq 1    ; a popup's parent Surface*
    .kind:                    resd 1    ; ROLE_*
    .level:                   resd 1    ; LEVEL_*
    .anchor:                  resd 1    ; a layer's ANCHOR_* bits
    .margin:                  resd 1    ; a layer's distance from its edges
    .offset_x:                resd 1    ; a popup's place on its parent
    .offset_y:                resd 1
    .x:                       resd 1    ; where the server put it
    .y:                       resd 1
    .placed:                  resd 1    ; 1 once it has shown a buffer
    .state:                   resd 1    ; WINDOW_* bits
    .saved_x:                 resd 1    ; its place and size before it was
    .saved_y:                 resd 1    ; maximized or made fullscreen
    .saved_w:                 resd 1
    .saved_h:                 resd 1
    .number:                  resd 1    ; a toplevel's id in the window list
    .exclusive:               resd 1    ; a layer's strip kept from windows
    .min_output:              resq 1    ; the Output* it is off, while hidden
    .workspace:               resd 1    ; a toplevel's, 0 to WORKSPACES - 1
    .decorated:               resd 1    ; 1: the server draws its title bar
    .bar_w:                   resd 1    ; the width its bar was drawn at
    .focus_seq:               resd 1    ; when it last got the keyboard
    .serial:                  resd 1    ; of the last configure sent
    .acked:                   resd 1    ; the last the client applied
    .title_len:               resd 1
    .app_id_len:              resd 1
    .pad:                     resd 1
    .title:                   resb 64   ; WINDOW_NAME_MAX + 1
    .app_id:                  resb 64
endstruc

struc Tablet
    resb 64
    .tool_type:               resd 1
    .tool_id:                 resd 1
    .x:                       resd 1
    .y:                       resd 1
    .pressure:                resd 1
    .distance:                resd 1
    .tilt_x:                  resd 1
    .tilt_y:                  resd 1
    .rotation:                resd 1
    .slider:                  resd 1
    .wheel:                   resd 1
    .buttons:                 resd 1
    .proximity:               resb 1
    .tip_state:               resb 3
    .prox_distance:           resq 1
    resb 4
endstruc

struc TextInput
    .seat:                    resq 1
    .surface:                 resq 1
    .content_type:            resd 1
    .content_hint:            resq 1
    resb 4
    .cursor:                  resd 1
    .anchor:                  resd 1
    .preedit:                 resq 1
    .content_purpose:         resq 1
    .preedit_start:           resd 1
    .preedit_end:             resd 1
    .commit_text:             resq 1
    .delete_surrounding_text: resq 1
    .keysym:                  resd 1
    .state:                   resd 1
    .next:                    resq 1
    .surrounding_text:        resq 1
endstruc

struc Theme
    .name:                    resq 1
    .colors:                  resq 1
    .font:                    resq 1
    .font_size:               resd 1
    .border_width:            resd 1
    .border_radius:           resd 1
    .titlebar_height:         resd 1
    .button_size:             resd 1
    .padding:                 resd 1
    resb 8
endstruc

struc ThemeColors
    .background:              resq 1
    .accent:                  resq 1
    .titlebar_bg:             resq 1
    .button_bg:               resq 1
    .button_hover_bg:         resq 1
    .button_pressed_bg:       resq 1
    .border:                  resq 1
    .button_fg:               resq 1
    .button_hover_fg:         resq 1
    .button_pressed_fg:       resq 1
    .foreground:              resq 1
    .titlebar_fg:             resq 1
endstruc

struc TileDiff
    .tile_w:                  resd 1
    .tile_h:                  resd 1
    .cols:                    resd 1
    .rows:                    resd 1
    .prev_crc:                resq 1
    .dirty:                   resq 1
    .dirty_count:             resq 1
    .arena:                   resq 1
endstruc

struc Token
    .value:                   resq 1
    .type:                    resd 1
    .capabilities:            resq 1
    .expires:                 resq 1
    .issued_to:               resq 1
    .issued_by:               resq 1
    .issued_at:               resq 1
    resb 4
endstruc

struc Toplevel
    .surface:                 resq 1
    .shell:                   resq 1
    .title:                   resq 1
    .app_id:                  resq 1
    .state:                   resd 1
    .pending_state:           resd 1
    .configure_serial:        resd 1
    .capabilities:            resd 1
    .pending_width:           resd 1
    .pending_height:          resq 1
    .pending_x:               resd 1
    .pending_y:               resd 1
    .width:                   resd 1
    .height:                  resd 1
    .x:                       resd 1
    .y:                       resd 1
    .saved_width:             resd 1
    .saved_height:            resd 1
    .saved_x:                 resd 1
    .saved_y:                 resd 1
    .decoration:              resq 1
    .layer:                   resq 1
    .workspace:               resq 1
    .output:                  resq 1
    .seat:                    resq 1
    .next_ws:                 resq 1
    .prev_ws:                 resq 1
    .layout_node:             resq 1
    resb 4
    .decorations:             resq 1
    .frame_cb:                resq 1
endstruc

struc Touch
    resb 64
    .slots:                   resq 1
    .num_slots:               resd 1
    .max_slots:               resd 1
    .active_slots:            resq 1
    .surface:                 resq 1
endstruc

struc TouchSlot
    .tracking_id:             resd 1
    .x:                       resd 1
    .y:                       resd 1
    .active:                  resq 1
    resb 4
endstruc

struc Trace
    .server:                  resq 1
    .buffer:                  resq 1
    .capacity:                resq 1
    .head:                    resq 1
    .count:                   resq 1
    .event_size:              resq 1
    .arena:                   resq 1
    .buf:                     resq 1
    .enabled_mask:            resq 1
    .dropped:                 resq 1
endstruc

struc TraceEvent
    .time_ns:                 resq 1
    .type:                    resd 1
    .event_id:                resq 1
    .client_id:               resq 1
    .object:                  resq 1
    .opcode:                  resd 1
    .flags:                   resq 1
    .arg0:                    resq 1
    .arg1:                    resq 1
    .arg2:                    resq 1
    .arg3:                    resq 1
endstruc

struc Transfer
    .next:                    resq 1
    .source_client:           resq 1
    .target_client:           resq 1
    .mime_type:               resq 1
    .mime_type_len:           resq 1
    .total_size:              resq 1
    .transferred:             resq 1
    .chunk_size:              resq 1
    .buffer:                  resq 1
    .buffer_size:             resq 1
    .status:                  resd 1
    .source_fd:               resq 1
    .target_fd:               resq 1
    .callback:                resq 1
    .user_data:               resq 1
    .serial:                  resq 1
endstruc

struc TrustProfile
    .name:                    resq 1
    .caps:                    resq 1
    .quota_mem:               resq 1
    .quota_surfs:             resd 1
    .quota_buffers:           resd 1
    .rate_msg_sec:            resq 1
    .rate_bytes_sec:          resq 1
    .prompts:                 resd 1
    .flags:                   resd 1
    .next:                    resq 1
endstruc

struc UserSession
    .session_id:              resq 1
    .user_id:                 resq 1
    .seat:                    resq 1
    .start_time:              resq 1
    .last_activity:           resq 1
    .state:                   resd 1
    .autostart_apps:          resq 1
    .env_vars:                resq 1
    .cwd:                     resq 1
    .next:                    resq 1
endstruc

struc VirtualOutput
    .server:                  resq 1
    .conn:                    resq 1
    .seq:                     resq 1
    .width:                   resd 1
    .height:                  resd 1
    .format:                  resd 1
    .damage:                  resd 1
    .fb:                      resq 1
    .output:                  resq 1
    .tilediff:                resq 1
endstruc

struc WaitQueue
    .next:                    resq 1
    .thread:                  resq 1
    .value:                   resq 1
endstruc

struc Workspace
    .id:                      resq 1
    .shell:                   resq 1
    .toplevels:               resq 1
    .state:                   resd 1
    .layout_engine:           resq 1
    .name:                    resq 1
    .next:                    resq 1
    .next_ws:                 resq 1
    resb 4
    .idx:                     resq 1
    .layout:                  resq 1
    .output:                  resq 1
endstruc

%endif ; __STRUCT_OFFSETS_INC__
