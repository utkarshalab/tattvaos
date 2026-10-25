; ============================================================================
; Common Struct Offsets — Seat, Pointer, Focus, Surface, Buffer, etc.
; Defines both dot and underscore notation for compatibility
; ============================================================================

%ifndef __STRUCT_OFFSETS_INC__
%define __STRUCT_OFFSETS_INC__

%macro DEFINE_STRUCT_OFFSET 3
%define %1.%2 %3
%define %1_%2 %3
%endmacro

; Seat
DEFINE_STRUCT_OFFSET Seat, id, 0
DEFINE_STRUCT_OFFSET Seat, capabilities, 8
DEFINE_STRUCT_OFFSET Seat, pointer, 16
DEFINE_STRUCT_OFFSET Seat, keyboard, 24
DEFINE_STRUCT_OFFSET Seat, touch, 32
DEFINE_STRUCT_OFFSET Seat, name, 40
DEFINE_STRUCT_OFFSET Seat, tablet, 48
DEFINE_STRUCT_OFFSET Seat, focus, 56
DEFINE_STRUCT_OFFSET Seat, grab, 64
DEFINE_STRUCT_OFFSET Seat, keymap, 72
DEFINE_STRUCT_OFFSET Seat, repeat, 80
DEFINE_STRUCT_OFFSET Seat, pointer_accel, 88
DEFINE_STRUCT_OFFSET Seat, constraints, 96
DEFINE_STRUCT_OFFSET Seat, cursor, 104
DEFINE_STRUCT_OFFSET Seat, devices, 112
DEFINE_STRUCT_OFFSET Seat, next, 120
DEFINE_STRUCT_OFFSET Seat, session, 128
DEFINE_STRUCT_OFFSET Seat, session_session, 136
DEFINE_STRUCT_OFFSET Seat, shell, 144
DEFINE_STRUCT_OFFSET Seat, ime_bridge, 152
DEFINE_STRUCT_OFFSET Seat, ime_arena, 160
DEFINE_STRUCT_OFFSET Seat, arena, 168
DEFINE_STRUCT_OFFSET Seat, pointer_focus, 176
DEFINE_STRUCT_OFFSET Seat, keyboard_focus, 184
DEFINE_STRUCT_OFFSET Seat, selection_source, 192
DEFINE_STRUCT_OFFSET Seat, selection_serial, 200
DEFINE_STRUCT_OFFSET Seat, drag_source, 208
DEFINE_STRUCT_OFFSET Seat, drag_icon, 216
DEFINE_STRUCT_OFFSET Seat, drag_actions, 224
%define Seat_SIZE 232
%define Seat.size 232
%define Seat_size 232

; All-caps aliases for Seat
%define SEAT_FOCUS 56

; Pointer
DEFINE_STRUCT_OFFSET Pointer, x, 0
DEFINE_STRUCT_OFFSET Pointer, y, 8
DEFINE_STRUCT_OFFSET Pointer, serial, 16
DEFINE_STRUCT_OFFSET Pointer, seat, 24
%define Pointer_SIZE 32
%define Pointer.size 32

; Focus
DEFINE_STRUCT_OFFSET Focus, surface, 0
DEFINE_STRUCT_OFFSET Focus, serial, 8
DEFINE_STRUCT_OFFSET Focus, seat, 16
%define Focus_SIZE 24
%define Focus.size 24

; Surface
DEFINE_STRUCT_OFFSET Surface, current, 0
DEFINE_STRUCT_OFFSET Surface, pending, 8
DEFINE_STRUCT_OFFSET Surface, width, 16
DEFINE_STRUCT_OFFSET Surface, height, 24
DEFINE_STRUCT_OFFSET Surface, format, 32
DEFINE_STRUCT_OFFSET Surface, buffer, 40
DEFINE_STRUCT_OFFSET Surface, damage, 48
DEFINE_STRUCT_OFFSET Surface, stride, 56
DEFINE_STRUCT_OFFSET Surface, z_order_next, 64
DEFINE_STRUCT_OFFSET Surface, z_order_prev, 72
DEFINE_STRUCT_OFFSET Surface, client, 80
DEFINE_STRUCT_OFFSET Surface, frame_seq, 88
DEFINE_STRUCT_OFFSET Surface, id, 92
DEFINE_STRUCT_OFFSET Surface, current, 96
DEFINE_STRUCT_OFFSET Surface, pending, 104
DEFINE_STRUCT_OFFSET Surface, z_order, 112
DEFINE_STRUCT_OFFSET Surface, role_data, 116
DEFINE_STRUCT_OFFSET Surface, role, 120
DEFINE_STRUCT_OFFSET Surface, subsurfaces, 128
%define Surface_SIZE 136
%define Surface.size 80
%define Surface_size 80

; SurfaceState
DEFINE_STRUCT_OFFSET SurfaceState, buffer, 0
DEFINE_STRUCT_OFFSET SurfaceState, damage, 8
DEFINE_STRUCT_OFFSET SurfaceState, pending, 16
DEFINE_STRUCT_OFFSET SurfaceState, buf_x, 24
DEFINE_STRUCT_OFFSET SurfaceState, buf_y, 32
DEFINE_STRUCT_OFFSET SurfaceState, input, 36
DEFINE_STRUCT_OFFSET SurfaceState, opaque, 44
DEFINE_STRUCT_OFFSET SurfaceState, width, 48
DEFINE_STRUCT_OFFSET SurfaceState, height, 56
DEFINE_STRUCT_OFFSET SurfaceState, transform, 64
DEFINE_STRUCT_OFFSET SurfaceState, scale, 72
DEFINE_STRUCT_OFFSET SurfaceState, frame_cbs, 80
DEFINE_STRUCT_OFFSET SurfaceState, subsurfaces, 88
DEFINE_STRUCT_OFFSET SurfaceState, stride, 96
%define SurfaceState_SIZE 104
%define SurfaceState.size 64
%define SurfaceState_size 64

; Buffer
DEFINE_STRUCT_OFFSET Buffer, base, 0
DEFINE_STRUCT_OFFSET Buffer, size, 8
DEFINE_STRUCT_OFFSET Buffer, format, 16
DEFINE_STRUCT_OFFSET Buffer, width, 24
DEFINE_STRUCT_OFFSET Buffer, height, 32
DEFINE_STRUCT_OFFSET Buffer, stride, 40
DEFINE_STRUCT_OFFSET Buffer, state, 48
DEFINE_STRUCT_OFFSET Buffer, client_id, 56
DEFINE_STRUCT_OFFSET Buffer, gpu_bo, 64
%define Buffer_SIZE 72
%define Buffer.size 72

; Client
DEFINE_STRUCT_OFFSET Client, id, 0
DEFINE_STRUCT_OFFSET Client, caps, 8
DEFINE_STRUCT_OFFSET Client, trust_profile, 16
DEFINE_STRUCT_OFFSET Client, obj_table, 24
DEFINE_STRUCT_OFFSET Client, quota, 24
DEFINE_STRUCT_OFFSET Client, ratelimit, 32
DEFINE_STRUCT_OFFSET Client, obj_table, 40
DEFINE_STRUCT_OFFSET Client, last_ping, 48
DEFINE_STRUCT_OFFSET Client, ping_serial, 56
DEFINE_STRUCT_OFFSET Client, verified, 64
DEFINE_STRUCT_OFFSET Client, rx_ring, 72
DEFINE_STRUCT_OFFSET Client, next_obj, 80
DEFINE_STRUCT_OFFSET Client, last_ping, 88
%define Client_SIZE 96
%define Client.size 96
%define Client_size 96

; ClientConn
DEFINE_STRUCT_OFFSET ClientConn, server_chan, 0
DEFINE_STRUCT_OFFSET ClientConn, tx_ring, 8
DEFINE_STRUCT_OFFSET ClientConn, rx_ring, 16
DEFINE_STRUCT_OFFSET ClientConn, handle_tx, 24
DEFINE_STRUCT_OFFSET ClientConn, handle_rx, 32
DEFINE_STRUCT_OFFSET ClientConn, caps_wanted, 40
DEFINE_STRUCT_OFFSET ClientConn, caps_granted, 48
DEFINE_STRUCT_OFFSET ClientConn, next_obj, 56
DEFINE_STRUCT_OFFSET ClientConn, arena, 64
%define ClientConn_SIZE 72
%define ClientConn.size 72
%define ClientConn_size 72

; Output
DEFINE_STRUCT_OFFSET Output, id, 0
DEFINE_STRUCT_OFFSET Output, name, 8
DEFINE_STRUCT_OFFSET Output, backend, 16
DEFINE_STRUCT_OFFSET Output, framebuffer, 24
DEFINE_STRUCT_OFFSET Output, scale, 32
DEFINE_STRUCT_OFFSET Output, rotation, 40
DEFINE_STRUCT_OFFSET Output, icc_profile, 48
DEFINE_STRUCT_OFFSET Output, vrr_enabled, 56
DEFINE_STRUCT_OFFSET Output, vrr_flags, 64
DEFINE_STRUCT_OFFSET Output, vrr_caps, 72
DEFINE_STRUCT_OFFSET Output, vrr_min_refresh, 80
DEFINE_STRUCT_OFFSET Output, vrr_max_refresh, 88
DEFINE_STRUCT_OFFSET Output, modes, 96
DEFINE_STRUCT_OFFSET Output, position, 104
DEFINE_STRUCT_OFFSET Output, damage, 112
DEFINE_STRUCT_OFFSET Output, x, 88
DEFINE_STRUCT_OFFSET Output, y, 96
DEFINE_STRUCT_OFFSET Output, width, 104
DEFINE_STRUCT_OFFSET Output, height, 112
DEFINE_STRUCT_OFFSET Output, connected, 120
DEFINE_STRUCT_OFFSET Output, controller, 128
DEFINE_STRUCT_OFFSET Output, crtc_index, 136
DEFINE_STRUCT_OFFSET Output, edid, 144
DEFINE_STRUCT_OFFSET Output, hpd_irq, 152
DEFINE_STRUCT_OFFSET Output, hpd_register, 160
DEFINE_STRUCT_OFFSET Output, i2c_bus, 168
DEFINE_STRUCT_OFFSET Output, current_surface, 176
DEFINE_STRUCT_OFFSET Output, current_mode, 184
DEFINE_STRUCT_OFFSET Output, surfaces, 192
DEFINE_STRUCT_OFFSET Output, toplevels, 200
DEFINE_STRUCT_OFFSET Output, hotplug_callback, 208
DEFINE_STRUCT_OFFSET Output, next, 216
DEFINE_STRUCT_OFFSET Output, stride, 224
DEFINE_STRUCT_OFFSET Output, frame_clock, 232
DEFINE_STRUCT_OFFSET Output, dpms_state, 240
DEFINE_STRUCT_OFFSET Output, dpms_timeout, 241
DEFINE_STRUCT_OFFSET Output, gamma_lut, 248
DEFINE_STRUCT_OFFSET Output, controller_ptr, 256
%define Output_SIZE 264
%define Output.size 264
%define Output_size 264INE_STRUCT_OFFSET Output, dpms_state, 152
DEFINE_STRUCT_OFFSET Output, dpms_timeout, 153
DEFINE_STRUCT_OFFSET Output, gamma_lut, 160
DEFINE_STRUCT_OFFSET Output, controller_ptr, 168
%define Output_SIZE 176
%define Output.size 176
%define Output_size 176

; Controller
DEFINE_STRUCT_OFFSET Controller, state, 0
DEFINE_STRUCT_OFFSET Controller, mmio_base, 8
DEFINE_STRUCT_OFFSET Controller, outputs, 16
DEFINE_STRUCT_OFFSET Controller, irq, 24
%define Controller_SIZE 32
%define Controller.size 32

; Backend
DEFINE_STRUCT_OFFSET Backend, state, 0
DEFINE_STRUCT_OFFSET Backend, server, 8
DEFINE_STRUCT_OFFSET Backend, capabilities, 16
DEFINE_STRUCT_OFFSET Backend, config, 24
DEFINE_STRUCT_OFFSET Backend, fb_base, 32
DEFINE_STRUCT_OFFSET Backend, fb_size, 40
DEFINE_STRUCT_OFFSET Backend, arena, 48
DEFINE_STRUCT_OFFSET Backend, outputs, 56
DEFINE_STRUCT_OFFSET Backend, output_count, 64
DEFINE_STRUCT_OFFSET Backend, layout_bounds, 72
DEFINE_STRUCT_OFFSET Backend, frame_clock, 80
DEFINE_STRUCT_OFFSET Backend, cursor_x, 88
DEFINE_STRUCT_OFFSET Backend, cursor_y, 96
%define Backend_SIZE 104
%define Backend.size 104

; Mode (extended)
DEFINE_STRUCT_OFFSET Mode, hactive, 0
DEFINE_STRUCT_OFFSET Mode, vactive, 8
DEFINE_STRUCT_OFFSET Mode, hblank, 16
DEFINE_STRUCT_OFFSET Mode, vblank, 24
DEFINE_STRUCT_OFFSET Mode, hsync_offset, 32
DEFINE_STRUCT_OFFSET Mode, hsync_width, 40
DEFINE_STRUCT_OFFSET Mode, vsync_offset, 48
DEFINE_STRUCT_OFFSET Mode, vsync_width, 56
DEFINE_STRUCT_OFFSET Mode, hborder, 64
DEFINE_STRUCT_OFFSET Mode, vborder, 72
DEFINE_STRUCT_OFFSET Mode, pixel_clock, 80
DEFINE_STRUCT_OFFSET Mode, refresh_ns, 88
DEFINE_STRUCT_OFFSET Mode, flags, 968
DEFINE_STRUCT_OFFSET Mode, width_mm, 128
DEFINE_STRUCT_OFFSET Mode, height_mm, 136
%define Mode_SIZE 144

; Mode (basic)
DEFINE_STRUCT_OFFSET Mode, width, 0
DEFINE_STRUCT_OFFSET Mode, height, 8
DEFINE_STRUCT_OFFSET Mode, htotal, 16
DEFINE_STRUCT_OFFSET Mode, hsync_start, 24
DEFINE_STRUCT_OFFSET Mode, hsync_end, 32
DEFINE_STRUCT_OFFSET Mode, hblank, 40
DEFINE_STRUCT_OFFSET Mode, vtotal, 48
DEFINE_STRUCT_OFFSET Mode, vsync_start, 56
DEFINE_STRUCT_OFFSET Mode, vsync_end, 64
DEFINE_STRUCT_OFFSET Mode, vblank, 72
DEFINE_STRUCT_OFFSET Mode, pixel_clock, 80
DEFINE_STRUCT_OFFSET Mode, flags, 88
DEFINE_STRUCT_OFFSET Mode, hsync_width, 96
DEFINE_STRUCT_OFFSET Mode, vsync_width, 104
DEFINE_STRUCT_OFFSET Mode, hborder, 112
DEFINE_STRUCT_OFFSET Mode, vborder, 120
DEFINE_STRUCT_OFFSET Mode, width_mm, 128
DEFINE_STRUCT_OFFSET Mode, height_mm, 136
%define Mode_SIZE 144

; Mode flags
%define MODE_FLAG_HSYNC_POSITIVE   (1 << 0)
%define MODE_FLAG_VSYNC_POSITIVE   (1 << 1)
%define MODE_FLAG_INTERLACED       (1 << 2)
%define MODE_FLAG_DBLSCAN          (1 << 3)
%define MODE_FLAG_CSYNC            (1 << 4)
%define MODE_FLAG_PCSYNC           (1 << 5)

; Config
DEFINE_STRUCT_OFFSET Config, fb_base, 0
DEFINE_STRUCT_OFFSET Config, fb_size, 8
DEFINE_STRUCT_OFFSET Config, mode, 16
DEFINE_STRUCT_OFFSET Config, fb_format, 24
DEFINE_STRUCT_OFFSET Config, flags, 32
%define Config_SIZE 40

; FrameClock
DEFINE_STRUCT_OFFSET FrameClock, callbacks, 0
DEFINE_STRUCT_OFFSET FrameClock, next_vblank, 8
DEFINE_STRUCT_OFFSET FrameClock, refresh_ns, 16
%define FrameClock_SIZE 24
%define FrameClock.size 24
%define FrameClock_size 24

%define FrameClock_next_vblank 8
%define FrameClock_refresh_ns 16
%define FrameClock_callbacks 0

; List
DEFINE_STRUCT_OFFSET List, head, 0
%define List_SIZE 8
%define List.size 8

; ListNode
DEFINE_STRUCT_OFFSET ListNode, next, 0
%define ListNode_SIZE 8
%define ListNode_size 8

; Arena
DEFINE_STRUCT_OFFSET Arena, base, 0
DEFINE_STRUCT_OFFSET Arena, cursor, 8
DEFINE_STRUCT_OFFSET Arena, limit, 16
DEFINE_STRUCT_OFFSET Arena, parent, 24
%define Arena_SIZE 32
%define Arena.size 32
%define Arena_size 32

; Server
DEFINE_STRUCT_OFFSET Server, arena, 0
DEFINE_STRUCT_OFFSET Server, backend, 8
DEFINE_STRUCT_OFFSET Server, clipboard, 16
DEFINE_STRUCT_OFFSET Server, primary_selection, 24
DEFINE_STRUCT_OFFSET Server, dnd, 32
DEFINE_STRUCT_OFFSET Server, seat, 40
DEFINE_STRUCT_OFFSET Server, outputs, 48
DEFINE_STRUCT_OFFSET Server, clients, 56
DEFINE_STRUCT_OFFSET Server, outputs, 56
DEFINE_STRUCT_OFFSET Server, accounting, 64
DEFINE_STRUCT_OFFSET Server, containment, 72
DEFINE_STRUCT_OFFSET Server, quotas, 80
DEFINE_STRUCT_OFFSET Server, ratelimits, 88
DEFINE_STRUCT_OFFSET Server, scheduler, 96
DEFINE_STRUCT_OFFSET Server, watchdog, 104
DEFINE_STRUCT_OFFSET Server, client_registry, 112
DEFINE_STRUCT_OFFSET Server, gpu, 120
DEFINE_STRUCT_OFFSET Server, cursors, 128
DEFINE_STRUCT_OFFSET Server, cursor_theme, 136
DEFINE_STRUCT_OFFSET Server, focus, 144
DEFINE_STRUCT_OFFSET Server, grabs, 152
DEFINE_STRUCT_OFFSET Server, grab_count, 160
DEFINE_STRUCT_OFFSET Server, surfaces, 168
DEFINE_STRUCT_OFFSET Server, z_order_tree, 176
DEFINE_STRUCT_OFFSET Server, input_sources, 184
DEFINE_STRUCT_OFFSET Server, seats, 192
DEFINE_STRUCT_OFFSET Server, seat_count, 200
DEFINE_STRUCT_OFFSET Server, default_seat, 208
DEFINE_STRUCT_OFFSET Server, debug, 216
DEFINE_STRUCT_OFFSET Server, faultdump, 224
DEFINE_STRUCT_OFFSET Server, metrics, 232
DEFINE_STRUCT_OFFSET Server, protolog, 240
DEFINE_STRUCT_OFFSET Server, recorder, 248
DEFINE_STRUCT_OFFSET Server, replayer, 256
DEFINE_STRUCT_OFFSET Server, client_stats, 264
DEFINE_STRUCT_OFFSET Server, layout_bounds, 272
DEFINE_STRUCT_OFFSET Server, policy, 280
DEFINE_STRUCT_OFFSET Server, crp, 288
DEFINE_STRUCT_OFFSET Server, rfb, 296
DEFINE_STRUCT_OFFSET Server, gpu_renderer, 304
DEFINE_STRUCT_OFFSET Server, cap_table, 312
DEFINE_STRUCT_OFFSET Server, gate, 320
DEFINE_STRUCT_OFFSET Server, isolation, 328
DEFINE_STRUCT_OFFSET Server, audit_log, 336
DEFINE_STRUCT_OFFSET Server, verifier, 344
DEFINE_STRUCT_OFFSET Server, prompts, 352
DEFINE_STRUCT_OFFSET Server, prompt_count, 360
DEFINE_STRUCT_OFFSET Server, trust_profiles, 368
DEFINE_STRUCT_OFFSET Server, buffer_table, 376
DEFINE_STRUCT_OFFSET Server, buffer_pool, 384
DEFINE_STRUCT_OFFSET Server, token_key, 392
DEFINE_STRUCT_OFFSET Server, damage_region, 400
DEFINE_STRUCT_OFFSET Server, fence_table, 408
DEFINE_STRUCT_OFFSET Server, region_table, 416
DEFINE_STRUCT_OFFSET Server, surface_table, 424
DEFINE_STRUCT_OFFSET Server, timeline_table, 432
DEFINE_STRUCT_OFFSET Server, idle_manager, 440
DEFINE_STRUCT_OFFSET Server, kiosk_sessions, 448
DEFINE_STRUCT_OFFSET Server, lock_screens, 456
DEFINE_STRUCT_OFFSET Server, power_manager, 464
DEFINE_STRUCT_OFFSET Server, multiseat, 472
DEFINE_STRUCT_OFFSET Server, configure_serial, 480
DEFINE_STRUCT_OFFSET Server, configure_list, 488
DEFINE_STRUCT_OFFSET Server, user_sessions, 496
DEFINE_STRUCT_OFFSET Server, session_count, 504
DEFINE_STRUCT_OFFSET Server, next_session_id, 512
DEFINE_STRUCT_OFFSET Server, decoration_theme, 520
DEFINE_STRUCT_OFFSET Server, layers, 528
DEFINE_STRUCT_OFFSET Server, layer_count, 536
DEFINE_STRUCT_OFFSET Server, move_resize, 544
DEFINE_STRUCT_OFFSET Server, popups, 552
DEFINE_STRUCT_OFFSET Server, rules, 560
DEFINE_STRUCT_OFFSET Server, rules_count, 568
DEFINE_STRUCT_OFFSET Server, theme, 576
DEFINE_STRUCT_OFFSET Server, toplevels, 584
DEFINE_STRUCT_OFFSET Server, subsurface, 592
DEFINE_STRUCT_OFFSET Server, shortcuts, 600
DEFINE_STRUCT_OFFSET Server, text_inputs, 608
DEFINE_STRUCT_OFFSET Server, frame_timeline, 288
DEFINE_STRUCT_OFFSET Server, trace, 296
DEFINE_STRUCT_OFFSET Server, output_count, 304
DEFINE_STRUCT_OFFSET Server, buffer_table, 312
DEFINE_STRUCT_OFFSET Server, seat, 320
%define Server_SIZE 328
%define Server.size 328
%define Server_size 328

; All-caps aliases for Server
%define SERVER_OUTPUTS 56
%define SERVER_CLIENTS 56
%define SERVER_ACCOUNTING 64

; Clipboard
DEFINE_STRUCT_OFFSET Clipboard, seat, 0
DEFINE_STRUCT_OFFSET Clipboard, data, 8
DEFINE_STRUCT_OFFSET Clipboard, data_len, 16
DEFINE_STRUCT_OFFSET Clipboard, mime_type, 24
DEFINE_STRUCT_OFFSET Clipboard, mime_type_len, 32
DEFINE_STRUCT_OFFSET Clipboard, source_client, 40
DEFINE_STRUCT_OFFSET Clipboard, serial, 48
DEFINE_STRUCT_OFFSET Clipboard, selection_type, 56
DEFINE_STRUCT_OFFSET Clipboard, offered_mimes, 64
DEFINE_STRUCT_OFFSET Clipboard, offered_count, 72
%define Clipboard_SIZE 80
%define Clipboard.size 80
%define Clipboard_size 80

; All-caps aliases for Clipboard
%define CLIPBOARD_SEAT 0
%define CLIPBOARD_DATA 8
%define CLIPBOARD_DATA_LEN 16
%define CLIPBOARD_MIME_TYPE 24
%define CLIPBOARD_MIME_TYPE_LEN 32
%define CLIPBOARD_SOURCE_CLIENT 40
%define CLIPBOARD_SERIAL 48
%define CLIPBOARD_SELECTION_TYPE 56
%define CLIPBOARD_OFFERED_MIMES 64
%define CLIPBOARD_OFFERED_COUNT 72
%define CLIPBOARD_SEAT 0
%define CLIPBOARD_DATA 8
%define CLIPBOARD_DATA_LEN 16
%define CLIPBOARD_MIME_TYPE 24
%define CLIPBOARD_MIME_TYPE_LEN 32
%define CLIPBOARD_SOURCE_CLIENT 40
%define CLIPBOARD_SERIAL 48
%define CLIPBOARD_SELECTION_TYPE 56
%define CLIPBOARD_OFFERED_MIMES 64
%define CLIPBOARD_OFFERED_COUNT 72
%define CLIPBOARD_SEAT 0
%define CLIPBOARD_DATA 8
%define CLIPBOARD_DATA_LEN 16
%define CLIPBOARD_MIME_TYPE 24
%define CLIPBOARD_MIME_TYPE_LEN 32
%define CLIPBOARD_SOURCE_CLIENT 40
%define CLIPBOARD_SERIAL 48
%define CLIPBOARD_SELECTION_TYPE 56
%define CLIPBOARD_OFFERED_MIMES 64
%define CLIPBOARD_OFFERED_COUNT 72

; DnD
DEFINE_STRUCT_OFFSET DnD, seat, 0
DEFINE_STRUCT_OFFSET DnD, source_client, 8
DEFINE_STRUCT_OFFSET DnD, source_surface, 16
DEFINE_STRUCT_OFFSET DnD, target_client, 24
DEFINE_STRUCT_OFFSET DnD, target_surface, 32
DEFINE_STRUCT_OFFSET DnD, drag_icon, 40
DEFINE_STRUCT_OFFSET DnD, grab, 48
DEFINE_STRUCT_OFFSET DnD, offered_mimes, 56
DEFINE_STRUCT_OFFSET DnD, mime_count, 64
DEFINE_STRUCT_OFFSET DnD, selected_mime, 72
DEFINE_STRUCT_OFFSET DnD, selected_mime_len, 80
DEFINE_STRUCT_OFFSET DnD, action, 88
DEFINE_STRUCT_OFFSET DnD, actions, 92
DEFINE_STRUCT_OFFSET DnD, serial, 96
DEFINE_STRUCT_OFFSET DnD, state, 100
%define DnD_SIZE 104
%define DnD.size 104
%define DnD_size 104

; All-caps aliases for DnD
%define DND_SEAT 0
%define DND_SOURCE_CLIENT 8
%define DND_SOURCE_SURFACE 16
%define DND_TARGET_CLIENT 24
%define DND_TARGET_SURFACE 32
%define DND_DRAG_ICON 40
%define DND_GRAB 48
%define DND_OFFERED_MIMES 56
%define DND_MIME_COUNT 64
%define DND_SELECTED_MIME 72
%define DND_SELECTED_MIME_LEN 80
%define DND_ACTION 88
%define DND_ACTIONS 92
%define DND_SERIAL 96
%define DND_STATE 100

; Limits
DEFINE_STRUCT_OFFSET Limits, clipboard_max, 0
DEFINE_STRUCT_OFFSET Limits, selection_max, 8
DEFINE_STRUCT_OFFSET Limits, dnd_max, 16
DEFINE_STRUCT_OFFSET Limits, offer_mimes_max, 24
DEFINE_STRUCT_OFFSET Limits, rate_msg_per_sec, 32
DEFINE_STRUCT_OFFSET Limits, rate_bytes_per_sec, 40
DEFINE_STRUCT_OFFSET Limits, per_client_limits, 48
%define Limits_SIZE 56
%define Limits.size 56
%define Limits_size 56

; ClientLimits
DEFINE_STRUCT_OFFSET ClientLimits, clipboard_bytes, 0
DEFINE_STRUCT_OFFSET ClientLimits, selection_bytes, 8
DEFINE_STRUCT_OFFSET ClientLimits, dnd_bytes, 16
DEFINE_STRUCT_OFFSET ClientLimits, messages_sent, 24
DEFINE_STRUCT_OFFSET ClientLimits, bytes_sent, 32
DEFINE_STRUCT_OFFSET ClientLimits, last_reset, 40
%define ClientLimits_SIZE 48
%define ClientLimits.size 48
%define ClientLimits_size 48

; Transfer
DEFINE_STRUCT_OFFSET Transfer, next, 0
DEFINE_STRUCT_OFFSET Transfer, source_client, 8
DEFINE_STRUCT_OFFSET Transfer, target_client, 16
DEFINE_STRUCT_OFFSET Transfer, mime_type, 24
DEFINE_STRUCT_OFFSET Transfer, mime_type_len, 32
DEFINE_STRUCT_OFFSET Transfer, total_size, 40
DEFINE_STRUCT_OFFSET Transfer, transferred, 48
DEFINE_STRUCT_OFFSET Transfer, chunk_size, 56
DEFINE_STRUCT_OFFSET Transfer, buffer, 64
DEFINE_STRUCT_OFFSET Transfer, buffer_size, 72
DEFINE_STRUCT_OFFSET Transfer, status, 80
DEFINE_STRUCT_OFFSET Transfer, source_fd, 84
DEFINE_STRUCT_OFFSET Transfer, target_fd, 92
DEFINE_STRUCT_OFFSET Transfer, callback, 100
DEFINE_STRUCT_OFFSET Transfer, user_data, 108
DEFINE_STRUCT_OFFSET Transfer, serial, 116
%define Transfer_SIZE 124
%define Transfer.size 124
%define Transfer_size 124

; Server additional fields
DEFINE_STRUCT_OFFSET Server, transfers, 56
DEFINE_STRUCT_OFFSET Server, transfer_count, 64
%define Server_SIZE 72
%define Server.size 72
%define Server_size 72

; Region
DEFINE_STRUCT_OFFSET Region, rects, 0
DEFINE_STRUCT_OFFSET Region, count, 8
DEFINE_STRUCT_OFFSET Region, capacity, 16
DEFINE_STRUCT_OFFSET Region, arena, 24
%define Region_SIZE 32
%define Region.size 32
%define Region_size 32

; TrustProfile
DEFINE_STRUCT_OFFSET TrustProfile, quota_mem, 0
DEFINE_STRUCT_OFFSET TrustProfile, quota_surfs, 8
DEFINE_STRUCT_OFFSET TrustProfile, quota_buffers, 16
DEFINE_STRUCT_OFFSET TrustProfile, rate_msg_sec, 24
DEFINE_STRUCT_OFFSET TrustProfile, rate_bytes_sec, 32
%define TrustProfile_SIZE 40
%define TrustProfile.size 40
%define TrustProfile_size 40

; GpuDevice
DEFINE_STRUCT_OFFSET GpuDevice, server, 0
DEFINE_STRUCT_OFFSET GpuDevice, fence_mgr, 8
DEFINE_STRUCT_OFFSET GpuDevice, mem, 16
DEFINE_STRUCT_OFFSET GpuDevice, mem_mgr, 24
DEFINE_STRUCT_OFFSET GpuDevice, ring_gfx, 32
DEFINE_STRUCT_OFFSET GpuDevice, ring_compute, 40
DEFINE_STRUCT_OFFSET GpuDevice, ring_sdma, 48
DEFINE_STRUCT_OFFSET GpuDevice, mmio_base, 56
DEFINE_STRUCT_OFFSET GpuDevice, mmio_size, 64
DEFINE_STRUCT_OFFSET GpuDevice, family, 72
DEFINE_STRUCT_OFFSET GpuDevice, enabled, 73
%define GpuDevice_SIZE 80
%define GpuDevice.size 80
%define GpuDevice_size 80

; PixBuf — layout written by pixbuf_create (lib/ugfx/core/pixbuf.asm, see lib/ugfx/include/ugfx.inc). "size" is
; the pixel-data size field; PixBuf_SIZE is the whole object.
DEFINE_STRUCT_OFFSET PixBuf, width, 0
DEFINE_STRUCT_OFFSET PixBuf, height, 8
DEFINE_STRUCT_OFFSET PixBuf, stride, 16
DEFINE_STRUCT_OFFSET PixBuf, format, 24
DEFINE_STRUCT_OFFSET PixBuf, data, 32
DEFINE_STRUCT_OFFSET PixBuf, size, 40
DEFINE_STRUCT_OFFSET PixBuf, refcount, 48
DEFINE_STRUCT_OFFSET PixBuf, arena, 56
%define PixBuf_SIZE 64

; Pixbuf (lowercase alias)
DEFINE_STRUCT_OFFSET Pixbuf, width, 0
DEFINE_STRUCT_OFFSET Pixbuf, height, 8
DEFINE_STRUCT_OFFSET Pixbuf, format, 16
DEFINE_STRUCT_OFFSET Pixbuf, stride, 24
DEFINE_STRUCT_OFFSET Pixbuf, data, 32
DEFINE_STRUCT_OFFSET Pixbuf, size, 40
%define Pixbuf_SIZE 48
%define Pixbuf.size 48
%define Pixbuf_size 48

; HuffDec
DEFINE_STRUCT_OFFSET HuffDec, state, 0
DEFINE_STRUCT_OFFSET HuffDec, bitstate, 8
DEFINE_STRUCT_OFFSET HuffDec, literal_table, 16
DEFINE_STRUCT_OFFSET HuffDec, distance_table, 24
%define HuffDec_SIZE 32
%define HuffDec.size 32
%define HuffDec_size 32

; PngImage
DEFINE_STRUCT_OFFSET PngImage, width, 0
DEFINE_STRUCT_OFFSET PngImage, height, 4
DEFINE_STRUCT_OFFSET PngImage, bit_depth, 8
DEFINE_STRUCT_OFFSET PngImage, color_type, 9
DEFINE_STRUCT_OFFSET PngImage, channels, 10
DEFINE_STRUCT_OFFSET PngImage, compression, 11
DEFINE_STRUCT_OFFSET PngImage, filter, 12
DEFINE_STRUCT_OFFSET PngImage, interlace, 13
DEFINE_STRUCT_OFFSET PngImage, idat_buf, 16
DEFINE_STRUCT_OFFSET PngImage, idat_len, 24
DEFINE_STRUCT_OFFSET PngImage, idat_cap, 32
DEFINE_STRUCT_OFFSET PngImage, arena, 40
DEFINE_STRUCT_OFFSET PngImage, idat_buf_ptr, 48
DEFINE_STRUCT_OFFSET PngImage, pixbuf, 56
DEFINE_STRUCT_OFFSET PngImage, palette, 64
DEFINE_STRUCT_OFFSET PngImage, palette_entries, 72
DEFINE_STRUCT_OFFSET PngImage, transparency, 80
DEFINE_STRUCT_OFFSET PngImage, transparency_len, 88
%define PngImage_SIZE 96
%define PngImage.size 96
%define PngImage_size 96

; Rect
DEFINE_STRUCT_OFFSET Rect, x, 0
DEFINE_STRUCT_OFFSET Rect, y, 8
DEFINE_STRUCT_OFFSET Rect, width, 16
DEFINE_STRUCT_OFFSET Rect, height, 24
DEFINE_STRUCT_OFFSET Rect, x1, 32
DEFINE_STRUCT_OFFSET Rect, y1, 40
DEFINE_STRUCT_OFFSET Rect, x2, 48
DEFINE_STRUCT_OFFSET Rect, y2, 56
%define Rect_SIZE 64
%define Rect.size 64
%define Rect_size 64

; All-caps aliases for Rect
%define RECT_X 0
%define RECT_Y 8
%define RECT_WIDTH 16
%define RECT_HEIGHT 24
%define RECT_X1 32
%define RECT_Y1 40
%define RECT_X2 48
%define RECT_Y2 56
%define RECT_W 16
%define RECT_H 24

; Cursor
DEFINE_STRUCT_OFFSET Cursor, pixbuf, 0
DEFINE_STRUCT_OFFSET Cursor, hotspot_x, 8
DEFINE_STRUCT_OFFSET Cursor, hotspot_y, 16
DEFINE_STRUCT_OFFSET Cursor, delay, 24
DEFINE_STRUCT_OFFSET Cursor, next_frame, 32
DEFINE_STRUCT_OFFSET Cursor, current, 40
%define Cursor_SIZE 48
%define Cursor.size 48
%define Cursor_size 48

; Grab
DEFINE_STRUCT_OFFSET Grab, next, 0
DEFINE_STRUCT_OFFSET Grab, type, 8
DEFINE_STRUCT_OFFSET Grab, seat, 16
DEFINE_STRUCT_OFFSET Grab, owner, 24
DEFINE_STRUCT_OFFSET Grab, serial, 32
DEFINE_STRUCT_OFFSET Grab, cursor, 40
DEFINE_STRUCT_OFFSET Grab, surface, 48
DEFINE_STRUCT_OFFSET Grab, confine, 56
%define Grab_SIZE 64
%define Grab.size 64
%define Grab_size 64

; Keyboard
DEFINE_STRUCT_OFFSET Keyboard, keymap, 64
DEFINE_STRUCT_OFFSET Keyboard, modifiers, 72
DEFINE_STRUCT_OFFSET Keyboard, leds, 76
DEFINE_STRUCT_OFFSET Keyboard, repeat, 80
DEFINE_STRUCT_OFFSET Keyboard, pressed_keys, 88
DEFINE_STRUCT_OFFSET Keyboard, pressed_count, 96
DEFINE_STRUCT_OFFSET Keyboard, repeat_key, 100
DEFINE_STRUCT_OFFSET Keyboard, repeat_timer, 104
DEFINE_STRUCT_OFFSET Keyboard, repeat_rate, 112
DEFINE_STRUCT_OFFSET Keyboard, repeat_delay, 116
%define Keyboard_SIZE 120
%define Keyboard.size 120
%define Keyboard_size 120

; Pointer
; Pointer embeds InputDevice (64 bytes) so every input device can share the
; intrusive Seat.devices list without overlapping pointer-specific state.
DEFINE_STRUCT_OFFSET Pointer, x, 64
DEFINE_STRUCT_OFFSET Pointer, y, 68
DEFINE_STRUCT_OFFSET Pointer, buttons, 72
DEFINE_STRUCT_OFFSET Pointer, serial, 76
DEFINE_STRUCT_OFFSET Pointer, focus, 80
DEFINE_STRUCT_OFFSET Pointer, constraint, 88
DEFINE_STRUCT_OFFSET Pointer, accel, 96
DEFINE_STRUCT_OFFSET Pointer, grab, 104
DEFINE_STRUCT_OFFSET Pointer, confined, 112
DEFINE_STRUCT_OFFSET Pointer, locked, 113
DEFINE_STRUCT_OFFSET Pointer, lock_x, 116
DEFINE_STRUCT_OFFSET Pointer, lock_y, 120
DEFINE_STRUCT_OFFSET Pointer, cursor, 128
%define Pointer_SIZE 136
%define Pointer.size 136
%define Pointer_size 136

; InputSource
DEFINE_STRUCT_OFFSET InputSource, type, 0
DEFINE_STRUCT_OFFSET InputSource, name, 8
DEFINE_STRUCT_OFFSET InputSource, init, 16
DEFINE_STRUCT_OFFSET InputSource, deinit, 24
DEFINE_STRUCT_OFFSET InputSource, start, 32
DEFINE_STRUCT_OFFSET InputSource, stop, 40
DEFINE_STRUCT_OFFSET InputSource, get_device, 48
DEFINE_STRUCT_OFFSET InputSource, grab, 56
DEFINE_STRUCT_OFFSET InputSource, next, 64
DEFINE_STRUCT_OFFSET InputSource, virtual, 72
%define InputSource_SIZE 80
%define InputSource.size 80
%define InputSource_size 80

; Tablet
; Tablet embeds InputDevice.
DEFINE_STRUCT_OFFSET Tablet, tool_type, 64
DEFINE_STRUCT_OFFSET Tablet, tool_id, 68
DEFINE_STRUCT_OFFSET Tablet, x, 72
DEFINE_STRUCT_OFFSET Tablet, y, 76
DEFINE_STRUCT_OFFSET Tablet, pressure, 80
DEFINE_STRUCT_OFFSET Tablet, distance, 84
DEFINE_STRUCT_OFFSET Tablet, tilt_x, 88
DEFINE_STRUCT_OFFSET Tablet, tilt_y, 92
DEFINE_STRUCT_OFFSET Tablet, rotation, 96
DEFINE_STRUCT_OFFSET Tablet, slider, 100
DEFINE_STRUCT_OFFSET Tablet, wheel, 104
DEFINE_STRUCT_OFFSET Tablet, buttons, 108
DEFINE_STRUCT_OFFSET Tablet, proximity, 112
DEFINE_STRUCT_OFFSET Tablet, tip_state, 113
DEFINE_STRUCT_OFFSET Tablet, prox_distance, 116
%define Tablet_SIZE 120
%define Tablet.size 120
%define Tablet_size 120

; Touch
; Touch also embeds InputDevice.
DEFINE_STRUCT_OFFSET Touch, slots, 64
DEFINE_STRUCT_OFFSET Touch, num_slots, 72
DEFINE_STRUCT_OFFSET Touch, max_slots, 76
DEFINE_STRUCT_OFFSET Touch, active_slots, 80
DEFINE_STRUCT_OFFSET Touch, surface, 88
%define Touch_SIZE 96
%define Touch.size 96
%define Touch_size 96

; TouchSlot
DEFINE_STRUCT_OFFSET TouchSlot, tracking_id, 0
DEFINE_STRUCT_OFFSET TouchSlot, x, 4
DEFINE_STRUCT_OFFSET TouchSlot, y, 8
DEFINE_STRUCT_OFFSET TouchSlot, active, 12
%define TouchSlot_SIZE 16
%define TouchSlot.size 16
%define TouchSlot_size 16

; FaultDump
DEFINE_STRUCT_OFFSET FaultDump, time_ns, 0
DEFINE_STRUCT_OFFSET FaultDump, fault_code, 8
DEFINE_STRUCT_OFFSET FaultDump, client_id, 16
DEFINE_STRUCT_OFFSET FaultDump, object, 24
DEFINE_STRUCT_OFFSET FaultDump, opcode, 32
DEFINE_STRUCT_OFFSET FaultDump, rax, 36
DEFINE_STRUCT_OFFSET FaultDump, rbx, 40
DEFINE_STRUCT_OFFSET FaultDump, rcx, 44
DEFINE_STRUCT_OFFSET FaultDump, rdx, 48
DEFINE_STRUCT_OFFSET FaultDump, rsi, 52
DEFINE_STRUCT_OFFSET FaultDump, rdi, 56
DEFINE_STRUCT_OFFSET FaultDump, rbp, 60
DEFINE_STRUCT_OFFSET FaultDump, rsp, 64
DEFINE_STRUCT_OFFSET FaultDump, r8, 68
DEFINE_STRUCT_OFFSET FaultDump, r9, 72
DEFINE_STRUCT_OFFSET FaultDump, r10, 76
DEFINE_STRUCT_OFFSET FaultDump, r11, 80
DEFINE_STRUCT_OFFSET FaultDump, r12, 84
DEFINE_STRUCT_OFFSET FaultDump, r13, 88
DEFINE_STRUCT_OFFSET FaultDump, r14, 92
DEFINE_STRUCT_OFFSET FaultDump, r15, 96
DEFINE_STRUCT_OFFSET FaultDump, rip, 100
DEFINE_STRUCT_OFFSET FaultDump, rflags, 108
%define FaultDump_SIZE 112
%define FaultDump.size 112
%define FaultDump_size 112

; Metrics
DEFINE_STRUCT_OFFSET Metrics, server, 0
DEFINE_STRUCT_OFFSET Metrics, frames, 8
DEFINE_STRUCT_OFFSET Metrics, dropped, 16
DEFINE_STRUCT_OFFSET Metrics, commits, 24
DEFINE_STRUCT_OFFSET Metrics, presents, 32
DEFINE_STRUCT_OFFSET Metrics, input_events, 40
DEFINE_STRUCT_OFFSET Metrics, proto_errors, 48
DEFINE_STRUCT_OFFSET Metrics, faults, 56
DEFINE_STRUCT_OFFSET Metrics, last_fps_time, 64
DEFINE_STRUCT_OFFSET Metrics, last_frames, 72
DEFINE_STRUCT_OFFSET Metrics, fps, 80
%define Metrics_SIZE 88
%define Metrics.size 88
%define Metrics_size 88

; ProtoLog
DEFINE_STRUCT_OFFSET ProtoLog, server, 0
DEFINE_STRUCT_OFFSET ProtoLog, buf, 8
DEFINE_STRUCT_OFFSET ProtoLog, capacity, 16
DEFINE_STRUCT_OFFSET ProtoLog, write_pos, 24
DEFINE_STRUCT_OFFSET ProtoLog, count, 32
DEFINE_STRUCT_OFFSET ProtoLog, enabled, 40
DEFINE_STRUCT_OFFSET ProtoLog, dropped, 48
%define ProtoLog_SIZE 56
%define ProtoLog.size 56
%define ProtoLog_size 56

; ProtoLogEntry
DEFINE_STRUCT_OFFSET ProtoLogEntry, time_ns, 0
DEFINE_STRUCT_OFFSET ProtoLogEntry, dir, 8
DEFINE_STRUCT_OFFSET ProtoLogEntry, opcode, 12
DEFINE_STRUCT_OFFSET ProtoLogEntry, size, 14
DEFINE_STRUCT_OFFSET ProtoLogEntry, client_id, 16
DEFINE_STRUCT_OFFSET ProtoLogEntry, obj, 24
DEFINE_STRUCT_OFFSET ProtoLogEntry, flags, 32
DEFINE_STRUCT_OFFSET ProtoLogEntry, len, 36
DEFINE_STRUCT_OFFSET ProtoLogEntry, payload_off, 40
DEFINE_STRUCT_OFFSET ProtoLogEntry, payload, 48
%define ProtoLogEntry_SIZE 56
%define ProtoLogEntry.size 56
%define ProtoLogEntry_size 56

; Recorder
DEFINE_STRUCT_OFFSET Recorder, server, 0
DEFINE_STRUCT_OFFSET Recorder, active, 8
DEFINE_STRUCT_OFFSET Recorder, path, 16
DEFINE_STRUCT_OFFSET Recorder, path_len, 24
DEFINE_STRUCT_OFFSET Recorder, frames, 32
DEFINE_STRUCT_OFFSET Recorder, msg_count, 40
DEFINE_STRUCT_OFFSET Recorder, bytes, 48
DEFINE_STRUCT_OFFSET Recorder, start_time, 56
DEFINE_STRUCT_OFFSET Recorder, file, 64
%define Recorder_SIZE 72
%define Recorder.size 72
%define Recorder_size 72

; Replayer
DEFINE_STRUCT_OFFSET Replayer, server, 0
DEFINE_STRUCT_OFFSET Replayer, active, 8
DEFINE_STRUCT_OFFSET Replayer, frames_total, 16
DEFINE_STRUCT_OFFSET Replayer, frames_done, 24
DEFINE_STRUCT_OFFSET Replayer, mismatches, 32
DEFINE_STRUCT_OFFSET Replayer, expected_crc, 40
%define Replayer_SIZE 48
%define Replayer.size 48
%define Replayer_size 48

; ClientStats
DEFINE_STRUCT_OFFSET ClientStats, client_id, 0
DEFINE_STRUCT_OFFSET ClientStats, frames, 8
DEFINE_STRUCT_OFFSET ClientStats, commits, 16
DEFINE_STRUCT_OFFSET ClientStats, damages, 24
DEFINE_STRUCT_OFFSET ClientStats, events_in, 32
DEFINE_STRUCT_OFFSET ClientStats, events_out, 40
DEFINE_STRUCT_OFFSET ClientStats, bytes_in, 48
DEFINE_STRUCT_OFFSET ClientStats, bytes_out, 56
DEFINE_STRUCT_OFFSET ClientStats, proto_errors, 64
DEFINE_STRUCT_OFFSET ClientStats, last_commit, 64
DEFINE_STRUCT_OFFSET ClientStats, last_present, 72
DEFINE_STRUCT_OFFSET ClientStats, commit_to_present_ns, 80
DEFINE_STRUCT_OFFSET ClientStats, mem_bytes, 88
DEFINE_STRUCT_OFFSET ClientStats, last_reset, 96
%define ClientStats_SIZE 104
%define ClientStats.size 104
%define ClientStats_size 104

; FrameTimeline
DEFINE_STRUCT_OFFSET FrameTimeline, server, 0
DEFINE_STRUCT_OFFSET FrameTimeline, marks, 8
DEFINE_STRUCT_OFFSET FrameTimeline, capacity, 16
DEFINE_STRUCT_OFFSET FrameTimeline, count, 24
DEFINE_STRUCT_OFFSET FrameTimeline, head, 32
DEFINE_STRUCT_OFFSET FrameTimeline, seq, 40
%define FrameTimeline_SIZE 48
%define FrameTimeline.size 48
%define FrameTimeline_size 48

; FrameMark
DEFINE_STRUCT_OFFSET FrameMark, time_ns, 0
DEFINE_STRUCT_OFFSET FrameMark, frame_number, 8
DEFINE_STRUCT_OFFSET FrameMark, flags, 16
DEFINE_STRUCT_OFFSET FrameMark, frame_seq, 24
DEFINE_STRUCT_OFFSET FrameMark, composite_start, 32
DEFINE_STRUCT_OFFSET FrameMark, composite_end, 40
DEFINE_STRUCT_OFFSET FrameMark, flip_time, 48
DEFINE_STRUCT_OFFSET FrameMark, vblank_time, 56
DEFINE_STRUCT_OFFSET FrameMark, present_time, 64
DEFINE_STRUCT_OFFSET FrameMark, damage_bytes, 72
%define FrameMark_SIZE 80
%define FrameMark.size 80
%define FrameMark_size 80

; Trace
DEFINE_STRUCT_OFFSET Trace, server, 0
DEFINE_STRUCT_OFFSET Trace, buffer, 8
DEFINE_STRUCT_OFFSET Trace, capacity, 16
DEFINE_STRUCT_OFFSET Trace, head, 24
DEFINE_STRUCT_OFFSET Trace, count, 32
DEFINE_STRUCT_OFFSET Trace, event_size, 40
DEFINE_STRUCT_OFFSET Trace, arena, 48
DEFINE_STRUCT_OFFSET Trace, buf, 56
DEFINE_STRUCT_OFFSET Trace, enabled_mask, 64
DEFINE_STRUCT_OFFSET Trace, dropped, 72
%define Trace_SIZE 80
%define Trace.size 80
%define Trace_size 80

; TraceEvent
DEFINE_STRUCT_OFFSET TraceEvent, time_ns, 0
DEFINE_STRUCT_OFFSET TraceEvent, type, 8
DEFINE_STRUCT_OFFSET TraceEvent, event_id, 12
DEFINE_STRUCT_OFFSET TraceEvent, client_id, 20
DEFINE_STRUCT_OFFSET TraceEvent, object, 28
DEFINE_STRUCT_OFFSET TraceEvent, opcode, 36
DEFINE_STRUCT_OFFSET TraceEvent, flags, 40
DEFINE_STRUCT_OFFSET TraceEvent, arg0, 48
DEFINE_STRUCT_OFFSET TraceEvent, arg1, 56
DEFINE_STRUCT_OFFSET TraceEvent, arg2, 64
DEFINE_STRUCT_OFFSET TraceEvent, arg3, 72
%define TraceEvent_SIZE 80
%define TraceEvent.size 80
%define TraceEvent_size 80

; Server DPMS fields
DEFINE_STRUCT_OFFSET Server, dpms_state, 280
DEFINE_STRUCT_OFFSET Server, dpms_timeout, 284
DEFINE_STRUCT_OFFSET Server, dpms_suspend_timeout, 288
DEFINE_STRUCT_OFFSET Server, dpms_off_timeout, 292
%define Server_SIZE 296
%define Server.size 296
%define Server_size 296

; FrameCtx
DEFINE_STRUCT_OFFSET FrameCtx, output, 0
DEFINE_STRUCT_OFFSET FrameCtx, scale, 8
DEFINE_STRUCT_OFFSET FrameCtx, rotation, 16
%define FrameCtx_SIZE 24
%define FrameCtx.size 24
%define FrameCtx_size 24

; LayoutEngine
DEFINE_STRUCT_OFFSET LayoutEngine, root, 0
DEFINE_STRUCT_OFFSET LayoutEngine, node_count, 8
DEFINE_STRUCT_OFFSET LayoutEngine, gap_size, 16
DEFINE_STRUCT_OFFSET LayoutEngine, master_ratio, 24
DEFINE_STRUCT_OFFSET LayoutEngine, smart_gaps, 32
DEFINE_STRUCT_OFFSET LayoutEngine, smart_borders, 40
DEFINE_STRUCT_OFFSET LayoutEngine, server, 48
%define LayoutEngine_SIZE 56
%define LayoutEngine.size 56
%define LayoutEngine_size 56

; All-caps aliases for LayoutEngine
%define LAYOUT_ENGINE_ROOT 0
%define LAYOUT_ENGINE_NODE_COUNT 8
%define LAYOUT_ENGINE_GAP_SIZE 16
%define LAYOUT_ENGINE_MASTER_RATIO 24
%define LAYOUT_ENGINE_SMART_GAPS 32
%define LAYOUT_ENGINE_SMART_BORDERS 40
%define LAYOUT_ENGINE_SERVER 48

; LayoutNode
DEFINE_STRUCT_OFFSET LayoutNode, type, 0
DEFINE_STRUCT_OFFSET LayoutNode, left, 8
DEFINE_STRUCT_OFFSET LayoutNode, right, 16
DEFINE_STRUCT_OFFSET LayoutNode, parent, 24
DEFINE_STRUCT_OFFSET LayoutNode, rect, 32
DEFINE_STRUCT_OFFSET LayoutNode, client, 40
DEFINE_STRUCT_OFFSET LayoutNode, ratio, 48
DEFINE_STRUCT_OFFSET LayoutNode, is_master, 56
DEFINE_STRUCT_OFFSET LayoutNode, toplevel, 64
DEFINE_STRUCT_OFFSET LayoutNode, x, 72
DEFINE_STRUCT_OFFSET LayoutNode, y, 80
DEFINE_STRUCT_OFFSET LayoutNode, width, 88
DEFINE_STRUCT_OFFSET LayoutNode, height, 96
DEFINE_STRUCT_OFFSET LayoutNode, gap, 104
%define LayoutNode_SIZE 112
%define LayoutNode.size 112
%define LayoutNode_size 112

; Toplevel
DEFINE_STRUCT_OFFSET Toplevel, next_ws, 0
DEFINE_STRUCT_OFFSET Toplevel, prev_ws, 8
DEFINE_STRUCT_OFFSET Toplevel, layout_node, 16
DEFINE_STRUCT_OFFSET Toplevel, output, 24
DEFINE_STRUCT_OFFSET Toplevel, workspace, 32
DEFINE_STRUCT_OFFSET Toplevel, title, 40
DEFINE_STRUCT_OFFSET Toplevel, app_id, 48
DEFINE_STRUCT_OFFSET Toplevel, decorations, 56
DEFINE_STRUCT_OFFSET Toplevel, surface, 64
DEFINE_STRUCT_OFFSET Toplevel, pending_width, 72
DEFINE_STRUCT_OFFSET Toplevel, pending_height, 80
DEFINE_STRUCT_OFFSET Toplevel, pending_state, 88
DEFINE_STRUCT_OFFSET Toplevel, state, 96
DEFINE_STRUCT_OFFSET Toplevel, shell, 104
DEFINE_STRUCT_OFFSET Toplevel, decoration, 112
DEFINE_STRUCT_OFFSET Toplevel, width, 120
DEFINE_STRUCT_OFFSET Toplevel, height, 124
DEFINE_STRUCT_OFFSET Toplevel, saved_width, 128
DEFINE_STRUCT_OFFSET Toplevel, saved_height, 132
%define Toplevel_SIZE 136
%define Toplevel.size 112
%define Toplevel_size 112

; Policy
DEFINE_STRUCT_OFFSET Policy, server, 0
DEFINE_STRUCT_OFFSET Policy, type, 4
DEFINE_STRUCT_OFFSET Policy, layout, 8
DEFINE_STRUCT_OFFSET Policy, configure, 16
DEFINE_STRUCT_OFFSET Policy, focus_change, 24
DEFINE_STRUCT_OFFSET Policy, kiosk_allowed_app, 28
DEFINE_STRUCT_OFFSET Policy, new_window, 32
DEFINE_STRUCT_OFFSET Policy, close_window, 40
DEFINE_STRUCT_OFFSET Policy, workspace_changed, 48
DEFINE_STRUCT_OFFSET Policy, tile_window, 48
DEFINE_STRUCT_OFFSET Policy, window_configured, 56
%define Policy_SIZE 64
%define Policy.size 64
%define Policy_size 64

; PolicyExternal
DEFINE_STRUCT_OFFSET PolicyExternal, base, 0
DEFINE_STRUCT_OFFSET PolicyExternal, server, 8
DEFINE_STRUCT_OFFSET PolicyExternal, client, 16
DEFINE_STRUCT_OFFSET PolicyExternal, channel, 24
DEFINE_STRUCT_OFFSET PolicyExternal, capabilities, 32
DEFINE_STRUCT_OFFSET PolicyExternal, pending_requests, 32
%define PolicyExternal_SIZE 40
%define PolicyExternal.size 40
%define PolicyExternal_size 40

; PolicyFloating
DEFINE_STRUCT_OFFSET PolicyFloating, base, 0
DEFINE_STRUCT_OFFSET PolicyFloating, server, 8
DEFINE_STRUCT_OFFSET PolicyFloating, data, 16
%define PolicyFloating_SIZE 24
%define PolicyFloating.size 24
%define PolicyFloating_size 24

; PolicyKiosk
DEFINE_STRUCT_OFFSET PolicyKiosk, base, 0
DEFINE_STRUCT_OFFSET PolicyKiosk, server, 8
DEFINE_STRUCT_OFFSET PolicyKiosk, data, 16
DEFINE_STRUCT_OFFSET PolicyKiosk, allowed_app_id, 24
DEFINE_STRUCT_OFFSET PolicyKiosk, allow_exit, 32
DEFINE_STRUCT_OFFSET PolicyKiosk, auto_restart, 33
%define PolicyKiosk_SIZE 24
%define PolicyKiosk.size 24
%define PolicyKiosk_size 24

; State flags
%define STATE_FLAG_FULLSCREEN    (1 << 0)
%define STATE_FLAG_MAXIMIZED     (1 << 1)
%define STATE_FLAG_TILED         (1 << 2)
%define STATE_FLAG_FLOATING      (1 << 3)
%define STATE_FLAG_MODAL         (1 << 4)



; VirtualOutput
DEFINE_STRUCT_OFFSET VirtualOutput, server, 0
DEFINE_STRUCT_OFFSET VirtualOutput, conn, 8
DEFINE_STRUCT_OFFSET VirtualOutput, seq, 16
DEFINE_STRUCT_OFFSET VirtualOutput, width, 24
DEFINE_STRUCT_OFFSET VirtualOutput, height, 28
DEFINE_STRUCT_OFFSET VirtualOutput, format, 32
DEFINE_STRUCT_OFFSET VirtualOutput, damage, 36
DEFINE_STRUCT_OFFSET VirtualOutput, fb, 40
DEFINE_STRUCT_OFFSET VirtualOutput, output, 48
DEFINE_STRUCT_OFFSET VirtualOutput, tilediff, 56
%define VirtualOutput_SIZE 64

; RfbClient




; CrpServer
DEFINE_STRUCT_OFFSET CrpServer, server, 0
DEFINE_STRUCT_OFFSET CrpServer, listener, 8
DEFINE_STRUCT_OFFSET CrpServer, port, 16
DEFINE_STRUCT_OFFSET CrpServer, sessions, 20
DEFINE_STRUCT_OFFSET CrpServer, voutput, 28
DEFINE_STRUCT_OFFSET CrpServer, running, 36
%define CrpServer_SIZE 40



; CrpSession
DEFINE_STRUCT_OFFSET CrpSession, server, 0
DEFINE_STRUCT_OFFSET CrpSession, conn, 8
DEFINE_STRUCT_OFFSET CrpSession, view_only, 16
DEFINE_STRUCT_OFFSET CrpSession, seq, 17
DEFINE_STRUCT_OFFSET CrpSession, next, 25
%define CrpSession_SIZE 40



; RfbServer


; RfbServer (full)
DEFINE_STRUCT_OFFSET RfbServer, server, 0
DEFINE_STRUCT_OFFSET RfbServer, listener, 8
DEFINE_STRUCT_OFFSET RfbServer, port, 16
DEFINE_STRUCT_OFFSET RfbServer, clients, 24
DEFINE_STRUCT_OFFSET RfbServer, client_count, 32
DEFINE_STRUCT_OFFSET RfbServer, voutput, 40
DEFINE_STRUCT_OFFSET RfbServer, running, 48
%define RfbServer_SIZE 56

; RfbClient (full)
DEFINE_STRUCT_OFFSET RfbClient, server, 0
DEFINE_STRUCT_OFFSET RfbClient, conn, 8
DEFINE_STRUCT_OFFSET RfbClient, width, 16
DEFINE_STRUCT_OFFSET RfbClient, height, 20
DEFINE_STRUCT_OFFSET RfbClient, shared, 24
DEFINE_STRUCT_OFFSET RfbClient, encodings, 32
DEFINE_STRUCT_OFFSET RfbClient, enc_count, 40
DEFINE_STRUCT_OFFSET RfbClient, next, 48
%define RfbClient_SIZE 56





; GpuRenderer
DEFINE_STRUCT_OFFSET GpuRenderer, base, 0
DEFINE_STRUCT_OFFSET GpuRenderer, gpu, 8
DEFINE_STRUCT_OFFSET GpuRenderer, sw_fallback, 16
%define GpuRenderer_SIZE 24



; GpuDevice
DEFINE_STRUCT_OFFSET GpuDevice, ring_gfx, 0
DEFINE_STRUCT_OFFSET GpuDevice, ring_compute, 8
DEFINE_STRUCT_OFFSET GpuDevice, ring_sdma, 16
DEFINE_STRUCT_OFFSET GpuDevice, vram_heap, 24
DEFINE_STRUCT_OFFSET GpuDevice, gtt_heap, 32
%define GpuDevice_SIZE 40



; Renderer (software renderer)
DEFINE_STRUCT_OFFSET Renderer, backend, 0
DEFINE_STRUCT_OFFSET Renderer, arena, 8
DEFINE_STRUCT_OFFSET Renderer, begin_frame, 16
DEFINE_STRUCT_OFFSET Renderer, render_surface, 24
DEFINE_STRUCT_OFFSET Renderer, render_rect, 32
DEFINE_STRUCT_OFFSET Renderer, end_frame, 40
DEFINE_STRUCT_OFFSET Renderer, flush, 48
DEFINE_STRUCT_OFFSET Renderer, caps, 56
DEFINE_STRUCT_OFFSET Renderer, blend_fn, 64
%define Renderer_SIZE 72



; FrameCtx
DEFINE_STRUCT_OFFSET FrameCtx, output, 0
DEFINE_STRUCT_OFFSET FrameCtx, damage, 8
DEFINE_STRUCT_OFFSET FrameCtx, render_list, 16
DEFINE_STRUCT_OFFSET FrameCtx, framebuffer, 24
DEFINE_STRUCT_OFFSET FrameCtx, stride, 32
DEFINE_STRUCT_OFFSET FrameCtx, width, 36
DEFINE_STRUCT_OFFSET FrameCtx, height, 40
DEFINE_STRUCT_OFFSET FrameCtx, color_transform, 48
%define FrameCtx_SIZE 56

; Render capabilities
%define RENDER_CAP_BLEND         (1 << 0)
%define RENDER_CAP_SCALE         (1 << 1)
%define RENDER_CAP_TRANSFORM     (1 << 2)
%define RENDER_CAP_DIRECT_SCANOUT (1 << 3)



; Gate
DEFINE_STRUCT_OFFSET Gate, server, 0
DEFINE_STRUCT_OFFSET Gate, audit_log, 8
%define Gate_SIZE 16



; AuditEntry
DEFINE_STRUCT_OFFSET AuditEntry, timestamp, 0
DEFINE_STRUCT_OFFSET AuditEntry, client_id, 8
DEFINE_STRUCT_OFFSET AuditEntry, action, 16
DEFINE_STRUCT_OFFSET AuditEntry, capability, 20
DEFINE_STRUCT_OFFSET AuditEntry, result, 28
DEFINE_STRUCT_OFFSET AuditEntry, details_len, 32
DEFINE_STRUCT_OFFSET AuditEntry, details, 40
%define AuditEntry_SIZE 48



; TrustProfile
DEFINE_STRUCT_OFFSET TrustProfile, name, 0
DEFINE_STRUCT_OFFSET TrustProfile, caps, 8
DEFINE_STRUCT_OFFSET TrustProfile, quota_mem, 16
DEFINE_STRUCT_OFFSET TrustProfile, quota_surfs, 24
DEFINE_STRUCT_OFFSET TrustProfile, quota_buffers, 28
DEFINE_STRUCT_OFFSET TrustProfile, rate_msg_sec, 32
DEFINE_STRUCT_OFFSET TrustProfile, rate_bytes_sec, 40
DEFINE_STRUCT_OFFSET TrustProfile, prompts, 48
DEFINE_STRUCT_OFFSET TrustProfile, flags, 52
DEFINE_STRUCT_OFFSET TrustProfile, next, 56
%define TrustProfile_SIZE 64

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
DEFINE_STRUCT_OFFSET AuditLog, buffer, 0
DEFINE_STRUCT_OFFSET AuditLog, capacity, 8
DEFINE_STRUCT_OFFSET AuditLog, head, 16
DEFINE_STRUCT_OFFSET AuditLog, tail, 24
DEFINE_STRUCT_OFFSET AuditLog, element_size, 32
DEFINE_STRUCT_OFFSET AuditLog, count, 40
%define AuditLog_SIZE 48



; Prompt
DEFINE_STRUCT_OFFSET Prompt, client, 0
DEFINE_STRUCT_OFFSET Prompt, message, 8
DEFINE_STRUCT_OFFSET Prompt, message_len, 16
DEFINE_STRUCT_OFFSET Prompt, capability, 24
DEFINE_STRUCT_OFFSET Prompt, options, 32
DEFINE_STRUCT_OFFSET Prompt, option_count, 40
DEFINE_STRUCT_OFFSET Prompt, callback, 44
DEFINE_STRUCT_OFFSET Prompt, user_data, 52
DEFINE_STRUCT_OFFSET Prompt, timeout, 60
DEFINE_STRUCT_OFFSET Prompt, state, 68
%define Prompt_SIZE 72

; PromptOption
DEFINE_STRUCT_OFFSET PromptOption, text, 0
DEFINE_STRUCT_OFFSET PromptOption, text_len, 8
DEFINE_STRUCT_OFFSET PromptOption, action, 16
DEFINE_STRUCT_OFFSET PromptOption, value, 20
%define PromptOption_SIZE 24



; Token
DEFINE_STRUCT_OFFSET Token, value, 0
DEFINE_STRUCT_OFFSET Token, type, 8
DEFINE_STRUCT_OFFSET Token, capabilities, 12
DEFINE_STRUCT_OFFSET Token, expires, 20
DEFINE_STRUCT_OFFSET Token, issued_to, 28
DEFINE_STRUCT_OFFSET Token, issued_by, 36
DEFINE_STRUCT_OFFSET Token, issued_at, 44
%define Token_SIZE 56



; Object
DEFINE_STRUCT_OFFSET Object, interface_id, 0
DEFINE_STRUCT_OFFSET Object, version, 2
DEFINE_STRUCT_OFFSET Object, refcount, 4
DEFINE_STRUCT_OFFSET Object, data_ptr, 12
DEFINE_STRUCT_OFFSET Object, client_id, 16
%define Object_SIZE 24



; Fence (full)
DEFINE_STRUCT_OFFSET Fence, state, 0
DEFINE_STRUCT_OFFSET Fence, timeline, 4
DEFINE_STRUCT_OFFSET Fence, value, 12
DEFINE_STRUCT_OFFSET Fence, waiters, 20
DEFINE_STRUCT_OFFSET Fence, lock, 28
DEFINE_STRUCT_OFFSET Fence, arena, 36
%define Fence_SIZE 44

; WaitQueue
DEFINE_STRUCT_OFFSET WaitQueue, next, 0
DEFINE_STRUCT_OFFSET WaitQueue, thread, 8
DEFINE_STRUCT_OFFSET WaitQueue, value, 16
%define WaitQueue_SIZE 24



; ListNode
DEFINE_STRUCT_OFFSET ListNode, next, 0
DEFINE_STRUCT_OFFSET ListNode, prev, 8
DEFINE_STRUCT_OFFSET ListNode, data, 16
%define ListNode_SIZE 24



; IdleManager
DEFINE_STRUCT_OFFSET IdleManager, server, 0
DEFINE_STRUCT_OFFSET IdleManager, idle_timeout, 8
DEFINE_STRUCT_OFFSET IdleManager, warning_time, 16
DEFINE_STRUCT_OFFSET IdleManager, timer, 24
DEFINE_STRUCT_OFFSET IdleManager, callbacks, 32
DEFINE_STRUCT_OFFSET IdleManager, inhibit_count, 40
%define IdleManager_SIZE 48



; KioskSession
DEFINE_STRUCT_OFFSET KioskSession, session, 0
DEFINE_STRUCT_OFFSET KioskSession, allowed_app_id, 8
DEFINE_STRUCT_OFFSET KioskSession, restart_on_exit, 16
DEFINE_STRUCT_OFFSET KioskSession, allow_exit, 17
DEFINE_STRUCT_OFFSET KioskSession, lock_screen, 24
DEFINE_STRUCT_OFFSET KioskSession, watchdog_timer, 32
%define KioskSession_SIZE 40



; LockScreen
DEFINE_STRUCT_OFFSET LockScreen, session, 0
DEFINE_STRUCT_OFFSET LockScreen, surface, 8
DEFINE_STRUCT_OFFSET LockScreen, password_hash, 16
DEFINE_STRUCT_OFFSET LockScreen, attempts, 24
DEFINE_STRUCT_OFFSET LockScreen, max_attempts, 28
DEFINE_STRUCT_OFFSET LockScreen, lock_time, 32
DEFINE_STRUCT_OFFSET LockScreen, unlock_callback, 40
DEFINE_STRUCT_OFFSET LockScreen, user_data, 48
DEFINE_STRUCT_OFFSET LockScreen, state, 56
DEFINE_STRUCT_OFFSET LockScreen, next, 64
%define LockScreen_SIZE 72



; Session
DEFINE_STRUCT_OFFSET Session, id, 0
DEFINE_STRUCT_OFFSET Session, user, 8
DEFINE_STRUCT_OFFSET Session, state, 16
DEFINE_STRUCT_OFFSET Session, lock_screen, 24
DEFINE_STRUCT_OFFSET Session, kiosk_session, 32
DEFINE_STRUCT_OFFSET Session, seat, 40
%define Session_SIZE 48



; Multiseat
DEFINE_STRUCT_OFFSET Multiseat, server, 0
DEFINE_STRUCT_OFFSET Multiseat, seats, 8
DEFINE_STRUCT_OFFSET Multiseat, seat_count, 16
DEFINE_STRUCT_OFFSET Multiseat, default_seat, 24
%define Multiseat_SIZE 32



; PowerManager
DEFINE_STRUCT_OFFSET PowerManager, server, 0
DEFINE_STRUCT_OFFSET PowerManager, inhibit_mask, 8
DEFINE_STRUCT_OFFSET PowerManager, suspend_callback, 16
DEFINE_STRUCT_OFFSET PowerManager, resume_callback, 24
DEFINE_STRUCT_OFFSET PowerManager, battery_level, 32
DEFINE_STRUCT_OFFSET PowerManager, ac_connected, 40
DEFINE_STRUCT_OFFSET PowerManager, suspending, 41
%define PowerManager_SIZE 48



; SeatSession
DEFINE_STRUCT_OFFSET SeatSession, seat, 0
DEFINE_STRUCT_OFFSET SeatSession, user_id, 8
DEFINE_STRUCT_OFFSET SeatSession, active, 16
DEFINE_STRUCT_OFFSET SeatSession, locked, 17
DEFINE_STRUCT_OFFSET SeatSession, lock_surface, 24
DEFINE_STRUCT_OFFSET SeatSession, idle_timer, 32
DEFINE_STRUCT_OFFSET SeatSession, idle_timeout, 40
DEFINE_STRUCT_OFFSET SeatSession, inhibit_count, 48
DEFINE_STRUCT_OFFSET SeatSession, power_inhibit, 56
%define SeatSession_SIZE 64



; UserSession
DEFINE_STRUCT_OFFSET UserSession, session_id, 0
DEFINE_STRUCT_OFFSET UserSession, user_id, 8
DEFINE_STRUCT_OFFSET UserSession, seat, 16
DEFINE_STRUCT_OFFSET UserSession, start_time, 24
DEFINE_STRUCT_OFFSET UserSession, last_activity, 32
DEFINE_STRUCT_OFFSET UserSession, state, 40
DEFINE_STRUCT_OFFSET UserSession, autostart_apps, 44
DEFINE_STRUCT_OFFSET UserSession, env_vars, 52
DEFINE_STRUCT_OFFSET UserSession, cwd, 60
DEFINE_STRUCT_OFFSET UserSession, next, 68
%define UserSession_SIZE 76



; Configure
DEFINE_STRUCT_OFFSET Configure, serial, 0
DEFINE_STRUCT_OFFSET Configure, surface, 8
DEFINE_STRUCT_OFFSET Configure, width, 16
DEFINE_STRUCT_OFFSET Configure, height, 20
DEFINE_STRUCT_OFFSET Configure, states, 24
DEFINE_STRUCT_OFFSET Configure, callback, 28
DEFINE_STRUCT_OFFSET Configure, user_data, 36
DEFINE_STRUCT_OFFSET Configure, ack_callback, 44
DEFINE_STRUCT_OFFSET Configure, next, 52
%define Configure_SIZE 56






; Decoration
DEFINE_STRUCT_OFFSET Decoration, toplevel, 0
DEFINE_STRUCT_OFFSET Decoration, mode, 8
DEFINE_STRUCT_OFFSET Decoration, theme, 16
DEFINE_STRUCT_OFFSET Decoration, buttons, 24
DEFINE_STRUCT_OFFSET Decoration, button_count, 32
DEFINE_STRUCT_OFFSET Decoration, titlebar_height, 36
DEFINE_STRUCT_OFFSET Decoration, border_width, 40
DEFINE_STRUCT_OFFSET Decoration, frame_callback, 48
DEFINE_STRUCT_OFFSET Decoration, renderer_data, 56
%define Decoration_SIZE 64



; DecorationDrawState
DEFINE_STRUCT_OFFSET DecorationDrawState, framebuffer, 0
DEFINE_STRUCT_OFFSET DecorationDrawState, stride, 8
DEFINE_STRUCT_OFFSET DecorationDrawState, width, 16
DEFINE_STRUCT_OFFSET DecorationDrawState, height, 20
DEFINE_STRUCT_OFFSET DecorationDrawState, titlebar_color, 24
DEFINE_STRUCT_OFFSET DecorationDrawState, border_color, 28
DEFINE_STRUCT_OFFSET DecorationDrawState, button_bg_color, 32
DEFINE_STRUCT_OFFSET DecorationDrawState, button_fg_color, 36
DEFINE_STRUCT_OFFSET DecorationDrawState, inactive_alpha, 40
%define DecorationDrawState_SIZE 48



; DecorationButton
DEFINE_STRUCT_OFFSET DecorationButton, rect, 0
DEFINE_STRUCT_OFFSET DecorationButton, type, 16
DEFINE_STRUCT_OFFSET DecorationButton, state, 20
DEFINE_STRUCT_OFFSET DecorationButton, callback, 24
DEFINE_STRUCT_OFFSET DecorationButton, user_data, 32
%define DecorationButton_SIZE 40

; Button states
%define BUTTON_STATE_NORMAL     0
%define BUTTON_STATE_HOVER      1
%define BUTTON_STATE_PRESSED    2
%define BUTTON_STATE_DISABLED   3



; Layer
DEFINE_STRUCT_OFFSET Layer, surface, 0
DEFINE_STRUCT_OFFSET Layer, shell, 8
DEFINE_STRUCT_OFFSET Layer, output, 16
DEFINE_STRUCT_OFFSET Layer, layer, 24
DEFINE_STRUCT_OFFSET Layer, namespace, 32
DEFINE_STRUCT_OFFSET Layer, anchor, 40
DEFINE_STRUCT_OFFSET Layer, exclusive_zone, 48
DEFINE_STRUCT_OFFSET Layer, keyboard_interactivity, 52
DEFINE_STRUCT_OFFSET Layer, width, 56
DEFINE_STRUCT_OFFSET Layer, height, 60
DEFINE_STRUCT_OFFSET Layer, margin_top, 64
DEFINE_STRUCT_OFFSET Layer, margin_right, 68
DEFINE_STRUCT_OFFSET Layer, margin_bottom, 72
DEFINE_STRUCT_OFFSET Layer, margin_left, 76
DEFINE_STRUCT_OFFSET Layer, next, 80
%define Layer_SIZE 88



; MoveResize
DEFINE_STRUCT_OFFSET MoveResize, seat, 0
DEFINE_STRUCT_OFFSET MoveResize, toplevel, 8
DEFINE_STRUCT_OFFSET MoveResize, type, 16
DEFINE_STRUCT_OFFSET MoveResize, edges, 20
DEFINE_STRUCT_OFFSET MoveResize, start_x, 24
DEFINE_STRUCT_OFFSET MoveResize, start_y, 28
DEFINE_STRUCT_OFFSET MoveResize, initial_x, 32
DEFINE_STRUCT_OFFSET MoveResize, initial_y, 36
DEFINE_STRUCT_OFFSET MoveResize, surface_x, 40
DEFINE_STRUCT_OFFSET MoveResize, surface_y, 44
DEFINE_STRUCT_OFFSET MoveResize, grab_serial, 48
DEFINE_STRUCT_OFFSET MoveResize, grab_time, 56
%define MoveResize_SIZE 64



; Popup
DEFINE_STRUCT_OFFSET Popup, surface, 0
DEFINE_STRUCT_OFFSET Popup, shell, 8
DEFINE_STRUCT_OFFSET Popup, parent, 16
DEFINE_STRUCT_OFFSET Popup, position, 24
DEFINE_STRUCT_OFFSET Popup, x, 28
DEFINE_STRUCT_OFFSET Popup, y, 32
DEFINE_STRUCT_OFFSET Popup, width, 36
DEFINE_STRUCT_OFFSET Popup, height, 36
DEFINE_STRUCT_OFFSET Popup, constrain, 40
DEFINE_STRUCT_OFFSET Popup, next, 48
%define Popup_SIZE 56



; Rule
DEFINE_STRUCT_OFFSET Rule, pattern_type, 0
DEFINE_STRUCT_OFFSET Rule, pattern, 8
DEFINE_STRUCT_OFFSET Rule, action, 16
DEFINE_STRUCT_OFFSET Rule, action_data, 24
DEFINE_STRUCT_OFFSET Rule, priority, 32
DEFINE_STRUCT_OFFSET Rule, enabled, 36
DEFINE_STRUCT_OFFSET Rule, next, 40
%define Rule_SIZE 48






; Theme
DEFINE_STRUCT_OFFSET Theme, name, 0
DEFINE_STRUCT_OFFSET Theme, colors, 8
DEFINE_STRUCT_OFFSET Theme, font, 16
DEFINE_STRUCT_OFFSET Theme, font_size, 24
DEFINE_STRUCT_OFFSET Theme, border_width, 28
DEFINE_STRUCT_OFFSET Theme, border_radius, 32
DEFINE_STRUCT_OFFSET Theme, titlebar_height, 36
DEFINE_STRUCT_OFFSET Theme, button_size, 40
DEFINE_STRUCT_OFFSET Theme, padding, 44
%define Theme_SIZE 56

; ThemeColors
DEFINE_STRUCT_OFFSET ThemeColors, background, 0
DEFINE_STRUCT_OFFSET ThemeColors, foreground, 4
DEFINE_STRUCT_OFFSET ThemeColors, accent, 8
DEFINE_STRUCT_OFFSET ThemeColors, border, 12
DEFINE_STRUCT_OFFSET ThemeColors, titlebar_bg, 16
DEFINE_STRUCT_OFFSET ThemeColors, titlebar_fg, 20
DEFINE_STRUCT_OFFSET ThemeColors, button_bg, 24
DEFINE_STRUCT_OFFSET ThemeColors, button_fg, 28
DEFINE_STRUCT_OFFSET ThemeColors, button_hover_bg, 32
DEFINE_STRUCT_OFFSET ThemeColors, button_hover_fg, 36
DEFINE_STRUCT_OFFSET ThemeColors, button_pressed_bg, 40
DEFINE_STRUCT_OFFSET ThemeColors, button_pressed_fg, 44
%define ThemeColors_SIZE 48



; Toplevel
DEFINE_STRUCT_OFFSET Toplevel, surface, 0
DEFINE_STRUCT_OFFSET Toplevel, shell, 8
DEFINE_STRUCT_OFFSET Toplevel, title, 16
DEFINE_STRUCT_OFFSET Toplevel, app_id, 24
DEFINE_STRUCT_OFFSET Toplevel, state, 32
DEFINE_STRUCT_OFFSET Toplevel, pending_state, 36
DEFINE_STRUCT_OFFSET Toplevel, configure_serial, 40
DEFINE_STRUCT_OFFSET Toplevel, capabilities, 44
DEFINE_STRUCT_OFFSET Toplevel, pending_width, 48
DEFINE_STRUCT_OFFSET Toplevel, pending_height, 52
DEFINE_STRUCT_OFFSET Toplevel, pending_state, 56
DEFINE_STRUCT_OFFSET Toplevel, pending_x, 60
DEFINE_STRUCT_OFFSET Toplevel, pending_y, 64
DEFINE_STRUCT_OFFSET Toplevel, width, 68
DEFINE_STRUCT_OFFSET Toplevel, height, 72
DEFINE_STRUCT_OFFSET Toplevel, x, 76
DEFINE_STRUCT_OFFSET Toplevel, y, 80
DEFINE_STRUCT_OFFSET Toplevel, saved_width, 84
DEFINE_STRUCT_OFFSET Toplevel, saved_height, 88
DEFINE_STRUCT_OFFSET Toplevel, saved_x, 92
DEFINE_STRUCT_OFFSET Toplevel, saved_y, 96
DEFINE_STRUCT_OFFSET Toplevel, decoration, 100
DEFINE_STRUCT_OFFSET Toplevel, layer, 108
DEFINE_STRUCT_OFFSET Toplevel, workspace, 116
DEFINE_STRUCT_OFFSET Toplevel, output, 124
DEFINE_STRUCT_OFFSET Toplevel, seat, 132
DEFINE_STRUCT_OFFSET Toplevel, next_ws, 140
DEFINE_STRUCT_OFFSET Toplevel, prev_ws, 148
DEFINE_STRUCT_OFFSET Toplevel, layout_node, 156
DEFINE_STRUCT_OFFSET Toplevel, frame_cb, 160
%define Toplevel_SIZE 152



; Workspace
DEFINE_STRUCT_OFFSET Workspace, id, 0
DEFINE_STRUCT_OFFSET Workspace, shell, 8
DEFINE_STRUCT_OFFSET Workspace, toplevels, 16
DEFINE_STRUCT_OFFSET Workspace, state, 24
DEFINE_STRUCT_OFFSET Workspace, layout_engine, 28
DEFINE_STRUCT_OFFSET Workspace, name, 36
DEFINE_STRUCT_OFFSET Workspace, next, 44
DEFINE_STRUCT_OFFSET Workspace, next_ws, 52
%define Workspace_SIZE 56



; IMEBridge
DEFINE_STRUCT_OFFSET IMEBridge, seat, 0
DEFINE_STRUCT_OFFSET IMEBridge, active_ime, 8
DEFINE_STRUCT_OFFSET IMEBridge, available_imes, 16
DEFINE_STRUCT_OFFSET IMEBridge, ime_count, 24
DEFINE_STRUCT_OFFSET IMEBridge, focused_text_input, 28
%define IMEBridge_SIZE 32

; IMEInfo
DEFINE_STRUCT_OFFSET IMEInfo, name, 0
DEFINE_STRUCT_OFFSET IMEInfo, engine, 8
DEFINE_STRUCT_OFFSET IMEInfo, capabilities, 16
DEFINE_STRUCT_OFFSET IMEInfo, language, 24
%define IMEInfo_SIZE 40



; PreeditString
DEFINE_STRUCT_OFFSET PreeditString, text, 0
DEFINE_STRUCT_OFFSET PreeditString, text_len, 8
DEFINE_STRUCT_OFFSET PreeditString, cursor, 16
DEFINE_STRUCT_OFFSET PreeditString, selection_start, 20
DEFINE_STRUCT_OFFSET PreeditString, selection_end, 24
DEFINE_STRUCT_OFFSET PreeditString, attributes, 32
DEFINE_STRUCT_OFFSET PreeditString, attr_count, 40
%define PreeditString_SIZE 48

; PreeditAttribute
DEFINE_STRUCT_OFFSET PreeditAttribute, type, 0
DEFINE_STRUCT_OFFSET PreeditAttribute, start, 4
DEFINE_STRUCT_OFFSET PreeditAttribute, end, 8
DEFINE_STRUCT_OFFSET PreeditAttribute, color, 12
%define PreeditAttribute_SIZE 16



; Shortcut
DEFINE_STRUCT_OFFSET Shortcut, keysym, 0
DEFINE_STRUCT_OFFSET Shortcut, modifiers, 4
DEFINE_STRUCT_OFFSET Shortcut, action, 8
DEFINE_STRUCT_OFFSET Shortcut, action_data, 12
DEFINE_STRUCT_OFFSET Shortcut, client, 20
DEFINE_STRUCT_OFFSET Shortcut, next, 28
%define Shortcut_SIZE 36



; TextInput
DEFINE_STRUCT_OFFSET TextInput, seat, 0
DEFINE_STRUCT_OFFSET TextInput, surface, 8
DEFINE_STRUCT_OFFSET TextInput, content_type, 16
DEFINE_STRUCT_OFFSET TextInput, content_hint, 20
DEFINE_STRUCT_OFFSET TextInput, surrounding_text, 24
DEFINE_STRUCT_OFFSET TextInput, cursor, 32
DEFINE_STRUCT_OFFSET TextInput, anchor, 36
DEFINE_STRUCT_OFFSET TextInput, preedit, 40
DEFINE_STRUCT_OFFSET TextInput, content_purpose, 48
DEFINE_STRUCT_OFFSET TextInput, content_hint, 52
DEFINE_STRUCT_OFFSET TextInput, preedit_start, 56
DEFINE_STRUCT_OFFSET TextInput, preedit_end, 60
DEFINE_STRUCT_OFFSET TextInput, commit_text, 64
DEFINE_STRUCT_OFFSET TextInput, delete_surrounding_text, 72
DEFINE_STRUCT_OFFSET TextInput, keysym, 80
DEFINE_STRUCT_OFFSET TextInput, state, 84
DEFINE_STRUCT_OFFSET TextInput, preedit, 88
%define TextInput_SIZE 96

; ============================================================================
; Compositor Structs
; ============================================================================

; Damage
DEFINE_STRUCT_OFFSET Damage, rects, 0
DEFINE_STRUCT_OFFSET Damage, count, 8
DEFINE_STRUCT_OFFSET Damage, capacity, 16
DEFINE_STRUCT_OFFSET Damage, arena, 24
%define Damage_SIZE 32
%define Damage.size 32
%define Damage_size 32

; DamageRect
DEFINE_STRUCT_OFFSET DamageRect, x, 0
DEFINE_STRUCT_OFFSET DamageRect, y, 4
DEFINE_STRUCT_OFFSET DamageRect, w, 8
DEFINE_STRUCT_OFFSET DamageRect, h, 12
%define DamageRect_SIZE 16
%define DamageRect.size 16
%define DamageRect_size 16

; Output
DEFINE_STRUCT_OFFSET Output, id, 0
DEFINE_STRUCT_OFFSET Output, name, 8
DEFINE_STRUCT_OFFSET Output, backend, 16
DEFINE_STRUCT_OFFSET Output, framebuffer, 24
DEFINE_STRUCT_OFFSET Output, scale, 32
DEFINE_STRUCT_OFFSET Output, rotation, 40
DEFINE_STRUCT_OFFSET Output, icc_profile, 48
DEFINE_STRUCT_OFFSET Output, vrr_enabled, 56
DEFINE_STRUCT_OFFSET Output, vrr_flags, 64
DEFINE_STRUCT_OFFSET Output, vrr_caps, 72
DEFINE_STRUCT_OFFSET Output, vrr_min_refresh, 80
DEFINE_STRUCT_OFFSET Output, vrr_max_refresh, 88
DEFINE_STRUCT_OFFSET Output, modes, 96
DEFINE_STRUCT_OFFSET Output, position, 104
DEFINE_STRUCT_OFFSET Output, damage, 112
DEFINE_STRUCT_OFFSET Output, x, 88
DEFINE_STRUCT_OFFSET Output, y, 96
DEFINE_STRUCT_OFFSET Output, width, 104
DEFINE_STRUCT_OFFSET Output, height, 112
DEFINE_STRUCT_OFFSET Output, connected, 120
DEFINE_STRUCT_OFFSET Output, controller, 128
DEFINE_STRUCT_OFFSET Output, crtc_index, 136
DEFINE_STRUCT_OFFSET Output, edid, 144
DEFINE_STRUCT_OFFSET Output, hpd_irq, 152
DEFINE_STRUCT_OFFSET Output, hpd_register, 160
DEFINE_STRUCT_OFFSET Output, i2c_bus, 168
DEFINE_STRUCT_OFFSET Output, current_surface, 176
DEFINE_STRUCT_OFFSET Output, current_mode, 184
DEFINE_STRUCT_OFFSET Output, surfaces, 192
DEFINE_STRUCT_OFFSET Output, toplevels, 200
DEFINE_STRUCT_OFFSET Output, hotplug_callback, 208
DEFINE_STRUCT_OFFSET Output, next, 216
DEFINE_STRUCT_OFFSET Output, stride, 224
DEFINE_STRUCT_OFFSET Output, frame_clock, 232
DEFINE_STRUCT_OFFSET Output, dpms_state, 240
DEFINE_STRUCT_OFFSET Output, dpms_timeout, 241
DEFINE_STRUCT_OFFSET Output, gamma_lut, 248
DEFINE_STRUCT_OFFSET Output, controller_ptr, 256
%define Output_SIZE 264
%define Output.size 264
%define Output_size 264

; All-caps aliases for Output
%define OUTPUT_ID 0
%define OUTPUT_NAME 8
%define OUTPUT_BACKEND 16
%define OUTPUT_FRAMEBUFFER 24
%define OUTPUT_SCALE 32
%define OUTPUT_ROTATION 40
%define OUTPUT_ICC_PROFILE 48
%define OUTPUT_VRR_ENABLED 56
%define OUTPUT_VRR_FLAGS 64
%define OUTPUT_VRR_CAPS 72
%define OUTPUT_VRR_MIN_REFRESH 80
%define OUTPUT_VRR_MAX_REFRESH 88
%define OUTPUT_MODES 96
%define OUTPUT_POSITION 104
%define OUTPUT_DAMAGE 112
%define OUTPUT_X 88
%define OUTPUT_Y 96
%define OUTPUT_WIDTH 104
%define OUTPUT_HEIGHT 112
%define OUTPUT_CONNECTED 120
%define OUTPUT_CONTROLLER 128
%define OUTPUT_CRTC_INDEX 136
%define OUTPUT_EDID 144
%define OUTPUT_HPD_IRQ 152
%define OUTPUT_HPD_REGISTER 160
%define OUTPUT_I2C_BUS 168
%define OUTPUT_CURRENT_SURFACE 176
%define OUTPUT_CURRENT_MODE 184
%define OUTPUT_SURFACES 192
%define OUTPUT_TOPLEVELS 200
%define OUTPUT_HOTPLUG_CALLBACK 208
%define OUTPUT_NEXT 216
%define OUTPUT_STRIDE 224
%define OUTPUT_FRAME_CLOCK 232
%define OUTPUT_DPMS_STATE 240
%define OUTPUT_DPMS_TIMEOUT 241
%define OUTPUT_GAMMA_LUT 248
%define OUTPUT_CONTROLLER_PTR 256

; SurfaceState (additional fields for compositor)
DEFINE_STRUCT_OFFSET SurfaceState, buffer, 0
DEFINE_STRUCT_OFFSET SurfaceState, damage, 8
DEFINE_STRUCT_OFFSET SurfaceState, pending, 16
DEFINE_STRUCT_OFFSET SurfaceState, buf_x, 24
DEFINE_STRUCT_OFFSET SurfaceState, buf_y, 32
DEFINE_STRUCT_OFFSET SurfaceState, input, 36
DEFINE_STRUCT_OFFSET SurfaceState, opaque, 44
DEFINE_STRUCT_OFFSET SurfaceState, width, 48
DEFINE_STRUCT_OFFSET SurfaceState, height, 56
DEFINE_STRUCT_OFFSET SurfaceState, transform, 64
DEFINE_STRUCT_OFFSET SurfaceState, scale, 72
DEFINE_STRUCT_OFFSET SurfaceState, frame_cbs, 80
DEFINE_STRUCT_OFFSET SurfaceState, subsurfaces, 88
DEFINE_STRUCT_OFFSET SurfaceState, stride, 96
%define SurfaceState_SIZE 104
%define SurfaceState.size 64
%define SurfaceState_size 64

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
DEFINE_STRUCT_OFFSET FrameClock, callbacks, 0
DEFINE_STRUCT_OFFSET FrameClock, next_vblank, 8
DEFINE_STRUCT_OFFSET FrameClock, refresh_ns, 16
%define FrameClock_SIZE 24
%define FrameClock.size 24
%define FrameClock_size 24

; All-caps aliases for FrameClock
%define FRAME_CLOCK_CALLBACKS 0
%define FRAME_CLOCK_NEXT_VBLANK 8
%define FRAME_CLOCK_REFRESH_NS 16

; Compositor
DEFINE_STRUCT_OFFSET Compositor, outputs, 0
DEFINE_STRUCT_OFFSET Compositor, damage, 8
DEFINE_STRUCT_OFFSET Compositor, frame_clock, 16
DEFINE_STRUCT_OFFSET Compositor, render_list, 24
DEFINE_STRUCT_OFFSET Compositor, bg_color, 32
DEFINE_STRUCT_OFFSET Compositor, cursor, 40
DEFINE_STRUCT_OFFSET Compositor, cursor_x, 48
DEFINE_STRUCT_OFFSET Compositor, cursor_y, 56
%define Compositor_SIZE 64
%define Compositor.size 64
%define Compositor_size 64

; All-caps aliases for Compositor
%define COMPOSITOR_OUTPUTS 0
%define COMPOSITOR_DAMAGE 8
%define COMPOSITOR_FRAME_CLOCK 16
%define COMPOSITOR_RENDER_LIST 24
%define COMPOSITOR_BG_COLOR 32
%define COMPOSITOR_CURSOR 40
%define COMPOSITOR_CURSOR_X 48
%define COMPOSITOR_CURSOR_Y 56

; RenderEntry
DEFINE_STRUCT_OFFSET RenderEntry, surface, 0
DEFINE_STRUCT_OFFSET RenderEntry, x, 8
DEFINE_STRUCT_OFFSET RenderEntry, y, 16
DEFINE_STRUCT_OFFSET RenderEntry, z, 24
DEFINE_STRUCT_OFFSET RenderEntry, alpha, 28
DEFINE_STRUCT_OFFSET RenderEntry, transform, 32
DEFINE_STRUCT_OFFSET RenderEntry, clip, 40
DEFINE_STRUCT_OFFSET RenderEntry, next, 48
%define RenderEntry_SIZE 56
%define RenderEntry.size 56
%define RenderEntry_size 56

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
DEFINE_STRUCT_OFFSET FrameCallback, surface, 0
DEFINE_STRUCT_OFFSET FrameCallback, seq, 8
DEFINE_STRUCT_OFFSET FrameCallback, timestamp, 16
DEFINE_STRUCT_OFFSET FrameCallback, next, 24
%define FrameCallback_SIZE 32
%define FrameCallback.size 32
%define FrameCallback_size 32

; ============================================================================
; Shell Structs
; ============================================================================

; Shell
DEFINE_STRUCT_OFFSET Shell, server, 0
DEFINE_STRUCT_OFFSET Shell, seat, 8
DEFINE_STRUCT_OFFSET Shell, arena, 16
DEFINE_STRUCT_OFFSET Shell, toplevels, 24
DEFINE_STRUCT_OFFSET Shell, popups, 32
DEFINE_STRUCT_OFFSET Shell, layers, 40
DEFINE_STRUCT_OFFSET Shell, workspaces, 48
DEFINE_STRUCT_OFFSET Shell, active_ws, 56
DEFINE_STRUCT_OFFSET Shell, workspace_count, 64
DEFINE_STRUCT_OFFSET Shell, configure_list, 72
DEFINE_STRUCT_OFFSET Shell, configure_count, 80
DEFINE_STRUCT_OFFSET Shell, policy, 88
DEFINE_STRUCT_OFFSET Shell, theme, 96
DEFINE_STRUCT_OFFSET Shell, outputs, 104
%define Shell_SIZE 112
%define Shell.size 112
%define Shell_size 112

; All-caps aliases for Shell
%define SHELL_SERVER 0
%define SHELL_SEAT 8
%define SHELL_ARENA 16
%define SHELL_TOPLEVELS 24
%define SHELL_POPUPS 32
%define SHELL_LAYERS 40
%define SHELL_WORKSPACES 48
%define SHELL_ACTIVE_WS 56
%define SHELL_ACTIVE_WS_IDX 60
%define SHELL_WORKSPACE_COUNT 64
%define SHELL_CONFIGURE_LIST 72
%define SHELL_CONFIGURE_COUNT 80
%define SHELL_POLICY 88
%define SHELL_THEME 96
%define SHELL_OUTPUTS 104
%define SHELL_CLIPBOARD 108
%define SHELL_PRIMARY_SELECTION 112
%define SHELL_DRAG_SOURCE 116
%define SHELL_DRAG_ICON 120
%define SHELL_DRAG_ACTIONS 124
%define SHELL_DRAG_SERIAL 128

; Toplevel
DEFINE_STRUCT_OFFSET Toplevel, surface, 0
DEFINE_STRUCT_OFFSET Toplevel, shell, 8
DEFINE_STRUCT_OFFSET Toplevel, title, 16
DEFINE_STRUCT_OFFSET Toplevel, app_id, 24
DEFINE_STRUCT_OFFSET Toplevel, state, 32
DEFINE_STRUCT_OFFSET Toplevel, pending_state, 36
DEFINE_STRUCT_OFFSET Toplevel, configure_serial, 40
DEFINE_STRUCT_OFFSET Toplevel, capabilities, 44
DEFINE_STRUCT_OFFSET Toplevel, pending_width, 48
DEFINE_STRUCT_OFFSET Toplevel, pending_height, 52
DEFINE_STRUCT_OFFSET Toplevel, saved_width, 56
DEFINE_STRUCT_OFFSET Toplevel, saved_height, 60
DEFINE_STRUCT_OFFSET Toplevel, decoration, 64
DEFINE_STRUCT_OFFSET Toplevel, x, 72
DEFINE_STRUCT_OFFSET Toplevel, y, 80
DEFINE_STRUCT_OFFSET Toplevel, width, 88
DEFINE_STRUCT_OFFSET Toplevel, height, 96
DEFINE_STRUCT_OFFSET Toplevel, next_ws, 104
DEFINE_STRUCT_OFFSET Toplevel, prev_ws, 112
DEFINE_STRUCT_OFFSET Toplevel, layout_node, 120
DEFINE_STRUCT_OFFSET Toplevel, output, 128
DEFINE_STRUCT_OFFSET Toplevel, workspace, 136
%define Toplevel_SIZE 144
%define Toplevel.size 144
%define Toplevel_size 144

; All-caps aliases for Toplevel
%define TOPLEVEL_SURFACE 0
%define TOPLEVEL_SHELL 8
%define TOPLEVEL_TITLE 16
%define TOPLEVEL_APP_ID 24
%define TOPLEVEL_STATE 32
%define TOPLEVEL_PENDING_STATE 36
%define TOPLEVEL_CONFIGURE_SERIAL 40
%define TOPLEVEL_CAPABILITIES 44
%define TOPLEVEL_PENDING_WIDTH 48
%define TOPLEVEL_PENDING_HEIGHT 52
%define TOPLEVEL_SAVED_WIDTH 56
%define TOPLEVEL_SAVED_HEIGHT 60
%define TOPLEVEL_DECORATION 64
%define TOPLEVEL_X 72
%define TOPLEVEL_Y 80
%define TOPLEVEL_WIDTH 88
%define TOPLEVEL_HEIGHT 96
%define TOPLEVEL_NEXT_WS 104
%define TOPLEVEL_PREV_WS 112
%define TOPLEVEL_LAYOUT_NODE 120
%define TOPLEVEL_OUTPUT 128
%define TOPLEVEL_WORKSPACE 136
%define TOPLEVEL_FRAME_CB 160

; Decoration
DEFINE_STRUCT_OFFSET Decoration, toplevel, 0
DEFINE_STRUCT_OFFSET Decoration, mode, 8
DEFINE_STRUCT_OFFSET Decoration, theme, 16
DEFINE_STRUCT_OFFSET Decoration, buttons, 24
DEFINE_STRUCT_OFFSET Decoration, button_count, 32
DEFINE_STRUCT_OFFSET Decoration, titlebar_h, 36
DEFINE_STRUCT_OFFSET Decoration, border_w, 40
DEFINE_STRUCT_OFFSET Decoration, frame_cb, 48
DEFINE_STRUCT_OFFSET Decoration, render_data, 56
%define Decoration_SIZE 64
%define Decoration.size 64
%define Decoration_size 64

; All-caps aliases for Decoration
%define DECORATION_TOPLEVEL 0
%define DECORATION_MODE 8
%define DECORATION_THEME 16
%define DECORATION_BUTTONS 24
%define DECORATION_BUTTON_COUNT 32
%define DECORATION_TITLEBAR_H 36
%define DECORATION_BORDER_W 40
%define DECORATION_FRAME_CB 48
%define DECORATION_RENDER_DATA 56

; DecorationButton
DEFINE_STRUCT_OFFSET DecorationButton, rect, 0
DEFINE_STRUCT_OFFSET DecorationButton, type, 16
DEFINE_STRUCT_OFFSET DecorationButton, state, 20
DEFINE_STRUCT_OFFSET DecorationButton, callback, 24
DEFINE_STRUCT_OFFSET DecorationButton, user_data, 32
%define DecorationButton_SIZE 40
%define DecorationButton.size 40
%define DecorationButton_size 40

; All-caps aliases for DecorationButton
%define DECOR_BTN_RECT 0
%define DECOR_BTN_TYPE 16
%define DECOR_BTN_STATE 20
%define DECOR_BTN_CALLBACK 24
%define DECOR_BTN_USER_DATA 32
%define DECOR_BTN_NEXT 40

; Workspace
DEFINE_STRUCT_OFFSET Workspace, output, 0
DEFINE_STRUCT_OFFSET Workspace, layout, 8
DEFINE_STRUCT_OFFSET Workspace, toplevels, 16
DEFINE_STRUCT_OFFSET Workspace, idx, 24
DEFINE_STRUCT_OFFSET Workspace, name, 32
%define Workspace_SIZE 40
%define Workspace.size 40
%define Workspace_size 40

; All-caps aliases for Workspace
%define WORKSPACE_OUTPUT 0
%define WORKSPACE_LAYOUT 8
%define WORKSPACE_TOPLEVELS 16
%define WORKSPACE_IDX 24
%define WORKSPACE_NAME 32
%define WORKSPACE_NEXT 48
%define WORKSPACE_SHELL 56

; Layer
DEFINE_STRUCT_OFFSET Layer, surface, 0
DEFINE_STRUCT_OFFSET Layer, shell, 8
DEFINE_STRUCT_OFFSET Layer, output, 16
DEFINE_STRUCT_OFFSET Layer, layer, 24
DEFINE_STRUCT_OFFSET Layer, namespace, 32
DEFINE_STRUCT_OFFSET Layer, anchor, 40
DEFINE_STRUCT_OFFSET Layer, exclusive_zone, 48
DEFINE_STRUCT_OFFSET Layer, keyboard_int, 52
DEFINE_STRUCT_OFFSET Layer, width, 56
DEFINE_STRUCT_OFFSET Layer, height, 60
DEFINE_STRUCT_OFFSET Layer, margin_top, 64
DEFINE_STRUCT_OFFSET Layer, margin_right, 68
DEFINE_STRUCT_OFFSET Layer, margin_bottom, 72
DEFINE_STRUCT_OFFSET Layer, margin_left, 76
DEFINE_STRUCT_OFFSET Layer, next, 80
%define Layer_SIZE 88
%define Layer.size 88
%define Layer_size 88

; Popup
DEFINE_STRUCT_OFFSET Popup, surface, 0
DEFINE_STRUCT_OFFSET Popup, shell, 8
DEFINE_STRUCT_OFFSET Popup, parent, 16
DEFINE_STRUCT_OFFSET Popup, position, 24
DEFINE_STRUCT_OFFSET Popup, x, 28
DEFINE_STRUCT_OFFSET Popup, y, 32
DEFINE_STRUCT_OFFSET Popup, width, 36
DEFINE_STRUCT_OFFSET Popup, height, 40
DEFINE_STRUCT_OFFSET Popup, constrain, 44
DEFINE_STRUCT_OFFSET Popup, next, 48
%define Popup_SIZE 56
%define Popup.size 56
%define Popup_size 56

; All-caps aliases for Popup
%define POPUP_SURFACE 0
%define POPUP_SHELL 8
%define POPUP_PARENT 16
%define POPUP_POSITION 24
%define POPUP_X 28
%define POPUP_Y 32
%define POPUP_WIDTH 36
%define POPUP_HEIGHT 40
%define POPUP_CONSTRAIN 44
%define POPUP_NEXT 48

; Configure
DEFINE_STRUCT_OFFSET Configure, serial, 0
DEFINE_STRUCT_OFFSET Configure, surface, 8
DEFINE_STRUCT_OFFSET Configure, width, 16
DEFINE_STRUCT_OFFSET Configure, height, 20
DEFINE_STRUCT_OFFSET Configure, states, 24
DEFINE_STRUCT_OFFSET Configure, callback, 28
DEFINE_STRUCT_OFFSET Configure, user_data, 36
DEFINE_STRUCT_OFFSET Configure, ack_callback, 44
DEFINE_STRUCT_OFFSET Configure, next, 52
%define Configure_SIZE 56
%define Configure.size 56
%define Configure_size 56

; All-caps aliases for Configure
%define CONFIGURE_SERIAL 0
%define CONFIGURE_SURFACE 8
%define CONFIGURE_WIDTH 16
%define CONFIGURE_HEIGHT 20
%define CONFIGURE_STATES 24
%define CONFIGURE_CALLBACK 28
%define CONFIGURE_USER_DATA 36
%define CONFIGURE_ACK_CALLBACK 44
%define CONFIGURE_NEXT 52

; DecorationDrawState
DEFINE_STRUCT_OFFSET DecorationDrawState, framebuffer, 0
DEFINE_STRUCT_OFFSET DecorationDrawState, stride, 8
DEFINE_STRUCT_OFFSET DecorationDrawState, width, 16
DEFINE_STRUCT_OFFSET DecorationDrawState, height, 20
DEFINE_STRUCT_OFFSET DecorationDrawState, titlebar_color, 24
DEFINE_STRUCT_OFFSET DecorationDrawState, border_color, 28
DEFINE_STRUCT_OFFSET DecorationDrawState, button_bg_color, 32
DEFINE_STRUCT_OFFSET DecorationDrawState, button_fg_color, 36
DEFINE_STRUCT_OFFSET DecorationDrawState, inactive_alpha, 40
%define DecorationDrawState_SIZE 48
%define DecorationDrawState.size 48
%define DecorationDrawState_size 48

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
DEFINE_STRUCT_OFFSET LayoutEngine, root, 0
DEFINE_STRUCT_OFFSET LayoutEngine, node_count, 8
DEFINE_STRUCT_OFFSET LayoutEngine, gap_size, 16
DEFINE_STRUCT_OFFSET LayoutEngine, master_ratio, 24
DEFINE_STRUCT_OFFSET LayoutEngine, smart_gaps, 32
DEFINE_STRUCT_OFFSET LayoutEngine, smart_borders, 40
DEFINE_STRUCT_OFFSET LayoutEngine, server, 48
%define LayoutEngine_SIZE 56
%define LayoutEngine.size 56
%define LayoutEngine_size 56

; All-caps aliases for LayoutEngine
%define LAYOUT_ENGINE_ROOT 0
%define LAYOUT_ENGINE_NODE_COUNT 8
%define LAYOUT_ENGINE_GAP_SIZE 16
%define LAYOUT_ENGINE_MASTER_RATIO 24
%define LAYOUT_ENGINE_SMART_GAPS 32
%define LAYOUT_ENGINE_SMART_BORDERS 40
%define LAYOUT_ENGINE_SERVER 48

; LayoutNode
DEFINE_STRUCT_OFFSET LayoutNode, type, 0
DEFINE_STRUCT_OFFSET LayoutNode, left, 8
DEFINE_STRUCT_OFFSET LayoutNode, right, 16
DEFINE_STRUCT_OFFSET LayoutNode, parent, 24
DEFINE_STRUCT_OFFSET LayoutNode, rect, 32
DEFINE_STRUCT_OFFSET LayoutNode, client, 40
DEFINE_STRUCT_OFFSET LayoutNode, ratio, 48
DEFINE_STRUCT_OFFSET LayoutNode, is_master, 56
DEFINE_STRUCT_OFFSET LayoutNode, toplevel, 64
DEFINE_STRUCT_OFFSET LayoutNode, x, 72
DEFINE_STRUCT_OFFSET LayoutNode, y, 80
DEFINE_STRUCT_OFFSET LayoutNode, width, 88
DEFINE_STRUCT_OFFSET LayoutNode, height, 96
DEFINE_STRUCT_OFFSET LayoutNode, gap, 104
%define LayoutNode_SIZE 112
%define LayoutNode.size 112
%define LayoutNode_size 112

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
DEFINE_STRUCT_OFFSET Policy, server, 0
DEFINE_STRUCT_OFFSET Policy, type, 4
DEFINE_STRUCT_OFFSET Policy, layout, 8
DEFINE_STRUCT_OFFSET Policy, configure, 16
DEFINE_STRUCT_OFFSET Policy, focus_change, 24
DEFINE_STRUCT_OFFSET Policy, kiosk_allowed_app, 28
DEFINE_STRUCT_OFFSET Policy, new_window, 32
DEFINE_STRUCT_OFFSET Policy, close_window, 40
DEFINE_STRUCT_OFFSET Policy, ws_changed, 48
DEFINE_STRUCT_OFFSET Policy, tile_window, 48
DEFINE_STRUCT_OFFSET Policy, window_configured, 56
%define Policy_SIZE 64
%define Policy.size 64
%define Policy_size 64

; All-caps aliases for Policy
%define POLICY_SERVER 0
%define POLICY_TYPE 4
%define POLICY_LAYOUT 8
%define POLICY_CONFIGURE 16
%define POLICY_FOCUS_CHANGE 24
%define POLICY_KIOSK_ALLOWED_APP 28
%define POLICY_NEW_WINDOW 32
%define POLICY_CLOSE_WINDOW 40
%define POLICY_WS_CHANGED 48
%define POLICY_TILE_WINDOW 48
%define POLICY_WINDOW_CONFIGURED 56

; Theme
DEFINE_STRUCT_OFFSET Theme, name, 0
DEFINE_STRUCT_OFFSET Theme, colors, 8
DEFINE_STRUCT_OFFSET Theme, font, 16
DEFINE_STRUCT_OFFSET Theme, font_size, 24
DEFINE_STRUCT_OFFSET Theme, border_width, 28
DEFINE_STRUCT_OFFSET Theme, border_radius, 32
DEFINE_STRUCT_OFFSET Theme, titlebar_height, 36
DEFINE_STRUCT_OFFSET Theme, button_size, 40
DEFINE_STRUCT_OFFSET Theme, padding, 44
%define Theme_SIZE 56
%define Theme.size 56
%define Theme_size 56

; All-caps aliases for Theme
%define THEME_NAME 0
%define THEME_COLORS 8
%define THEME_FONT 16
%define THEME_FONT_SIZE 24
%define THEME_BORDER_WIDTH 28
%define THEME_BORDER_RADIUS 32
%define THEME_TITLEBAR_HEIGHT 36
%define THEME_BUTTON_SIZE 40
%define THEME_PADDING 44

; ThemeColors
DEFINE_STRUCT_OFFSET ThemeColors, background, 0
DEFINE_STRUCT_OFFSET ThemeColors, foreground, 4
DEFINE_STRUCT_OFFSET ThemeColors, accent, 8
DEFINE_STRUCT_OFFSET ThemeColors, border, 12
DEFINE_STRUCT_OFFSET ThemeColors, titlebar_bg, 16
DEFINE_STRUCT_OFFSET ThemeColors, titlebar_fg, 20
DEFINE_STRUCT_OFFSET ThemeColors, button_bg, 24
DEFINE_STRUCT_OFFSET ThemeColors, button_fg, 28
DEFINE_STRUCT_OFFSET ThemeColors, button_hover_bg, 32
DEFINE_STRUCT_OFFSET ThemeColors, button_hover_fg, 36
DEFINE_STRUCT_OFFSET ThemeColors, button_pressed_bg, 40
DEFINE_STRUCT_OFFSET ThemeColors, button_pressed_fg, 44
%define ThemeColors_SIZE 48
%define ThemeColors.size 48
%define ThemeColors_size 48

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

%endif ; __STRUCT_OFFSETS_INC__
