# UTM Enterprise Build System
# Pure Assembly Implementation - Enterprise/Datacenter Grade

ARCH ?= x86_64

AS = nasm
ASFLAGS = -f elf64 -g -F dwarf
LD = ld
LDFLAGS = -nostdlib -static -z max-page-size=4096

KERNEL_DIR = kernel
COLLECTOR_DIR = collector
UI_DIR = ui
API_DIR = api
CLI_DIR = cli
INCLUDE_DIR = include
BUILD_DIR = build
OBJ_DIR = $(BUILD_DIR)/obj
BIN_DIR = $(BUILD_DIR)/bin

KERNEL_SRCS = \
	$(KERNEL_DIR)/proc_table.asm \
	$(KERNEL_DIR)/cpu_accounting.asm \
	$(KERNEL_DIR)/mem_stats.asm \
	$(KERNEL_DIR)/disk_accounting.asm \
	$(KERNEL_DIR)/net_accounting.asm \
	$(KERNEL_DIR)/energy.asm \
	$(KERNEL_DIR)/thermal.asm \
	$(KERNEL_DIR)/gpu_stats.asm \
	$(KERNEL_DIR)/numa_stats.asm \
	$(KERNEL_DIR)/container_stats.asm \
	$(KERNEL_DIR)/flight_rec.asm \
	$(KERNEL_DIR)/alert_engine.asm \
	$(KERNEL_DIR)/syscalls.asm

COLLECTOR_SRCS = \
	$(COLLECTOR_DIR)/sampler.asm \
	$(COLLECTOR_DIR)/aggregator.asm \
	$(COLLECTOR_DIR)/ring_buffer.asm \
	$(COLLECTOR_DIR)/daemon.asm

UI_SRCS = \
	$(UI_DIR)/text_ui.asm \
	$(UI_DIR)/graphs.asm \
	$(UI_DIR)/themes.asm

API_SRCS = \
	$(API_DIR)/utm_api.asm

CLI_SRCS = \
	$(CLI_DIR)/utm_cli.asm

KERNEL_OBJS = $(patsubst $(KERNEL_DIR)/%.asm,$(OBJ_DIR)/kernel/%.o,$(KERNEL_SRCS))
COLLECTOR_OBJS = $(patsubst $(COLLECTOR_DIR)/%.asm,$(OBJ_DIR)/collector/%.o,$(COLLECTOR_SRCS))
UI_OBJS = $(patsubst $(UI_DIR)/%.asm,$(OBJ_DIR)/ui/%.o,$(UI_SRCS))
API_OBJS = $(patsubst $(API_DIR)/%.asm,$(OBJ_DIR)/api/%.o,$(API_SRCS))
CLI_OBJS = $(patsubst $(CLI_DIR)/%.asm,$(OBJ_DIR)/cli/%.o,$(CLI_SRCS))

KERNEL_TARGET = $(BIN_DIR)/utm_kernel.o
COLLECTOR_TARGET = $(BIN_DIR)/utm_collector
UI_TARGET = $(BIN_DIR)/utm_ui
API_TARGET = $(BIN_DIR)/utm_api
CLI_TARGET = $(BIN_DIR)/utm_cli

all: $(KERNEL_TARGET) $(COLLECTOR_TARGET) $(UI_TARGET) $(API_TARGET) $(CLI_TARGET)

$(OBJ_DIR)/kernel $(OBJ_DIR)/collector $(OBJ_DIR)/ui $(OBJ_DIR)/api $(OBJ_DIR)/cli $(BIN_DIR):
	@mkdir -p $@

$(OBJ_DIR)/kernel/%.o: $(KERNEL_DIR)/%.asm | $(OBJ_DIR)/kernel
	$(AS) $(ASFLAGS) -I $(INCLUDE_DIR)/ -o $@ $<

$(OBJ_DIR)/collector/%.o: $(COLLECTOR_DIR)/%.asm | $(OBJ_DIR)/collector
	$(AS) $(ASFLAGS) -I $(INCLUDE_DIR)/ -o $@ $<

$(OBJ_DIR)/ui/%.o: $(UI_DIR)/%.asm | $(OBJ_DIR)/ui
	$(AS) $(ASFLAGS) -I $(INCLUDE_DIR)/ -o $@ $<

$(OBJ_DIR)/api/%.o: $(API_DIR)/%.asm | $(OBJ_DIR)/api
	$(AS) $(ASFLAGS) -I $(INCLUDE_DIR)/ -o $@ $<

$(OBJ_DIR)/cli/%.o: $(CLI_DIR)/%.asm | $(OBJ_DIR)/cli
	$(AS) $(ASFLAGS) -I $(INCLUDE_DIR)/ -o $@ $<

$(KERNEL_TARGET): $(KERNEL_OBJS) | $(BIN_DIR)
	$(LD) -r $(LDFLAGS) -o $@ $(KERNEL_OBJS)

$(COLLECTOR_TARGET): $(COLLECTOR_OBJS) $(KERNEL_OBJS) | $(BIN_DIR)
	$(LD) $(LDFLAGS) -o $@ $(COLLECTOR_OBJS) $(KERNEL_OBJS) \
		--entry=utm_sampler_main \
		-Ttext=0x400000

$(UI_TARGET): $(UI_OBJS) $(COLLECTOR_OBJS) $(KERNEL_OBJS) | $(BIN_DIR)
	$(LD) $(LDFLAGS) -o $@ $(UI_OBJS) $(COLLECTOR_OBJS) $(KERNEL_OBJS) \
		--entry=utm_ui_main \
		-Ttext=0x400000

$(API_TARGET): $(API_OBJS) | $(BIN_DIR)
	$(LD) $(LDFLAGS) -o $@ $(API_OBJS) \
		--entry=_start \
		-Ttext=0x400000

$(CLI_TARGET): $(CLI_OBJS) | $(BIN_DIR)
	$(LD) $(LDFLAGS) -o $@ $(CLI_OBJS) \
		--entry=_start \
		-Ttext=0x400000

install: all
	@mkdir -p $(DESTDIR)/boot/modules
	cp $(KERNEL_TARGET) $(DESTDIR)/boot/modules/utm_kernel.o
	@mkdir -p $(DESTDIR)/usr/bin
	cp $(COLLECTOR_TARGET) $(DESTDIR)/usr/bin/utm-collector
	cp $(UI_TARGET) $(DESTDIR)/usr/bin/utm-ui
	cp $(API_TARGET) $(DESTDIR)/usr/bin/utm-api
	cp $(CLI_TARGET) $(DESTDIR)/usr/bin/utm
	@mkdir -p $(DESTDIR)/etc/utm
	cp config/utm.conf $(DESTDIR)/etc/utm/utm.conf

clean:
	rm -rf $(BUILD_DIR)

debug: ASFLAGS += -DDEBUG
debug: all

test: all
	@echo "Running enterprise tests..."
	@./build/bin/utm_cli version

disasm: $(KERNEL_TARGET)
	objdump -d $(KERNEL_TARGET) > $(BUILD_DIR)/kernel.disasm
	objdump -d $(COLLECTOR_TARGET) > $(BUILD_DIR)/collector.disasm
	objdump -d $(UI_TARGET) > $(BUILD_DIR)/ui.disasm
	objdump -d $(API_TARGET) > $(BUILD_DIR)/api.disasm
	objdump -d $(CLI_TARGET) > $(BUILD_DIR)/cli.disasm

size: all
	@echo "=== Kernel Modules ==="
	@size $(KERNEL_OBJS)
	@echo "=== Collector ==="
	@size $(COLLECTOR_TARGET)
	@echo "=== UI ==="
	@size $(UI_TARGET)
	@echo "=== API ==="
	@size $(API_TARGET)
	@echo "=== CLI ==="
	@size $(CLI_TARGET)

help:
	@echo "UTM Enterprise Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all       - Build all components (default)"
	@echo "  kernel    - Build kernel modules only"
	@echo "  collector - Build collector daemon only"
	@echo "  ui        - Build UI only"
	@echo "  api       - Build REST API only"
	@echo "  cli       - Build CLI only"
	@echo "  install   - Install to DESTDIR"
	@echo "  clean     - Remove build artifacts"
	@echo "  debug     - Build with debug symbols"
	@echo "  test      - Run tests"
	@echo "  disasm    - Generate disassembly listings"
	@echo "  size      - Show size report"
	@echo "  help      - Show this help"
	@echo ""
	@echo "Variables:"
	@echo "  ARCH      - Target architecture (default: x86_64)"
	@echo "  DESTDIR   - Installation prefix"

.PHONY: all kernel collector ui api cli install clean debug test disasm size help