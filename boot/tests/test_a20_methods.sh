#!/bin/sh
# boot/tests/test_a20_methods.sh
# Reserved for testing all three A20 enabling methods individually.
#
# The boot code tries port 0x92, BIOS INT 15h, and the 8042 controller in
# sequence, but the build does not yet expose a switch that forces one path.
# The previous version booted the same image three times and falsely labelled
# that as independent method coverage. Exit 77 is the conventional "skipped"
# result; run_all.sh intentionally does not invoke this file yet.

echo "SKIP: forced A20-method builds are not implemented"
exit 77
