# Decision 0011: Defer AVIF, HEIF, and JPEG XL Decoding

**Status**: Accepted
**Date**: 2026-10-21
**Phase**: Post-v0.1

## Context

Canvas already has native decoders for the image formats needed by the early
desktop, shell, UI, diagnostics, and camera pipeline. AVIF, HEIF, and JPEG XL
require substantially larger codec stacks and conformance work than the value
they provide to the near-term Utkarsha OS display-server milestones.

## Decision

Defer AVIF, HEIF, and JPEG XL pixel decoding. Keep their format identifiers and
bounded signature/container probes so callers can identify the input, but make
no claim that `image_decode` supports them. The generic decoder continues to
return null for these recognized-but-unsupported formats.

No external codec library, compatibility ABI, or hosted-process bridge will be
introduced. Future implementations remain native Utkarsha OS assembly modules.

## Current Behavior

- `modern_probe` recognizes AVIF/AVIS brands, common HEIF brands, raw JPEG XL,
  and the JPEG XL container signature.
- `image_sniff` returns `IMAGE_FMT_AVIF`, `IMAGE_FMT_HEIF`, or `IMAGE_FMT_JXL`.
- `image_decode` returns null for all three formats.
- PNG, JPEG, GIF, WebP, camera RAW, and the other existing native formats remain
  the supported paths for current product work.

## Consequences

- Engineering time moves to display-server reliability, rendering, policy,
  sessions, input, accessibility, remote display, and testing.
- Applications can diagnose unsupported modern-image input accurately instead
  of misidentifying it.
- Files using these codecs must be converted to a supported format before use.

## Revisit Criteria

Implement one codec at a time only when at least one condition is met:

1. A first-party Utkarsha OS application has a demonstrated requirement.
2. A deployment workload contains enough real files to justify the footprint.
3. The decoder can be fuzzed and tested against a meaningful conformance corpus.
4. Higher-priority Canvas and boot/kernel milestones are no longer blocked.

Priority when revisited is determined by measured workload demand, not format
popularity. AVIF and HEIF may share ISO-BMFF parsing, but their pixel codecs and
tests remain separately gated; JPEG XL remains an independent implementation.

## Related

- `../PLAN.md` Track H hardening requirements
- `../../src/img/modern.asm` bounded format probes
- `../../src/img/sniff.asm` unified image dispatch

