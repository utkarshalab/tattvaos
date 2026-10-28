; UXFS bounded persistent volume v2. Private format, not the legacy v1 scaffold.
%ifndef UXFS_VOLUME_INC
%define UXFS_VOLUME_INC
%define UV_NODES 64
%define UV_NODE 4352
%define UV_DATA 256
%define UV_TYPE 240
%define UV_SIZE 248
%define UV_BYTES (UV_NODES*UV_NODE)
%define UV_SECTORS (UV_BYTES/512)
%define UV_BANK (UV_SECTORS+1)
%define UV_MAGIC 0x32564c4f56584655 ; UFXVOLV2, little endian
%endif
