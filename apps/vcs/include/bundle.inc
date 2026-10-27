%ifndef VCS_BUNDLE_INC
%define VCS_BUNDLE_INC

; Portable repository-object payload carried inside the signed wire frame.
%define VB_MAGIC       0x31444e4253435655 ; UVCSBND1
%define VB_VERSION     1
%define VB_HEADER      96
%define VB_RECORD      24
%define VB_MAX_RECORDS 18               ; commit + hash + signature + 15 blobs

%define VBH_MAGIC      0
%define VBH_VERSION    8
%define VBH_TOTAL      16
%define VBH_RECORDS    24
%define VBH_TIP        32
%define VBH_PARENT     40
%define VBH_PARENT_HASH 48
%define VBH_FLAGS      80
%define VBH_RESERVED   88

%define VBR_KIND       0
%define VBR_ID         8
%define VBR_SIZE       16

%define VB_KIND_COMMIT 1
%define VB_KIND_HASH   2
%define VB_KIND_SIGN   3
%define VB_KIND_BLOB   4
%define VB_FLAG_SIGNED 1
%define VB_MAP_MAGIC   0x3150414d53435655 ; UVCSMAP1

%endif
