; Test-only C ABI bridges for ctypes. Core uses its native register interface.
bits 64
default rel
extern calc_scientific
section .text
global test_scientific
test_scientific:
 push rdx
 call calc_scientific
 pop rcx
 movsd [rcx],xmm0
 mov eax,edx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
