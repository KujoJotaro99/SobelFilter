SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

TOP := sobel
RTL_DIR := ../../rtl/sobel
FILELIST := $(RTL_DIR)/filelist.json
PCF := icebreaker.pcf
BUILD := build

YOSYS := yosys
NEXTPNR := nextpnr-ice40
ICEPACK := icepack
LOG ?= out.txt
LOG_CMD := tee -a $(LOG)
SEED ?= 14
DEVICE := up5k
PACKAGE := sg48

VERILOG_SOURCES := $(shell python3 -c "import json; \
    j=json.load(open('$(FILELIST)')); \
    print(' '.join('$(RTL_DIR)/' + f for f in j['files']))")

JSON := $(BUILD)/$(TOP).json
ASC := $(BUILD)/$(TOP).asc
BIN := $(BUILD)/$(TOP).bin

.PHONY: all netlist synth place bitstream abstract clean log_init

all: log_init bitstream

log_init:
	@ : > $(LOG)

$(BUILD):
	mkdir -p $(BUILD)

netlist: $(JSON)

$(JSON): $(VERILOG_SOURCES) | $(BUILD)
	$(YOSYS) -p "read_verilog -sv $(VERILOG_SOURCES); synth_ice40 -top $(TOP) -json $(JSON)" 2>&1 | $(LOG_CMD)

synth: $(JSON)

place: $(ASC)

$(ASC): $(JSON) $(PCF) | $(BUILD)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --json $(JSON) --pcf $(PCF) --asc $(ASC) --seed $(SEED) 2>&1 | $(LOG_CMD)

bitstream: $(BIN)

$(BIN): $(ASC) | $(BUILD)
	$(ICEPACK) $(ASC) $(BIN) 2>&1 | $(LOG_CMD)

abstract:
	netlistsvg $(JSON) -o $(BUILD)/$(TOP).svg
	@if command -v rsvg-convert >/dev/null 2>&1; then \
		rsvg-convert -f pdf -o $(BUILD)/$(TOP).pdf $(BUILD)/$(TOP).svg; \
	elif command -v inkscape >/dev/null 2>&1; then \
		inkscape $(BUILD)/$(TOP).svg --export-type=pdf --export-filename=$(BUILD)/$(TOP).pdf; \
	else \
		echo 'warning: rsvg-convert or inkscape not found, skipping pdf export'; \
	fi

clean:
	rm -rf $(BUILD)
	rm -f $(MAG_LUT)
	rm -rf *.txt
