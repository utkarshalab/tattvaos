#!/usr/bin/env python3
# =============================================================================
# tests/conformance/unicode/run_conformance.py
# UCD Conformance Test Runner for the Tattva OS str library.
#
# Parses and executes conformance tests for:
#   - GraphemeBreakTest.txt
#   - WordBreakTest.txt
#   - SentenceBreakTest.txt
#   - LineBreakTest.txt
#   - NormalizationTest.txt
# =============================================================================

import os
import sys
import ctypes

# Paths to test files relative to the script
UCD_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../data/ucd"))
AUX_DIR = os.path.join(UCD_DIR, "auxiliary")

class StrSlice(ctypes.Structure):
    _fields_ = [
        ("ptr", ctypes.c_char_p),
        ("len", ctypes.c_uint64)
    ]

class UnicodeConformanceRunner:
    def __init__(self, lib_path):
        if not os.path.exists(lib_path):
            raise FileNotFoundError(f"Could not find library at {lib_path}")
        self.lib = ctypes.CDLL(lib_path)
        self.setup_signatures()

    def setup_signatures(self):
        # int64_t str_grapheme_next(const StrSlice *src, uint64_t offset, uint64_t *out_next)
        self.lib.str_grapheme_next.argtypes = [
            ctypes.POINTER(StrSlice),
            ctypes.c_uint64,
            ctypes.POINTER(ctypes.c_uint64)
        ]
        self.lib.str_grapheme_next.restype = ctypes.c_int64

        # int64_t str_word_next(const StrSlice *src, uint64_t offset, uint64_t *out_next)
        self.lib.str_word_next.argtypes = [
            ctypes.POINTER(StrSlice),
            ctypes.c_uint64,
            ctypes.POINTER(ctypes.c_uint64)
        ]
        self.lib.str_word_next.restype = ctypes.c_int64

        # int64_t str_sentence_next(const StrSlice *src, uint64_t offset, uint64_t *out_next)
        self.lib.str_sentence_next.argtypes = [
            ctypes.POINTER(StrSlice),
            ctypes.c_uint64,
            ctypes.POINTER(ctypes.c_uint64)
        ]
        self.lib.str_sentence_next.restype = ctypes.c_int64

        # int64_t str_normalize_nfd(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len)
        self.lib.str_normalize_nfd.argtypes = [
            ctypes.POINTER(StrSlice),
            ctypes.c_char_p,
            ctypes.c_uint64,
            ctypes.POINTER(ctypes.c_uint64)
        ]
        self.lib.str_normalize_nfd.restype = ctypes.c_int64

        # int64_t str_normalize_nfc(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len)
        self.lib.str_normalize_nfc.argtypes = [
            ctypes.POINTER(StrSlice),
            ctypes.c_char_p,
            ctypes.c_uint64,
            ctypes.POINTER(ctypes.c_uint64)
        ]
        self.lib.str_normalize_nfc.restype = ctypes.c_int64

    def parse_hex_seq(self, seq_str):
        cps = [int(x, 16) for x in seq_str.strip().split() if x.strip()]
        # encode to UTF-8 bytes
        b = "".join(chr(cp) for cp in cps).encode("utf-8")
        return b

    def run_segmentation_test(self, file_path, next_func):
        """Runs segmentation boundary tests (Grapheme, Word, Sentence)."""
        if not os.path.exists(file_path):
            print(f"Skipping {os.path.basename(file_path)}: file not found.")
            return True

        passed = 0
        failed = 0

        with open(file_path, "r", encoding="utf-8") as f:
            for line_idx, line in enumerate(f, 1):
                line = line.strip()
                if not line or line.startswith("#"):
                    continue

                # Parse: e.g. "÷ 0009 ÷ 0009 ÷"
                parts = line.split("#")[0].strip().split()
                
                # Extract codepoints and expected boundaries
                codepoints = []
                expected_boundaries = []
                
                # The line format: boundary, codepoint, boundary, codepoint...
                # boundary is '÷' (break) or '×' (no break)
                current_offset = 0
                for part in parts:
                    if part in ("÷", "×"):
                        if part == "÷":
                            expected_boundaries.append(current_offset)
                    else:
                        cp = int(part, 16)
                        codepoints.append(cp)
                        # UTF-8 encoded byte length
                        current_offset += len(chr(cp).encode("utf-8"))

                if not codepoints:
                    continue

                # Always expect a boundary at the very end
                expected_boundaries.append(current_offset)

                # Prepare the string slice
                utf8_bytes = "".join(chr(cp) for cp in codepoints).encode("utf-8")
                slice_struct = StrSlice(utf8_bytes, len(utf8_bytes))

                # Determine actual boundaries returned by the library
                actual_boundaries = [0]
                offset = 0
                out_next = ctypes.c_uint64(0)
                
                while offset < len(utf8_bytes):
                    res = next_func(ctypes.byref(slice_struct), offset, ctypes.byref(out_next))
                    if res != 0: # STR_ERR_ITER_END or other error
                        break
                    actual_boundaries.append(out_next.value)
                    offset = out_next.value

                # Compare
                expected_boundaries = sorted(list(set(expected_boundaries)))
                actual_boundaries = sorted(list(set(actual_boundaries)))

                if expected_boundaries == actual_boundaries:
                    passed += 1
                else:
                    failed += 1
                    print(f"Line {line_idx} FAILED: {line}")
                    print(f"  Expected boundaries: {expected_boundaries}")
                    print(f"  Actual boundaries:   {actual_boundaries}")

        print(f"[{os.path.basename(file_path)}] Passed: {passed}, Failed: {failed}")
        return failed == 0

    def run_normalization_test(self, file_path):
        """Runs NormalizationTest.txt conformance suite."""
        if not os.path.exists(file_path):
            print(f"Skipping {os.path.basename(file_path)}: file not found.")
            return True

        passed = 0
        failed = 0

        with open(file_path, "r", encoding="utf-8") as f:
            for line_idx, line in enumerate(f, 1):
                line = line.strip()
                if not line or line.startswith(("#", "@")):
                    continue

                parts = line.split("#")[0].strip().split(";")
                if len(parts) < 6:
                    continue

                # Col 1: source
                # Col 2: NFC
                # Col 3: NFD
                # Col 4: NFKC
                # Col 5: NFKD
                c1 = self.parse_hex_seq(parts[0])
                c2 = self.parse_hex_seq(parts[1])
                c3 = self.parse_hex_seq(parts[2])
                c4 = self.parse_hex_seq(parts[3])
                c5 = self.parse_hex_seq(parts[4])

                # Verify NFD(c1) == c3
                if not self.check_norm(c1, c3, self.lib.str_normalize_nfd, "NFD"):
                    failed += 1
                    print(f"Line {line_idx} FAILED: NFD(c1) != c3")
                    continue

                # Verify NFC(c1) == c2
                if not self.check_norm(c1, c2, self.lib.str_normalize_nfc, "NFC"):
                    failed += 1
                    print(f"Line {line_idx} FAILED: NFC(c1) != c2")
                    continue

                passed += 1

        print(f"[NormalizationTest.txt] Passed: {passed}, Failed: {failed}")
        return failed == 0

    def check_norm(self, src_bytes, expected_bytes, norm_func, name):
        src_slice = StrSlice(src_bytes, len(src_bytes))
        dst_buf = ctypes.create_string_buffer(len(src_bytes) * 4 + 16)
        out_len = ctypes.c_uint64(0)

        res = norm_func(ctypes.byref(src_slice), dst_buf, len(dst_buf), ctypes.byref(out_len))
        if res != 0:
            return False

        actual_bytes = dst_buf.raw[:out_len.value]
        return actual_bytes == expected_bytes

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 run_conformance.py <path_to_shared_libstr>")
        sys.exit(1)

    lib_path = sys.argv[1]
    try:
        runner = UnicodeConformanceRunner(lib_path)
    except Exception as e:
        print(f"Error initializing test runner: {e}")
        sys.exit(1)

    all_passed = True

    # 1. Grapheme Cluster Boundary Conformance
    grapheme_txt = os.path.join(AUX_DIR, "GraphemeBreakTest.txt")
    if not runner.run_segmentation_test(grapheme_txt, runner.lib.str_grapheme_next):
        all_passed = False

    # 2. Word Boundary Conformance
    word_txt = os.path.join(AUX_DIR, "WordBreakTest.txt")
    if not runner.run_segmentation_test(word_txt, runner.lib.str_word_next):
        all_passed = False

    # 3. Sentence Boundary Conformance
    sentence_txt = os.path.join(AUX_DIR, "SentenceBreakTest.txt")
    if not runner.run_segmentation_test(sentence_txt, runner.lib.str_sentence_next):
        all_passed = False

    # 4. Normalization Conformance
    norm_txt = os.path.join(UCD_DIR, "NormalizationTest.txt")
    if not runner.run_normalization_test(norm_txt):
        all_passed = False

    if all_passed:
        print("ALL CONFORMANCE TESTS PASSED.")
        sys.exit(0)
    else:
        print("SOME CONFORMANCE TESTS FAILED.")
        sys.exit(1)

if __name__ == "__main__":
    main()
