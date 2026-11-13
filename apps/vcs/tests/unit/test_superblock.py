"""Format-v3 superblock sealing, verification, and recovery tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, CORRUPT, CONFLICT = 0, 5, 6


class Selection(ctypes.Structure):
    _fields_ = [
        ("first", P),
        ("second", P),
        ("result", P),
        ("result_generation", ctypes.c_uint64),
    ]


lib.vcs_superblock_seal.argtypes = [P]
lib.vcs_superblock_seal.restype = ctypes.c_uint64
lib.vcs_superblock_verify.argtypes = [P]
lib.vcs_superblock_verify.restype = ctypes.c_uint64
lib.vcs_superblock_select_latest.argtypes = [ctypes.POINTER(Selection)]
lib.vcs_superblock_select_latest.restype = ctypes.c_uint64


def valid_image(features=3, generation=27, operation_sequence=91,
                next_transaction=103, created_ns=0):
    image = bytearray(512)
    image[:8] = b"UVCSREP3"
    struct.pack_into("<IIQQ", image, 8, 3, 512, features, generation)
    image[32:48] = bytes.fromhex("00112233445566778899aabbccddeeff")
    struct.pack_into("<II", image, 48, 1, 4096)
    image[56:88] = hashlib.sha256(b"head commit").digest()
    image[88:120] = hashlib.sha256(b"ref catalog").digest()
    image[120:152] = hashlib.sha256(b"ownership catalog").digest()
    image[184:216] = hashlib.sha256(b"object index").digest()
    struct.pack_into("<QQq", image, 248, operation_sequence,
                     next_transaction, created_ns)
    return image


def sealed(image):
    buffer = (ctypes.c_ubyte * 512).from_buffer(image)
    assert lib.vcs_superblock_seal(buffer) == OK
    return buffer


def select(first, second, result=0x1234, generation=0x5678):
    first_buffer = ((ctypes.c_ubyte * 512).from_buffer(first)
                    if first is not None else None)
    second_buffer = ((ctypes.c_ubyte * 512).from_buffer(second)
                     if second is not None else None)
    request = Selection(first_buffer, second_buffer,
                        ctypes.cast(result, P), generation)
    status = lib.vcs_superblock_select_latest(ctypes.byref(request))
    return status, request, first_buffer, second_buffer


image = valid_image()
buffer = (ctypes.c_ubyte * 512).from_buffer(image)
assert lib.vcs_superblock_seal(buffer) == OK
assert bytes(image[480:]) == hashlib.sha256(image[:480]).digest()
assert lib.vcs_superblock_verify(buffer) == OK

with_operation = valid_image(0x0B)
with_operation[152:184] = hashlib.sha256(b"operation head").digest()
operation_buffer = (ctypes.c_ubyte * 512).from_buffer(with_operation)
assert lib.vcs_superblock_seal(operation_buffer) == OK
assert lib.vcs_superblock_verify(operation_buffer) == OK

mutations = [
    (0, b"X"), (8, struct.pack("<I", 2)), (12, struct.pack("<I", 511)),
    (16, struct.pack("<Q", 1)), (16, struct.pack("<Q", 0x13)),
    (24, bytes(8)), (32, bytes(16)), (48, struct.pack("<I", 2)),
    (52, struct.pack("<I", 8192)), (88, bytes(32)), (120, bytes(32)),
    (184, bytes(32)), (256, bytes(8)), (272, b"\x01"),
]
for offset, replacement in mutations:
    bad = valid_image()
    bad[480:] = b"\xA5" * 32
    bad[offset:offset + len(replacement)] = replacement
    before = bytes(bad[480:])
    bad_buffer = (ctypes.c_ubyte * 512).from_buffer(bad)
    assert lib.vcs_superblock_seal(bad_buffer) == CORRUPT
    assert bytes(bad[480:]) == before

bad_operation = valid_image(3)
bad_operation[152:184] = hashlib.sha256(b"unexpected operation").digest()
assert lib.vcs_superblock_seal((ctypes.c_ubyte * 512).from_buffer(bad_operation)) == CORRUPT

tampered = bytearray(image)
tampered[57] ^= 1
assert lib.vcs_superblock_verify((ctypes.c_ubyte * 512).from_buffer(tampered)) == CORRUPT
tampered = bytearray(image)
tampered[500] ^= 1
assert lib.vcs_superblock_verify((ctypes.c_ubyte * 512).from_buffer(tampered)) == CORRUPT

older = valid_image(generation=27, operation_sequence=91, next_transaction=103)
newer = valid_image(features=0x0B, generation=28,
                    operation_sequence=92, next_transaction=104)
sealed(older)
sealed(newer)
status, request, older_buffer, newer_buffer = select(older, newer)
assert status == OK
assert ctypes.addressof(request.result.contents) == ctypes.addressof(newer_buffer)
assert request.result_generation == 28
status, request, newer_buffer, older_buffer = select(newer, older)
assert status == OK
assert ctypes.addressof(request.result.contents) == ctypes.addressof(newer_buffer)

torn = bytearray(newer)
torn[500] ^= 1
status, request, older_buffer, torn_buffer = select(older, torn)
assert status == OK
assert ctypes.addressof(request.result.contents) == ctypes.addressof(older_buffer)
status, request, torn_buffer, older_buffer = select(torn, older)
assert status == OK
assert ctypes.addressof(request.result.contents) == ctypes.addressof(older_buffer)
second_torn = bytearray(older)
second_torn[60] ^= 1
status, request, _, _ = select(torn, second_torn)
assert status == CORRUPT
assert ctypes.cast(request.result, ctypes.c_void_p).value == 0x1234
assert request.result_generation == 0x5678

same = bytearray(older)
status, request, older_buffer, _ = select(older, same)
assert status == OK
assert ctypes.addressof(request.result.contents) == ctypes.addressof(older_buffer)
divergent = valid_image(generation=27, operation_sequence=91, next_transaction=103)
divergent[56:88] = hashlib.sha256(b"divergent head").digest()
sealed(divergent)
status, request, _, _ = select(older, divergent)
assert status == CONFLICT
assert ctypes.cast(request.result, ctypes.c_void_p).value == 0x1234

for rollback in (
    valid_image(generation=28, operation_sequence=92, next_transaction=103),
    valid_image(generation=28, operation_sequence=90, next_transaction=104),
):
    sealed(rollback)
    status, request, _, _ = select(older, rollback)
    assert status == CORRUPT

feature_old = valid_image(features=0x0B, generation=27,
                          operation_sequence=91, next_transaction=103)
feature_new = valid_image(features=3, generation=28,
                          operation_sequence=92, next_transaction=104)
sealed(feature_old)
sealed(feature_new)
status, request, _, _ = select(feature_old, feature_new)
assert status == CORRUPT

for incompatible in (
    (32, b"\xff" * 16),
    (48, struct.pack("<I", 2)),
    (52, struct.pack("<I", 8192)),
    (264, struct.pack("<q", 1)),
):
    candidate = valid_image(generation=28, operation_sequence=92,
                            next_transaction=104)
    offset, replacement = incompatible
    candidate[offset:offset + len(replacement)] = replacement
    # Unsupported per-slot fields fail sealing; immutable but individually valid
    # fields seal and are rejected by cross-generation compatibility checks.
    candidate_buffer = (ctypes.c_ubyte * 512).from_buffer(candidate)
    seal_status = lib.vcs_superblock_seal(candidate_buffer)
    if seal_status == OK:
        status, request, _, _ = select(older, candidate)
        assert status == CORRUPT
    else:
        assert seal_status == CORRUPT

print("VCS superblock: PASS (layout, sealing, tamper rejection, redundant recovery selection)")
