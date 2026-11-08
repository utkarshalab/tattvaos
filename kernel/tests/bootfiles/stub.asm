; =============================================================================
; kernel/tests/bootfiles/stub.asm — kernel/exec/bootfiles.asm for host tests
; =============================================================================
; The ACPI kernel stub (console, boot information, phys_state), SHA-256,
; SHA-512, Ed25519 (with a random source that always fails: nothing here
; makes keys), the UPK verifier, then the boot files.
; =============================================================================

%include "lib/io/acpi/aml/tests/kstub.asm"

section .text
global urand_get_bytes                  ; key generation only: not used here
urand_get_bytes:
    mov eax, -1
    ret

%include "lib/crypto/uhash/sha256/sha256.asm"
%include "lib/crypto/uhash/sha512/sha512.asm"
%include "lib/crypto/usign/ed25519/ed25519.asm"
%include "pkg/format/upk.asm"
%include "kernel/exec/bootfiles.asm"
