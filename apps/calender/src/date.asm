; Public app symbols delegate all date arithmetic to lib/cal.
bits 64
default rel
section .text
%ifndef TIME_NATIVE_EMBEDDED
extern cal_civil_validate
%endif
global ucal_validate
ucal_validate: jmp cal_civil_validate
%ifndef TIME_NATIVE_EMBEDDED
extern cal_civil_to_epoch
%endif
global ucal_to_epoch
ucal_to_epoch: jmp cal_civil_to_epoch
%ifndef TIME_NATIVE_EMBEDDED
extern cal_civil_from_epoch
%endif
global ucal_from_epoch
ucal_from_epoch: jmp cal_civil_from_epoch
%ifndef TIME_NATIVE_EMBEDDED
extern cal_civil_month_grid
%endif
global ucal_month_grid
ucal_month_grid: jmp cal_civil_month_grid
%ifndef TIME_NATIVE_EMBEDDED
extern cal_civil_add_days
%endif
global ucal_add_days
ucal_add_days: jmp cal_civil_add_days
%ifndef TIME_NATIVE_EMBEDDED
extern cal_civil_add_months
%endif
global ucal_add_months
ucal_add_months: jmp cal_civil_add_months
%ifndef TIME_NATIVE_EMBEDDED
extern cal_civil_iso_week
%endif
global ucal_iso_week
ucal_iso_week: jmp cal_civil_iso_week
%ifndef TIME_NATIVE_EMBEDDED
section .note.GNU-stack noalloc noexec nowrite progbits
%endif
