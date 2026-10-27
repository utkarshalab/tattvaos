%ifndef VCS_SYNC_PROTOCOL_INC
%define VCS_SYNC_PROTOCOL_INC

%define VS_REQ_MAGIC 0x3151455253435655 ; UVCSREQ1
%define VS_RES_MAGIC 0x3153455253435655 ; UVCSRES1
%define VS_VERSION   1
%define VS_MESSAGE   96

%define VS_MAGIC     0
%define VS_VERSION_O 8
%define VS_OPERATION 12
%define VS_FLAGS     16
%define VS_COUNT     24
%define VS_DIGEST    32
%define VS_REF       64
%define VS_REF_BYTES 32

%define VS_OP_FETCH  1
%define VS_OP_PUSH   2
%define VS_OP_CLONE  3
%define VS_CAP_RESUME 1
%define VS_CAP_SIGNED 2
%define VS_CAP_V1 (VS_CAP_RESUME | VS_CAP_SIGNED)

%endif
