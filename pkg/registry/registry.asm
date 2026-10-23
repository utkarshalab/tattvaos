%ifndef GUARD_PKG_REGISTRY_REGISTRY_ASM
%define GUARD_PKG_REGISTRY_REGISTRY_ASM
; =============================================================================
; File     : pkg/registry/registry.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Package registry — package registry for installed packages.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; pkg_registry_init — Initialize package registry
; Input:  none
; Output: rax = 0 on success
; -----------------------------------------------------------------------------
global pkg_registry_init
pkg_registry_init:
    ret

; -----------------------------------------------------------------------------
; pkg_registry_install — Register a newly installed package
; Input:  rdi = package name, rsi = version, rdx = install path
; Output: rax = 0 on success
; -----------------------------------------------------------------------------
global pkg_registry_install
pkg_registry_install:
    ret

%endif ; GUARD_PKG_REGISTRY_REGISTRY_ASM