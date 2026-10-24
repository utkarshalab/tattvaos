# kernel/tests/ubf — test program and package

> What the kernel's boot self-test loads (`kernel/exec/selftest.asm`).

| File | What it is |
|---|---|
| [`hello.s`](hello.s) | the test program: prints two lines through `ut_console_print` (via its stub and via its slot), uses an `ABS64` pointer, data and bss, returns 42 |
| `hello.ubf` | `hello.s` built: `utasm -f ubf kernel/tests/ubf/hello.s -o kernel/tests/ubf/hello.ubf` |
| [`hello.manifest`](hello.manifest) | the test package's manifest |
| [`hello.conf`](hello.conf) | a configuration file the package carries |
| `hello.upk` | the test package, signed with the test key (command below) |
| `test-only.key`, `test-only.key.pub` | **a test key, and nothing else.** Its private half is in this repository, so a signature by it proves nothing: never put `test-only.key.pub` in a real trust store. |

The kernel is assembled by NASM, which cannot write UBF or UPK, so these are
committed built. To rebuild them after changing `hello.s` or the manifest
(from the repository root):

```sh
cd kernel/tests/ubf
utasm -f ubf hello.s -o hello.ubf
utasm -f upk hello.manifest --upk-add main=hello.ubf \
      --upk-add conf/hello=hello.conf --upk-sign test-only.key -o hello.upk
```

Part of the `kernel/` category in Utkarsha OS.
