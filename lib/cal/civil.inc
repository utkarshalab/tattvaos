%ifndef CAL_CIVIL_INC
%define CAL_CIVIL_INC
%define CAL_INVALID -1
%define CAL_RANGE -2
struc cal_civil_date
 .year: resq 1
 .month: resq 1
 .day: resq 1
 .hour: resq 1
 .minute: resq 1
 .second: resq 1
 .weekday: resq 1
 .yearday: resq 1
endstruc
struc cal_civil_month
 .year: resq 1
 .month: resq 1
 .week_start: resq 1
 .days: resq 1
 .first: resq 1
 .cells: resq 42
endstruc
%endif
