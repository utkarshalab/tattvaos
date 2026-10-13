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

; Memory operations
extern memcopy
extern memset
extern memcmp
extern blit_copy

; String operations
extern str_dup_arena
extern str_cmp
extern str_len

; Time
extern tv_time_now_ns
extern tv_time_ns_to_ms

; Fence operations
extern fence_wait
extern fence_signal

; Backend init/deinit/modeset/flip
extern headless_init
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

; I2C
extern tv_i2c_read
extern tv_i2c_write

; EDID
extern ddc_read_edid
extern edid_parse
extern edid_find_preferred_mode

; Pixbuf
extern pixbuf_create

; Error codes (defined in errors.inc, but ensure they exist)
%ifndef ENOTSUP
%define ENOTSUP 95      ; Operation not supported
%endif

%endif ; __EXTERNS_INC__