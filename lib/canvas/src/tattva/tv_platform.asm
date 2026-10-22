; Native TattvaOS service bindings used by Canvas. These are direct syscall
; veneers, not a foreign compatibility ABI.

%define TATTVA_BINDING_IMPL 1
%include "inc/tattva.inc"

section .text

%macro TV_SYSCALL 2
global %1
%1:
    mov eax, %2
    syscall
    ret
%endmacro

TV_SYSCALL tv_task_spawn, SYS_TASK_SPAWN
TV_SYSCALL tv_task_wait, SYS_TASK_WAIT
TV_SYSCALL tv_task_self, SYS_TASK_SELF
TV_SYSCALL tv_task_set_priority, SYS_TASK_SET_PRIO
TV_SYSCALL tv_task_pin, SYS_TASK_PIN

global tv_task_exit
tv_task_exit:
    mov eax, SYS_TASK_EXIT
    syscall
.halt:
    hlt
    jmp .halt

TV_SYSCALL tv_irq_register, SYS_IRQ_REGISTER
TV_SYSCALL tv_irq_unregister, SYS_IRQ_UNREGISTER
TV_SYSCALL tv_irq_enable, SYS_IRQ_ENABLE
TV_SYSCALL tv_irq_disable, SYS_IRQ_DISABLE
TV_SYSCALL tv_irq_affinity, SYS_IRQ_AFFINITY
TV_SYSCALL tv_irq_set_affinity, SYS_IRQ_SET_AFFINITY

TV_SYSCALL tv_input_register_callback, SYS_INPUT_REGISTER_CB
TV_SYSCALL tv_input_unregister_callback, SYS_INPUT_UNREGISTER_CB
TV_SYSCALL tv_input_device_info, SYS_INPUT_DEV_INFO
TV_SYSCALL tv_input_grab, SYS_INPUT_GRAB

TV_SYSCALL tv_fs_read, SYS_FS_READ
TV_SYSCALL tv_fs_stat, SYS_FS_STAT
TV_SYSCALL tv_fs_list, SYS_FS_LIST
TV_SYSCALL tv_fs_open, SYS_FS_OPEN
TV_SYSCALL tv_fs_pread, SYS_FS_PREAD
TV_SYSCALL tv_fs_close, SYS_FS_CLOSE

TV_SYSCALL tv_pci_for_each, SYS_PCI_FOR_EACH
TV_SYSCALL tv_pci_find_class, SYS_PCI_FIND_CLASS
TV_SYSCALL tv_pci_config_read_dword, SYS_PCI_CONFIG_READ
TV_SYSCALL tv_pci_config_write_dword, SYS_PCI_CONFIG_WRITE
TV_SYSCALL tv_pci_enable_device, SYS_PCI_ENABLE
TV_SYSCALL tv_pci_disable_device, SYS_PCI_DISABLE

TV_SYSCALL tv_mmio_map, SYS_MMIO_MAP
TV_SYSCALL tv_mmio_unmap, SYS_MMIO_UNMAP
TV_SYSCALL tv_dma_alloc, SYS_DMA_ALLOC
TV_SYSCALL tv_dma_free, SYS_DMA_FREE
TV_SYSCALL tv_dma_map_device, SYS_DMA_MAP_DEVICE
TV_SYSCALL tv_dma_sync, SYS_DMA_SYNC
TV_SYSCALL tv_i2c_read, SYS_I2C_READ
TV_SYSCALL tv_i2c_write, SYS_I2C_WRITE

TV_SYSCALL tv_tls_listen, SYS_TLS_LISTEN
TV_SYSCALL tv_tls_accept, SYS_TLS_ACCEPT
TV_SYSCALL tv_tls_connect, SYS_TLS_CONNECT
TV_SYSCALL tv_tls_read, SYS_TLS_READ
TV_SYSCALL tv_tls_write, SYS_TLS_WRITE
TV_SYSCALL tv_tls_close, SYS_TLS_CLOSE
TV_SYSCALL tv_tls_peer_cert, SYS_TLS_PEER_CERT

section .data
global tv_platform_version
tv_platform_version: dq 0x010000
