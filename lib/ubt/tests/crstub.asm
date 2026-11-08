; =============================================================================
; Utkarsha OS — lib/ubt/tests/crstub.asm — what usign's P-256 file calls
; that the kernel provides and the host tests do not
; =============================================================================
; ecdsa_p256.asm (included for SMP's ECDH) also signs and makes its own
; keys, which need the kernel's random numbers and SHA-256. The Bluetooth
; code never takes those paths; here they fail if anything ever does.
; =============================================================================

section .text
global urand_get_bytes
global hmac_sha256
global sha256_hash
urand_get_bytes:
hmac_sha256:
sha256_hash:
    mov eax, -1
    ret
