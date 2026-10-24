%ifndef CAL_CIVIL_API_INC
%define CAL_CIVIL_API_INC
%include "lib/cal/civil.inc"
; RDI,RSI,RDX,RCX,R8,R9 arguments; RAX status; native x86-64 preserved registers.
extern cal_civil_validate,cal_civil_to_epoch,cal_civil_from_epoch
extern cal_civil_month_grid,cal_civil_add_days,cal_civil_add_months,cal_civil_iso_week
%endif
