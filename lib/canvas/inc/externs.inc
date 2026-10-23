; ============================================================================
; Common External Function Declarations
; Include this file to get extern declarations for common functions
; ============================================================================

%ifndef __EXTERNS_INC__
%define __EXTERNS_INC__

; Core allocator
extern arena_alloc
extern arena_alloc_aligned
extern arena_init
extern arena_create_child
extern arena_destroy_child
extern arena_free
extern arena_create
extern arena_destroy

; Memory operations
extern memcopy
extern memset
extern memcmp
extern blit_copy

; Codec operations
extern adaptive_encode
extern msgbuf_write
extern msgbuf_read
extern huff_build
extern huff_decode
extern lzw_decode_gif
extern deflate_compress
extern delta_compress
extern lz_compress
extern rle_compress
extern rle_decompress
extern rle_encode
extern rle_decode
extern delta_encode_tile
extern delta_decode_tile
extern siphash_init
extern siphash_update
extern siphash_final
extern siphash24
extern siphash24_verify
extern ut_entropy_siphash_key

; String operations
extern str_dup_arena
extern str_cmp
extern str_compare
extern str_copy
extern str_len

; Aliases for string functions
%define str_compare str_cmp
%define str_copy str_dup_arena

; Time
extern ut_time_now_ns
extern ut_time_ns_to_ms
extern ut_log_write

; Fence operations
extern fence_wait
extern fence_signal

; Backend init/deinit/modeset/flip
extern headless_init
extern backend_modeset
extern backend_dpms
extern headless_deinit
extern headless_modeset
extern headless_flip
extern headless_vblank_wait
extern headless_hotplug
extern headless_cursor
extern fb_linear_init
extern fb_linear_deinit
extern fb_linear_modeset
extern fb_linear_flip
extern fb_linear_vblank_wait
extern fb_linear_hotplug
extern fb_linear_cursor
extern native_init
extern native_deinit
extern native_modeset
extern native_flip
extern native_vblank_wait
extern native_hotplug
extern native_cursor
extern remote_backend_init
extern remote_backend_deinit
extern remote_backend_modeset
extern remote_backend_flip
extern remote_backend_vblank_wait
extern remote_backend_hotplug
extern remote_backend_cursor
extern virtual_output_create
extern virtual_output_destroy
extern rfb_server_update
extern crp_share_broadcast

; I2C
extern ut_i2c_read
extern ut_i2c_write

; EDID
extern ddc_read_edid
extern edid_parse
extern edid_find_preferred_mode

; Ring operations
extern ring_init
extern ring_push
extern ring_pop
extern ring_peek
extern ring_available
extern ring_free
extern ring_clear
extern arena_create
extern arena_destroy
extern rbtree_init
extern rbtree_insert
extern rbtree_remove
extern rbtree_find
extern rbtree_max
extern rbtree_min
extern handle_table_init
extern list_remove
extern list_push_back
extern list_pop_front
extern presentation_queue
extern list_init
extern policy_session_lock
extern policy_session_unlock
extern policy_decoration_mode

; Frame clock
extern frame_clock_schedule
extern frame_clock_schedule_vblank
extern output_schedule_vblank_vblank
extern frame_clock_init
extern output_schedule_vblank

; Buffer operations
extern canvas_buffer_create
extern canvas_buffer_destroy

; Client connection
extern canvas_connect
extern canvas_disconnect

; Surface operations
extern canvas_surface_create
extern canvas_surface_attach
extern canvas_surface_damage
extern canvas_surface_commit
extern canvas_surface_present
extern canvas_surface_destroy
extern commit_surface

; Present
extern canvas_present_wait

; Pixbuf
extern pixbuf_create
extern pixbuf_destroy

; Client clipboard
extern canvas_clipboard_set
extern canvas_clipboard_get

; Toplevel
extern canvas_toplevel_create
extern canvas_layer_create
extern toplevel_destroy
extern toplevel_schedule_configure

; Font
extern cmap_glyph_id
; Keymap
extern keymap_lookup_keysym
extern keymap_is_modifier
extern keymap_create_default
; Cursor
extern cursor_create_default
extern cmap_be16
extern outline_decode_points

; Security
extern audit_log
extern prompts_show
extern prompts_draw
extern prompts_wait
extern prompts_answer
extern prompts_cancel_client
; Client
extern client_disconnect
extern client_registry_init
extern client_registry_add
extern auth_send_caps

; Rect operations
extern rect_intersect
extern rect_copy
; Toplevel
extern toplevel_destroy
; Channel
extern channel_init
; Toplevel
extern toplevel_schedule_configure
; Handle
extern handle_resolve
extern handle_create
extern handle_destroy
; Region
extern region_init
extern region_destroy
extern region_contains_point
extern region_union
extern region_copy
extern region_add_rect
extern region_subtract_rect
extern region_clear
extern region_is_empty
extern surface_transform_rect
extern region_intersect_rect
extern region_intersect_rect
extern region_clear
extern region_is_empty

; GPU
extern gpu_ring_write
extern backend_vrr_enable
extern backend_vrr_disable
extern backend_vrr_set_range
extern gpu_ring_submit
extern gpu_mem_init
extern gpu_fence_init
extern gpu_ring_init
extern gfx9_emit_copy
extern gfx9_emit_fill
extern gpu_bo_create

; Security
extern containment_fault

; Image
extern fill_solid
; Input source
extern input_source_register
extern inflate
extern adler32
extern svg_probe
extern zlib_decompress
extern png_unfilter

; DRM formats
%define DRM_FORMAT_BGRA8888 0x41524742

; Security
%define CAP_DEBUG     1
extern gate_check

; Layer
extern canvas_layer_destroy
; Policy
extern cw_policy_external_init
extern cw_policy_floating_init
extern cw_policy_tiling_init
extern cw_policy_kiosk_init
extern cw_policy_iface_init
extern cw_policy_layout_init
extern cw_policy_layout_destroy
extern cw_policy_layout_add_window
extern cw_policy_layout_remove_window
extern cw_policy_layout_resize
extern cw_policy_layout_apply
extern policy_tile_window
; Output
extern output_set_mode
; Observability
extern trace_set_mask
extern trace_clear
extern metrics_snapshot
extern canvas_layer_set_position
extern canvas_layer_set_size
extern canvas_layer_set_buffer
extern canvas_layer_set_visible
extern canvas_layer_set_z

; Input grab
extern grab_pointer
extern grab_release
; Pointer
extern pointer_accel_create
; Constraints
extern constraints_create
; Input source
extern input_source_tv_init
; Filesystem
extern ut_fs_read
; Seat
extern seat_deliver_event

; Error codes (defined in errors.inc, but ensure they exist)
%ifndef ENOTSUP
%define ENOTSUP 95      ; Operation not supported
%endif

; Blend dispatch functions
extern blend_scalar
extern blend_sse2
extern blend_avx2
extern blend_avx512
extern blend_dispatch

; Network/TLS
extern ut_tls_write
extern ut_tls_read

; Surface and Layout management
extern surface_destroy
extern layout_destroy
extern surface_create
extern surface_set_position
extern surface_set_size
extern commit_surface

; Remote display
extern virtual_output_damage
extern rfb_tls_write_all
extern rfb_tls_read_all
extern clipboard_set

; Software rendering
extern sw_render_init
extern sw_render_deinit
extern sw_render_begin_frame
extern sw_render_surface
extern sw_render_rect
extern sw_render_end_frame
extern sw_render_flush
extern sw_render_version
extern direct_scanout_check
extern direct_scanout_enable
extern frame_clock_schedule
extern region_clear
extern region_is_empty

; Remote display
extern rfb_client_update
extern rfb_tls_write_all
extern rfb_tls_read_all
extern clipboard_set
extern output_create
extern tile_diff_init
extern tile_diff_update

; Software rendering
extern sw_render_init
extern sw_render_deinit
extern sw_render_begin_frame
extern sw_render_surface
extern sw_render_rect
extern sw_render_end_frame
extern sw_render_flush
extern sw_render_version
extern direct_scanout_check
extern direct_scanout_enable
extern frame_clock_schedule
extern region_clear
extern region_is_empty

; Remote display
extern rfb_client_update
extern rfb_tls_write_all
extern rfb_tls_read_all
extern clipboard_set
extern output_create
extern tile_diff_init
extern tile_diff_update

; Software rendering
extern sw_render_init
extern sw_render_deinit
extern sw_render_begin_frame
extern sw_render_surface
extern sw_render_rect
extern sw_render_end_frame
extern sw_render_flush
extern sw_render_version
extern direct_scanout_check
extern direct_scanout_enable
extern frame_clock_schedule
extern region_clear
extern region_is_empty

; Remote display
extern rfb_client_update
extern rfb_tls_write_all
extern rfb_tls_read_all
extern clipboard_set
extern output_create
extern tile_diff_init
extern tile_diff_update

; Software rendering
extern sw_render_init
extern sw_render_deinit
extern sw_render_begin_frame
extern sw_render_surface
extern sw_render_rect
extern sw_render_end_frame
extern sw_render_flush
extern sw_render_version
extern direct_scanout_check
extern direct_scanout_enable
extern frame_clock_schedule
extern region_clear
extern region_is_empty

; Remote display
extern rfb_client_update
extern rfb_tls_write_all
extern rfb_tls_read_all
extern clipboard_set
extern output_create
extern tile_diff_init
extern tile_diff_update

; Software rendering
extern sw_render_init
extern sw_render_deinit
extern sw_render_begin_frame
extern sw_render_surface
extern sw_render_rect
extern sw_render_end_frame
extern sw_render_flush
extern sw_render_version
extern direct_scanout_check
extern direct_scanout_enable
extern frame_clock_schedule
extern region_clear
extern region_is_empty

; Remote display
extern rfb_client_update
extern rfb_tls_write_all
extern rfb_tls_read_all
extern clipboard_set
extern output_create
extern tile_diff_init
extern tile_diff_update

; Software rendering
extern sw_render_init
extern sw_render_deinit
extern sw_render_begin_frame
extern sw_render_surface
extern sw_render_rect
extern sw_render_end_frame
extern sw_render_flush
extern sw_render_version
extern direct_scanout_check
extern direct_scanout_enable
extern frame_clock_schedule
extern region_clear
extern region_is_empty

; Remote display
extern rfb_client_update
extern rfb_tls_write_all
extern rfb_tls_read_all
extern clipboard_set
extern output_create
extern tile_diff_init
extern tile_diff_update

; Software rendering
extern sw_render_init
extern sw_render_deinit
extern sw_render_begin_frame
extern sw_render_surface
extern sw_render_rect
extern sw_render_end_frame
extern sw_render_flush
extern sw_render_version
extern direct_scanout_check
extern direct_scanout_enable
extern frame_clock_schedule
extern region_clear
extern region_is_empty

; Remote display
extern rfb_client_update
extern rfb_tls_write_all
extern rfb_tls_read_all
extern clipboard_set
extern output_create
extern tile_diff_init
extern tile_diff_update

; Geometry primitives
extern line_draw
extern line_intersect_rect
extern circle_draw
extern ellipse_draw
extern arc_draw
extern rounded_rect_draw
extern rounded_rect_stroke
extern triangle_draw
extern polygon_draw
extern scale_bilinear
extern quad_draw
extern rect_fill
extern circle_draw_quadrant
extern fixed_cos
extern fixed_sin

; Path tessellation
extern path_tessellate
extern path_bounds
extern path_length

; Polygon fill
extern polygon_fill

; Path rendering
extern path_render
extern path_render_gradient
extern path_render_pattern
extern path_hit_test

; Gradient primitives
extern gradient_create
extern gradient_add_stop
extern gradient_set_linear
extern gradient_set_radial
extern gradient_set_conical
extern gradient_set_matrix
extern gradient_interpolate
extern gradient_render_rect

; Stroke primitives
extern stroke_style_init
extern stroke_style_set_dash
extern stroke_render_line
extern stroke_render_path
extern stroke_join_miter
extern stroke_join_round
extern stroke_join_bevel
extern stroke_cap_round
extern stroke_cap_square
extern dash_pattern_get_length

; Font primitives
extern font_load_ttf
extern font_get_glyph
extern font_get_glyph_metrics
extern font_face_create
extern font_render_glyph
extern font_render_text
extern font_kerning
extern glyph_cache_get
extern glyph_cache_put

; Font rasterization
extern glyph_rasterize

; Font text layout
extern text_layout_create
extern text_layout_set_text
extern text_layout_draw
extern text_layout_get_bounds
extern font_render_glyph_run

; PNG codec
extern png_probe
extern png_decode
extern png_decompress_idat
extern image_sniff
extern image_decode
extern qoi_decode
extern tga_decode
extern pnm_decode
extern farbfeld_decode
extern raw_decode
extern sensor_process
extern dng_decode
extern pcx_decode
extern ico_decode
extern tiff_decode
extern dds_decode
extern ktx_decode
extern ktx2_decode
extern bc_decode
extern hdr_decode
extern exr_decode
extern psd_decode
extern camera_probe
extern camera_decode
extern modern_probe
extern webp_probe
extern webp_decode
extern webp_vp8l_decode
extern webp_decode_image
extern webp_bool_init
extern webp_bool_get
extern webp_bool_literal
extern webp_vp8_inspect
extern webp_vp8_parse_config
extern webp_vp8_parse_partitions
extern webp_vp8_decode_token
extern webp_vp8_decode_block
extern webp_vp8_update_probs
extern webp_vp8_coeff_probs_init
extern webp_vp8_coeff_probs_update
extern webp_vp8_decode_macroblock_residual
extern webp_vp8_quant_factors
extern webp_vp8_dequant_block
extern webp_vp8_dequant_macroblock
extern webp_vp8_decode_keyframe_base_modes
extern webp_vp8_decode_bmode
extern webp_vp8_decode_bpred_modes
extern webp_vp8_decode_mb_header
extern webp_vp8_idct4x4
extern webp_vp8_iwht4x4
extern webp_vp8_add_block
extern webp_vp8_predict_block
extern webp_vp8_predict4x4
extern webp_vp8_reconstruct_macroblock
extern webp_vp8_predict_macroblock
extern webp_vp8_alloc_frame_planes
extern webp_vp8_render_macroblock
extern webp_vp8_decode
extern webp_vp8_filter_sample
extern webp_vp8_filter_edge
extern webp_vp8_filter_frame
extern webp_alpha_apply_raw
extern webp_vp8_yuv420_to_bgra
extern webp_inspect
extern webp_inspect_animation
extern webp_composite_frame
extern webp_dispose_background
extern webp_decode_animation
extern webp_bits_init
extern webp_bits_get
extern webp_huff_build
extern webp_huff_decode
extern webp_huff_read
extern webp_huff_group_read
extern webp_prefix_value
extern webp_copy_pixels
extern webp_color_cache_index
extern webp_huff_group_decode_literals
extern webp_distance_value
extern webp_huff_group_decode
extern webp_huff_group_decode_one
extern webp_huff_groups_decode
extern webp_inverse_subtract_green
extern webp_inverse_color
extern webp_inverse_color_index
extern webp_palette_expand
extern webp_predict_basic
extern webp_predict_pixel
extern webp_inverse_predictor

; Tools
extern debug_scene_dump
extern record_start
extern record_stop
extern replay_run_file
extern trace_set_mask
extern debug_client_list
extern debug_surface_list
extern debug_layer_list

; CTS/Testing functions
extern canvas_get_caps
extern surface_create
extern surface_set_position
extern surface_set_size
extern commit_surface
extern canvas_surface_destroy
extern handle_resolve
extern memcopy
extern output_layout_apply
extern wire_validate_message
extern wire_decode_header
extern wire_decode_handles
extern gif_probe
extern fuzz_target_png
extern fuzz_target_jpeg
extern fuzz_target_gif
extern fuzz_target_ttf
extern fuzz_target_icc
extern fuzz_target_rfb
extern fuzz_target_wire
extern fuzz_target_keymap
extern fuzz_target_config
extern fuzz_target_png
extern fuzz_target_jpeg
extern fuzz_target_gif
extern fuzz_target_ttf
extern fuzz_target_icc
extern fuzz_target_rfb
extern surface_create
extern surface_set_position
extern surface_set_size
extern commit_surface
extern canvas_surface_destroy
extern handle_resolve
extern memcopy
extern output_layout_apply
extern wire_validate_message
extern wire_decode_header
extern wire_decode_handles
extern gif_probe
extern debug_scene_dump
extern record_start
extern record_stop
extern replay_run_file
extern trace_set_mask
extern debug_client_list
extern debug_surface_list
extern debug_layer_list
extern composer_composite

; Path tessellation
extern path_tessellate
extern path_bounds
extern path_length

; Polygon fill
extern polygon_fill

; Path rendering
extern path_render
extern path_render_gradient
extern path_render_pattern
extern path_hit_test

; Font rasterization
extern glyph_rasterize

; Text layout
extern text_layout_create
extern text_layout_set_text
extern text_layout_draw
extern text_layout_get_bounds
extern font_render_glyph_run

; Image transforms
extern image_scale
extern image_rotate
extern image_transform

; GPU acceleration (AMD GFX9)
extern gpu_renderer_init
extern gpu_renderer_deinit
extern gpu_path_tessellate
extern gpu_gradient_render
extern gpu_image_scale
extern gpu_composite
extern gpu_submit_commands
extern gpu_wait_idle
extern gpu_get_stats

; Core allocator (needed by many modules)
extern arena_alloc
extern arena_alloc_aligned
extern arena_init
extern arena_create_child
extern arena_destroy_child
extern arena_free
extern arena_create
extern arena_destroy

; Memory operations
extern memcopy
extern memset
extern memcmp
extern blit_copy

; GPU operations
extern gpu_ring_write
extern gpu_fence_init

; Backend operations
extern backend_modeset
extern backend_dpms
extern backend_flip
extern backend_vblank_wait
extern backend_hotplug
extern backend_cursor
extern canvas_get_caps
extern surface_create
extern surface_set_position
extern surface_set_size
extern commit_surface
extern canvas_surface_destroy
extern handle_resolve
extern output_layout_apply

; Compositor
extern damage_init
extern damage_destroy
extern damage_add_rect
extern damage_get_rects
extern damage_clear
extern damage_intersect_rect

extern output_create
extern output_destroy
extern output_set_mode
extern output_dpms
extern output_set_scale
extern output_set_rotation
extern output_schedule_frame
extern output_get_info

extern surface_state_init
extern surface_state_destroy
extern surface_attach_buffer
extern surface_damage
extern surface_commit
extern surface_get_buffer
extern surface_get_size
extern surface_set_transform
extern surface_set_scale
extern frame_callback_init

extern frame_clock_init
extern frame_clock_deinit
extern frame_clock_schedule
extern frame_clock_schedule_vblank
extern frame_clock_vblank_handler
extern frame_clock_get_refresh
extern frame_clock_set_refresh

extern compositor_init
extern compositor_destroy
extern compositor_add_output
extern compositor_remove_output
extern compositor_composite
extern compositor_set_cursor
extern compositor_move_cursor
extern compositor_set_background
extern compositor_raise_surface
extern compositor_focus_surface
extern seat_set_focus

; Shell
extern toplevel_create
extern toplevel_destroy
extern toplevel_set_state
extern toplevel_get_state
extern toplevel_set_title
extern toplevel_set_app_id
extern toplevel_schedule_configure
extern toplevel_configure
extern toplevel_set_position
extern toplevel_get_size
extern toplevel_is_maximized
extern toplevel_is_fullscreen
extern toplevel_is_tiled

extern decoration_create_for_toplevel
extern decoration_destroy
extern decoration_set_mode
extern decoration_get_titlebar_height
extern decoration_get_border_width
extern decoration_hit_test
extern decoration_render
extern decoration_button_callback

extern workspace_create
extern workspace_destroy
extern workspace_set_active
extern workspace_get_active
extern workspace_add_toplevel
extern workspace_remove_toplevel
extern workspace_get_toplevels

extern layer_create
extern layer_destroy
extern layer_set_anchor
extern layer_set_exclusive_zone
extern layer_set_keyboard_interactivity
extern layer_set_size
extern layer_set_margin
extern layer_get_output

extern popup_create
extern popup_destroy
extern popup_set_position
extern popup_set_size
extern popup_set_constrain
extern popup_get_position
extern popup_constrain_to_output

extern layout_engine_create
extern layout_engine_destroy
extern layout_add_toplevel
extern layout_remove_toplevel
extern layout_apply
extern layout_resize
extern layout_set_master_ratio
extern layout_set_gap
extern layout_toggle_smart_gaps
extern layout_toggle_smart_borders

extern policy_init
extern policy_floating_init
extern policy_tiling_init
extern policy_kiosk_init
extern policy_external_init
extern policy_iface_init

extern configure_create
extern configure_destroy
extern configure_ack
extern configure_set_size
extern configure_set_states
extern configure_set_serial

extern shell_create
extern shell_destroy
extern shell_get_toplevel_at
extern shell_focus_toplevel
extern shell_get_active_toplevel
extern shell_new_toplevel
extern shell_close_toplevel
extern shell_maximize_toplevel
extern shell_fullscreen_toplevel
extern shell_set_policy
extern shell_get_toplevels
extern shell_get_popups
extern shell_get_layers
extern shell_get_outputs

%endif ; __EXTERNS_INC__
