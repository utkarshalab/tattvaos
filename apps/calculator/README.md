# Utkarsha Calculator

An interactive scientific and programmer calculator written in x86-64 assembly.
Its engine has no filesystem, heap, networking, libc, or libm dependency. Scientific
functions reuse the assembly implementations in `lib/umath`.

## Build and use

On Linux/WSL with NASM, GNU ld, make and Python 3:

```sh
make
./build/calc                         # interactive terminal
./build/calc 'sqrt(81) + 2**3'        # 17
./build/calc --deg 'sin(30)'         # 0.5
./build/calc -x '0xff << 4'          # ff0
./build/calc -b '255 & ~0x80'        # 1111111
make test
```

No arguments starts a session. `--help` lists functions and commands. Quote a
one-shot expression containing spaces or shell operators as one argument.
Scientific mode is the default. `--science` selects it explicitly; `--programmer`
or `-d` selects decimal programmer mode, `-x` hexadecimal, `-b` binary.
`--deg` selects scientific mode with degree input/output for trig functions.

Example interactive session:

```text
calc> x = sqrt(81)
9
calc> x**2 + 5!
201
calc> ms
Memory updated
calc> ans / 2
100.5
calc> mr
201
calc> deg
Degrees
calc> sin(30)
0.5
calc> hex
Programmer output base updated
calc> 0xff << 4
ff0
calc> history
...
calc> quit
Bye.
```

## Scientific mode

- Decimal fractions and decimal exponents: `.5`, `1.25`, `3e-8`.
- Constants `pi`, `e`, `tau`; previous successful result `ans`; current memory `mem`.
- Variables `x`, `y`, `z`, `a`, `b`, `c`, initially zero. Assign at session level
  with `x = expression`. Failed assignments preserve the variable and `ans`.
- Arithmetic `+ - * / %`, right-associative power `**`, postfix factorial `!`.
  `%` is remainder, not percentage; `^` belongs to programmer XOR.
- Precedence: factorial, power, unary signs, multiplication/division/remainder,
  addition/subtraction. Thus `-2**2` is `-4`, `2**3**2` is `512`.
- Unary functions: `sqrt`, `cbrt`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`,
  `ln`, `log`/`log10`, `log2`, `exp`, `abs`, `floor`, `ceil`, `round`, `trunc`, `fact`.
- Binary functions: `pow(x,y)`, `hypot(x,y)`, `atan2(y,x)`, `min(x,y)`, `max(x,y)`.
- `round` uses ties to even. Factorials require an integer from 0 through 170.
  Division truncation does not apply in scientific mode; `1/2` returns `0.5`.

## Programmer mode

Exact 64-bit bit patterns, decimal/`0x`/`0b` literals, parentheses, unary `+ - ~`,
and binary `* / % + - << >> & ^ |` (listed from higher to lower precedence).
Operators of equal precedence associate left. `ans` and `mem` retain exact integer
values, including values beyond binary64's exact-integer range.

Arithmetic wraps modulo 2^64. Decimal output and division/remainder are signed
two's-complement; division truncates toward zero and remainder follows the dividend.
Hex/binary output is unsigned, lowercase, without a prefix. Shifts are logical
with counts 0 through 63. Oversized literals, zero divisors, and signed division
overflow (INT64_MIN / -1, including remainder) return errors.

## Session commands

| Command | Effect |
|---|---|
| `sci`, `prog` | Switch arithmetic mode |
| `rad`, `deg` | Set scientific angle units (default radians) |
| `dec`, `hex`, `bin` | Select programmer mode and output base |
| `precision N` | Set scientific display to 1..15 significant digits; default 12 |
| `ms`, `mr`, `mc` | Store last result, recall memory into `ans`, clear memory |
| `m+`, `m-` | Add/subtract last result to/from memory |
| `history` | Show the last 16 successful expressions, oldest first |
| `clear` | Clear expression history |
| `reset` | Reset the entire session, variables, memories, modes and history |
| `help` | Show built-in help |
| `quit`, `exit` | End the session |

Scientific and programmer modes maintain separate answers and memories. Changing
modes never converts or loses an exact integer. Memory recall updates the current
answer. Memory commands are not added to expression history. Scientific memory
updates that would become nonfinite fail without overwriting memory.
All state is in memory and lasts only for the current session.

Input is case sensitive and limited to 255 bytes per terminal/session line.
Blank interactive lines do nothing; a blank one-shot expression is a usage error.
Overlong terminal lines are rejected and drained before the next prompt. EOF
processes a final unterminated line. Host terminal line discipline supplies normal
line editing; custom arrow-key history and a Canvas GUI are not implemented.

## Numerical limits

Scientific calculations use binary64, not arbitrary-precision decimal arithmetic.
The parser retains up to 18 significant decimal digits and scales using x87
extended precision; arbitrary-length literals are not guaranteed correctly rounded.
Output rounds to 1..15 significant decimal digits and uses scientific notation for
very small/large values. It is a display format, not a guaranteed lossless serializer.

Nonfinite results, out-of-range decimal literals, and function domain errors are
reported. Underflow from arithmetic may round to zero. Trig arguments are limited
to absolute values at most 6.5e9 radians after angle conversion, matching umath's
accurate range-reduction domain. A floating-point approximation to a pole such as
`tan(pi/2)` may produce a large finite result. Parser recursion is limited to 64
expression frames. The core assumes the standard masked floating-point exceptions
and round-to-nearest environment used by umath.

## Native integration

`src/host.asm` is the Linux development terminal; it alone performs host system
calls. `build/calc` is a static Linux ELF, not an Utkarsha boot image. The native
engine and session contain no host calls and do not need UBF/UPK.

System V AMD64 entry points:

| Function | Inputs | Result |
|---|---|---|
| `calc_eval` | `rdi=NUL integer expression` | `rax=value`, `edx=status` |
| `calc_eval_context` | same, `rsi=two qwords: integer ans/mem` | same |
| `calc_scientific` | `rdi=NUL expression`, `rsi=initialized context` | `xmm0=value`, `edx=status`; updates scientific ans on success |
| `calc_format` | `rdi=integer`, `esi=2/10/16`, `rdx=buffer>=67 bytes` | `rax=buffer`, `edx=length` |
| `calc_float_format` | `xmm0=value`, `rdi=buffer>=64`, `esi=precision 1..15` | `rax=buffer`, `edx=length` |
| `calc_session_init` | `rdi=context`, at least `CALC_CONTEXT_SIZE` writable bytes | initialized context |
| `calc_session` | `rdi=context`, `rsi=NUL line`, `rdx=buffer>=CALC_OUTPUT_SIZE` | `eax=status`, NUL-terminated response |
| `calc_cli` | `rdi=argc`, `rsi=argv`, `rdx=initialized context`, `rcx=output buffer` | `eax=status`, response in caller buffer |
| `cmd_calc` | `rdi=argc`, `rsi=argv` | one-shot command status; prints through `frontend_write_str` |

`src/session.inc` defines state/buffer sizes and offsets. Contexts are caller-owned;
independent contexts do not share calculator state. Serialize access to a single
context. Buffers must not overlap inputs or contexts. Inputs must remain readable
through NUL. All entry points preserve callee-saved registers. No heap is required.
`cmd_calc` uses about 14 KiB of stack for its temporary context and output, plus
parser/library calls; reserve at least 24 KiB. A persistent native terminal can call
`calc_session` using separately allocated state/buffers instead.

Status codes: 0 success, 1 syntax/usage/input limit, 2 range/nonfinite, 3 division,
4 shift, 5 nesting, 6 invalid API argument/host I/O failure, 7 function domain.
`calc_session` returns 255 for quit/exit; terminal hosts translate that to success.
Formatting returns zero in both result registers for invalid base/precision or
nonfinite scientific input, without writing. Evaluators return zero value on error.

Ush registers a calculator command and embeds this engine/session with persistent
state: `calc "expression"` evaluates once and `calc` enters the calculator terminal.
See [Ush](../ush/README.md). Its shell adapter links the core objects rather than
this app's optional `command.o`. The calculator runs through Ush in the production
kernel under BIOS/UEFI QEMU, including SMP and strict-NX firmware; see
[integration evidence](../ush/docs/KERNEL_QEMU.md). Canvas UI and physical hardware
remain outside the current qualification.

## Validation

`make test` assembles the app and runs integer and scientific checks against Python
reference arithmetic/math, formatter edge cases across the binary64 exponent range,
command frontend tests, and session/terminal tests for memory, variables, angle/base
changes, history wraparound, precision, error recovery, overlong input and EOF.
These are focused Linux/WSL host checks, not hardware or full OS qualification.
