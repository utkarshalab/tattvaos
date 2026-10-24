%ifndef UCALENDER_API_INC
%define UCALENDER_API_INC
%include "apps/calender/inc/calender.inc"
; Native assembly calling convention: RDI,RSI,RDX,RCX,R8,R9 arguments; RAX result.
; Preserve RBX,RBP,R12..R15; RSP aligned to 16 bytes before CALL; DF clear.
extern ucal_validate
extern ucal_to_epoch
extern ucal_from_epoch
extern ucal_month_grid
extern ucal_add_days
extern ucal_add_months
extern ucal_iso_week
extern ucal_store_init
extern ucal_event_put
extern ucal_event_get
extern ucal_event_delete
extern ucal_event_query
extern ucal_now
extern ucal_month_now
%endif
