; ============================================================================
; Trace Event IDs — Shared Trace/Debug Event Definitions
; ============================================================================

%ifndef __TRACE_INC__
%define __TRACE_INC__

; Core lifecycle
%define TRACE_CLIENT_CONNECT       1
%define TRACE_CLIENT_DISCONNECT    2
%define TRACE_CAPS_GRANT           3
%define TRACE_CAPS_DENY            4

; Protocol
%define TRACE_MSG_RECV             10
%define TRACE_MSG_SEND             11
%define TRACE_MSG_DISPATCH         12
%define TRACE_PROTO_ERROR          13

; Buffers / sync
%define TRACE_BUFFER_CREATE        20
%define TRACE_BUFFER_DESTROY       21
%define TRACE_BUFFER_ATTACH        22
%define TRACE_FENCE_SIGNAL         23
%define TRACE_FENCE_WAIT           24
%define TRACE_TIMELINE_SIGNAL      25
%define TRACE_TIMELINE_WAIT        26

; Surfaces / commit
%define TRACE_SURFACE_CREATE       30
%define TRACE_SURFACE_DESTROY      31
%define TRACE_SURFACE_COMMIT       32
%define TRACE_FRAME_CALLBACK       33
%define TRACE_DAMAGE               34

; Render / output
%define TRACE_COMPOSITE_BEGIN      40
%define TRACE_COMPOSITE_END        41
%define TRACE_FLIP                 42
%define TRACE_VBLANK               43
%define TRACE_PRESENT              44
%define TRACE_DIRECT_SCANOUT       45

; Input
%define TRACE_INPUT_EVENT          50
%define TRACE_FOCUS_CHANGE         51
%define TRACE_GRAB                 52

; Shell / policy
%define TRACE_TOPLEVEL_CREATE      60
%define TRACE_TOPLEVEL_DESTROY     61
%define TRACE_CONFIGURE            62
%define TRACE_CONFIGURE_ACK        63

; Governance / security
%define TRACE_QUOTA_EXCEEDED       70
%define TRACE_RATE_EXCEEDED        71
%define TRACE_WATCHDOG_KILL        72
%define TRACE_FAULT_CONTAINED      73
%define TRACE_AUDIT                74

%endif ; __TRACE_INC__
