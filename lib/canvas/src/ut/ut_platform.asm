; Native Utkarsha OS service bindings used by Canvas. These are direct syscall
; veneers, not a foreign compatibility ABI.

%define UT_BINDING_IMPL 1
%include "inc/ut.inc"

section .text

%macro UT_SYSCALL 2
global %1
%1:
    mov eax, %2
    syscall
    ret
%endmacro

UT_SYSCALL ut_task_spawn, SYS_TASK_SPAWN
UT_SYSCALL ut_task_wait, SYS_TASK_WAIT
UT_SYSCALL ut_task_self, SYS_TASK_SELF
UT_SYSCALL ut_task_set_priority, SYS_TASK_SET_PRIO
UT_SYSCALL ut_task_pin, SYS_TASK_PIN

global ut_task_exit
ut_task_exit:
    mov eax, SYS_TASK_EXIT
    syscall
.halt:
    hlt
    jmp .halt

UT_SYSCALL ut_irq_register, SYS_IRQ_REGISTER
UT_SYSCALL ut_irq_unregister, SYS_IRQ_UNREGISTER
UT_SYSCALL ut_irq_enable, SYS_IRQ_ENABLE
UT_SYSCALL ut_irq_disable, SYS_IRQ_DISABLE
UT_SYSCALL ut_irq_affinity, SYS_IRQ_AFFINITY
UT_SYSCALL ut_irq_set_affinity, SYS_IRQ_SET_AFFINITY

UT_SYSCALL ut_input_register_callback, SYS_INPUT_REGISTER_CB
UT_SYSCALL ut_input_unregister_callback, SYS_INPUT_UNREGISTER_CB
UT_SYSCALL ut_input_device_info, SYS_INPUT_DEV_INFO
UT_SYSCALL ut_input_grab, SYS_INPUT_GRAB

UT_SYSCALL ut_fs_read, SYS_FS_READ
UT_SYSCALL ut_fs_stat, SYS_FS_STAT
UT_SYSCALL ut_fs_list, SYS_FS_LIST
UT_SYSCALL ut_fs_open, SYS_FS_OPEN
UT_SYSCALL ut_fs_pread, SYS_FS_PREAD
UT_SYSCALL ut_fs_close, SYS_FS_CLOSE

UT_SYSCALL ut_pci_for_each, SYS_PCI_FOR_EACH
UT_SYSCALL ut_pci_find_class, SYS_PCI_FIND_CLASS
UT_SYSCALL ut_pci_config_read_dword, SYS_PCI_CONFIG_READ
UT_SYSCALL ut_pci_config_write_dword, SYS_PCI_CONFIG_WRITE
UT_SYSCALL ut_pci_enable_device, SYS_PCI_ENABLE
UT_SYSCALL ut_pci_disable_device, SYS_PCI_DISABLE

UT_SYSCALL ut_mmio_map, SYS_MMIO_MAP
UT_SYSCALL ut_mmio_unmap, SYS_MMIO_UNMAP
UT_SYSCALL ut_dma_alloc, SYS_DMA_ALLOC
UT_SYSCALL ut_dma_free, SYS_DMA_FREE
UT_SYSCALL ut_dma_map_device, SYS_DMA_MAP_DEVICE
UT_SYSCALL ut_dma_sync, SYS_DMA_SYNC
UT_SYSCALL ut_i2c_read, SYS_I2C_READ
UT_SYSCALL ut_i2c_write, SYS_I2C_WRITE

UT_SYSCALL ut_tls_listen, SYS_TLS_LISTEN
UT_SYSCALL ut_tls_accept, SYS_TLS_ACCEPT
UT_SYSCALL ut_tls_connect, SYS_TLS_CONNECT
UT_SYSCALL ut_tls_read, SYS_TLS_READ
UT_SYSCALL ut_tls_write, SYS_TLS_WRITE
UT_SYSCALL ut_tls_close, SYS_TLS_CLOSE
UT_SYSCALL ut_tls_peer_cert, SYS_TLS_PEER_CERT

section .data
global ut_platform_version
ut_platform_version: dq 0x010000
