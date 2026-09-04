# PK8000 Nano - the ПК8000 "Сура" on the Tang Nano 20K.
#
# Everything this needs lives under tools/, fetched by `make toolchain`;
# nothing is installed on the host.  Both halves build here: the
# bitstream through Gowin's headless shell, the firmware through the
# Bouffalo SDK; the design lints and simulates besides.
# .claude/docs/build.md says what each of these does and does not prove.
#
#   make toolchain   fetch the toolchain into tools/  (~7 GB, once)
#   make lint        Verilator over the whole design - the fast check
#   make sim         run the machine to the BASIC prompt (RUN_MS=1200)
#   make wave        the same, dumping a VCD, then open it (WAVE_MS=2)
#   make frames      the same, writing video frames as .ppm (PPM_FROM=1000)
#   make bitstream   build the FPGA bitstream with Gowin -> bin/tang.fs
#                    (refuses a layout that fails the timing gate)
#   make timing      the timing gate alone, on the last PnR report
#   make menu-test   the OSD menu on the host: forms, keys, layout
#   make bas-test    the firmware's BASIC tokeniser on the host against tools/mkcas.py
#   make tokens      regenerate mnano/pk8000_tokens.h from the ROM (tools/mkcas.py)
#   make fw          build the BL616 firmware -> build/fw/bl616.bin
#   make rom         regenerate tang/src/pk8000/pk8000_rom.v from tang/rom/
#   make waits       regenerate tang/src/pk8000/waits_rom.v (tools/waits_rom.py)
#   make flash-fpga  openFPGALoader the shipped bitstream to SRAM
#   make flash-mcu   flash the firmware over UART (COMX=/dev/ttyACM0)
#   make clean       remove build/ and sim/out/

ROOT     := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
TOOLS    := $(ROOT)/tools
OSS      := $(TOOLS)/oss-cad-suite
BUILD    := $(ROOT)/build

GOWIN    := $(TOOLS)/gowin
GWSH     := $(GOWIN)/bin/gw_sh
# gw_sh ships its own Qt and its own libstdc++, and on a current Linux both
# fight the system's.  tools/fetch.sh moves the stale duplicates into
# _shadowed/; these three variables do the rest.
GWENV    := LD_LIBRARY_PATH="$(GOWIN)/lib:$(GOWIN)/bin" \
            QT_QPA_PLATFORM=offscreen \
            QT_PLUGIN_PATH="$(GOWIN)/plugins/qt"
VERILATOR:= $(OSS)/bin/verilator
GTKWAVE  := $(OSS)/bin/gtkwave
OFL      := $(OSS)/bin/openFPGALoader
BLFLASH  := $(TOOLS)/bouffalo_sdk/tools/bflb_tools/bouffalo_flash_cube/BLFlashCommand-ubuntu
PYTHON   := python3

# The design's file list comes out of the Gowin project file, so it can
# never drift from what the IDE builds.
RTL      := $(shell $(PYTHON) $(TOOLS)/srcs.py)
STUBS    := sim/stubs/gowin_ip_sim.v sim/stubs/sdram_model.v sim/stubs/sd_card_sim.v
TB       := sim/tb/tb_top.v
SIMBIN   := $(BUILD)/sim/obj/tb_top
SIMBINW  := $(BUILD)/sim/objw/tb_top_w

VFLAGS   := -Wno-fatal --timing -j 4

ROMHEX   := $(BUILD)/mif/pk8000_rom.hex $(BUILD)/mif/fdc_rom.hex $(BUILD)/mif/hdd_rom.hex

# The BASIC ROM takes about a second of machine time to reach its prompt.
RUN_MS   ?= 1200
PPM_MAX  ?= 4
PPM_FROM ?= 1000
WAVE_MS  ?= 2

COMX     ?= /dev/ttyACM0
BAUDRATE ?= 2000000
FW_BIN   ?= bin/bl616.bin

# The BL616 firmware: -DM0S_DOCK=1 picks the SPI pinout in mnano/spi.c
# that matches this board's wiring; CONFIG_BT_STACK_CLI=0 drops a BLE
# shell that will not build against this SDK.
FW_BOARD := bl616dk -DCMAKE_C_FLAGS=-DM0S_DOCK=1 -DCONFIG_BT_STACK_CLI=0
FW_OUT   := mnano/build/build_out/misterynano_fw_bl616.bin

.PHONY: all toolchain lint sim wave frames fw rom waits mif clean bitstream \
        flash-fpga flash-fpga-flash flash-mcu help menu-test bas-test tokens timing

all: lint

help:
	@sed -n '2,24p' $(firstword $(MAKEFILE_LIST)) | sed 's/^# \?//'

#-----------------------------------------------------------------------
# Toolchain
#-----------------------------------------------------------------------
toolchain:
	$(TOOLS)/fetch.sh

$(VERILATOR):
	@echo "toolchain missing - run: make toolchain" >&2; exit 1

#-----------------------------------------------------------------------
# ROM images.  The synthesised ROM is pk8000_rom.v (pROM primitives, made
# by bin2prom.py and committed); the simulation model reads $readmemh
# hex of the same bytes.
#-----------------------------------------------------------------------
mif: $(ROMHEX)

$(BUILD)/mif/pk8000_rom.hex: tang/rom/pk8000_v12.rom $(TOOLS)/mif.py
	@mkdir -p $(dir $@)
	$(PYTHON) $(TOOLS)/mif.py binhex $< $@

$(BUILD)/mif/fdc_rom.hex: tang/rom/pk8000_fdc.rom $(TOOLS)/mif.py
	@mkdir -p $(dir $@)
	$(PYTHON) $(TOOLS)/mif.py binhex $< $@

$(BUILD)/mif/hdd_rom.hex: tang/rom/pk8000_hdd.rom $(TOOLS)/mif.py
	@mkdir -p $(dir $@)
	$(PYTHON) $(TOOLS)/mif.py binhex $< $@

rom:
	$(PYTHON) $(TOOLS)/bin2prom.py tang/rom/pk8000_v12.rom tang/src/pk8000/pk8000_rom.v -m pk8000_rom
	$(PYTHON) $(TOOLS)/bin2prom.py tang/rom/pk8000_fdc.rom tang/src/pk8000/fdc_rom.v -m fdc_rom
	$(PYTHON) $(TOOLS)/bin2prom.py tang/rom/pk8000_hdd.rom tang/src/pk8000/hdd_rom.v -m hdd_rom

# a .cas of a one-line BASIC program, for the tape test (make sim SIMARGS="+TAPE=soft/hello.cas +TYPE_CLOAD")
soft/hello.cas: $(TOOLS)/mkcas.py
	$(PYTHON) $(TOOLS)/mkcas.py $@

waits:
	$(PYTHON) $(TOOLS)/waits_rom.py > tang/src/pk8000/waits_rom.v

#-----------------------------------------------------------------------
# Lint and simulation
#-----------------------------------------------------------------------
lint: $(VERILATOR)
	$(VERILATOR) --lint-only $(VFLAGS) --top-module top $(RTL) $(STUBS)
	@echo "lint: ok"

$(SIMBIN): $(TB) $(STUBS) $(RTL) $(VERILATOR)
	@mkdir -p $(BUILD)/sim
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_top -o tb_top --Mdir $(BUILD)/sim/obj \
	  $(TB) $(STUBS) $(RTL)

$(SIMBINW): $(TB) $(STUBS) $(RTL) $(VERILATOR)
	@mkdir -p $(BUILD)/sim
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style --trace \
	  --trace-structs --trace-max-array 256 \
	  --top-module tb_top -o tb_top_w --Mdir $(BUILD)/sim/objw \
	  $(TB) $(STUBS) $(RTL)

sim: $(SIMBIN) mif
	@mkdir -p sim/out
	$(SIMBIN) +RUN_MS=$(RUN_MS) $(SIMARGS)

wave: $(SIMBINW) mif
	@mkdir -p sim/out
	$(SIMBINW) +VCD +RUN_MS=$(WAVE_MS) $(SIMARGS)
	@ls -la sim/out/tb_top.vcd
	$(GTKWAVE) sim/out/tb_top.vcd &

# Frames as .ppm, decoded back out of the TMDS stream: 768x576.
frames: $(SIMBIN) mif
	@mkdir -p sim/out
	$(SIMBIN) +VIDEO_PPM +RUN_MS=$(RUN_MS) +PPM_MAX=$(PPM_MAX) \
	  +PPM_FROM=$(PPM_FROM) $(SIMARGS)
	@ls -la sim/out/*.ppm 2>/dev/null || echo "no frames produced"

#-----------------------------------------------------------------------
# FPGA bitstream
#-----------------------------------------------------------------------
bitstream:
	@test -x $(GWSH) || { \
	  echo "gowin missing - run: make toolchain" >&2; exit 1; }
	$(PYTHON) $(TOOLS)/gowin_tcl.py > tang/build.tcl
	cd tang && $(GWENV) $(GWSH) build.tcl
	@$(PYTHON) $(TOOLS)/timing_check.py || { \
	  echo "bitstream NOT copied to bin/: the layout fails the timing gate" >&2; \
	  echo "(.claude/rules/timing.md; make timing to see it again)" >&2; exit 1; }
	@mkdir -p bin
	@rm -f bin/tang.fs && cp tang/impl/pnr/pk8000.fs bin/tang.fs
	@echo
	@echo "bitstream: bin/tang.fs"
	@ls -l bin/tang.fs
	@echo "resources and timing:"
	@grep -iE "Timing Constraints|Logic|Register|BSRAM|PLL" \
	    tang/impl/pnr/pk8000.rpt.txt 2>/dev/null | head -12 || true

timing:
	$(PYTHON) $(TOOLS)/timing_check.py

#-----------------------------------------------------------------------
# MCU firmware
#-----------------------------------------------------------------------
fw:
	@test -d $(TOOLS)/bouffalo_sdk || { \
	  echo "bouffalo_sdk missing - run: make toolchain" >&2; exit 1; }
	@test -x $(TOOLS)/toolchain_gcc_t-head_linux/bin/riscv64-unknown-elf-gcc || { \
	  echo "riscv toolchain missing - run: make toolchain" >&2; exit 1; }
	$(MAKE) -C mnano \
	  CROSS_COMPILE=$(TOOLS)/toolchain_gcc_t-head_linux/bin/riscv64-unknown-elf- \
	  BL_SDK_BASE=$(TOOLS)/bouffalo_sdk \
	  BOARD='$(FW_BOARD)' \
	  PATH="$(TOOLS)/cmake/bin:$(TOOLS)/bin:$$PATH"
	@mkdir -p $(BUILD)/fw bin
	@cp $(FW_OUT) $(BUILD)/fw/bl616.bin
	@echo
	@echo "firmware: build/fw/bl616.bin"
	@ls -l $(BUILD)/fw/bl616.bin

# The OSD menu on the host (mnano/menu_test.c): menu.c with its SDL host
# switch, u8g2 drawing into a bitmap, FatFs with no card.  Walks every
# PK8000 form and leaves each screen under build/menu/ as text and PNG.
FATFS_SRC := $(TOOLS)/bouffalo_sdk/components/fs/fatfs
MENU_TEST_SRC := mnano/menu_test.c mnano/menu.c \
  $(wildcard mnano/u8g2/csrc/*.c) mnano/u8g2/sys/bitmap/common/u8x8_d_bitmap.c \
  $(FATFS_SRC)/ff.c $(FATFS_SRC)/ffunicode.c
# The tokeniser the firmware uses for "Run .bas" (mnano/bas.c) against the
# one tools/mkcas.py uses for a .cas: the same bytes for soft/demo.bas.
bas-test: mnano/bas.c mnano/bas_test.c mnano/pk8000_tokens.h soft/demo.bas
	@mkdir -p $(BUILD)/menu
	$(CC) -O -Wall -DBAS_HOST_TEST -Imnano -o $(BUILD)/menu/bas_test mnano/bas.c mnano/bas_test.c
	$(BUILD)/menu/bas_test soft/demo.bas $(BUILD)/menu/demo_fw.tok
	$(PYTHON) $(TOOLS)/mkcas.py --tok $(BUILD)/menu/demo_py.tok soft/demo.bas
	cmp $(BUILD)/menu/demo_fw.tok $(BUILD)/menu/demo_py.tok && echo "bas-test: ok"

tokens:
	$(PYTHON) $(TOOLS)/mkcas.py --header mnano/pk8000_tokens.h

menu-test: $(MENU_TEST_SRC) mnano/menu.h VERSION
	@test -d $(FATFS_SRC) || { echo "bouffalo_sdk missing - run: make toolchain" >&2; exit 1; }
	@mkdir -p $(BUILD)/menu
	rm -f $(BUILD)/menu/*.txt $(BUILD)/menu/*.png
	@$(CC) -O1 -w -DSDL -DCORE_VERSION='"$(shell head -1 VERSION)"' \
	  -Imnano -Imnano/u8g2/csrc -I$(FATFS_SRC) -o $(BUILD)/menu/menu_test $(MENU_TEST_SRC)
	$(BUILD)/menu/menu_test $(BUILD)/menu
	$(PYTHON) $(TOOLS)/osd_png.py $(BUILD)/menu/*.txt

#-----------------------------------------------------------------------
# Flashing
#-----------------------------------------------------------------------
flash-fpga:
	$(OFL) -b tangnano20k bin/tang.fs

flash-fpga-flash:
	$(OFL) -b tangnano20k -f -r bin/tang.fs

# The BL616 flashes over its own UART bootloader: hold BOOT, tap RESET,
# release BOOT, then say which port that put on the host.
flash-mcu:
	@test -x $(BLFLASH) || { \
	  echo "bouffalo_sdk missing - run: make toolchain" >&2; exit 1; }
	@test -f $(FW_BIN) || { \
	  echo "no firmware at $(FW_BIN)" >&2; exit 1; }
	@test -w $(COMX) || { \
	  echo "cannot write $(COMX) - is the board in boot mode, and are" >&2; \
	  echo "you in the 'dialout' group?  See .claude/docs/build.md." >&2; \
	  exit 1; }
	@mkdir -p $(BUILD)/flash
	@printf '[cfg]\nerase = 1\nskip_mode = 0x0, 0x0\nboot2_isp_mode = 0\n\n[FW]\nfiledir = %s\naddress = 0x000000\n' \
	  "$(abspath $(FW_BIN))" > $(BUILD)/flash/bl616.ini
	@echo "flashing $(abspath $(FW_BIN)) -> $(COMX)"
	$(BLFLASH) --interface=uart --baudrate=$(BAUDRATE) --port=$(COMX) \
	  --chipname=bl616 --config=$(BUILD)/flash/bl616.ini

clean:
	rm -rf $(BUILD) sim/out mnano/build mnano/build_out
