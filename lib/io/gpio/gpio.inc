; =============================================================================
; Utkarsha OS — lib/io/gpio/gpio.inc
; =============================================================================
; Constants and limits for GPIO controllers and pins. Plan:
; lib/io/gpio/ROADMAP.md.
; =============================================================================

%ifndef LIB_IO_GPIO_GPIO_INC
%define LIB_IO_GPIO_GPIO_INC

%define GPIO_MAX_CTRL       2       ; controllers
%define GPIO_MAX_PINS       256     ; pins per controller

; controller kinds
%define GPIO_KIND_NONE      0
%define GPIO_KIND_AMD       1

; interrupt modes for gpio_irq_setup (combine one trigger and one polarity)
%define GPIO_IRQ_EDGE       (1 << 0)    ; else level
%define GPIO_IRQ_LOW        (1 << 1)    ; active low / falling edge
%define GPIO_IRQ_BOTH       (1 << 2)    ; both edges (edge mode only)

; pulls for gpio_pull
%define GPIO_PULL_NONE      0
%define GPIO_PULL_UP        1
%define GPIO_PULL_DOWN      2

; a pin that interrupts this many times within GPIO_STORM_NS is masked
%define GPIO_STORM_COUNT    10000
%define GPIO_STORM_NS       1000000000

; errors (negative in EAX)
%define GPIO_EBUSY          16
%define GPIO_ENODEV         19
%define GPIO_EINVAL         22
%define GPIO_ENOSPC         28

; per-pin state bits (gpio_pin_flags)
%define GPIO_PIN_IRQ        (1 << 0)    ; has a handler
%define GPIO_PIN_LEVEL      (1 << 1)    ; level-triggered: masked until
                                        ; the handler's owner unmasks it
%define GPIO_PIN_STORM      (1 << 2)    ; masked by storm detection

%endif ; LIB_IO_GPIO_GPIO_INC
