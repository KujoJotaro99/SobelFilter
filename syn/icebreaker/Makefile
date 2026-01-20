TOP := sobel
RTL_DIR := ../../rtl/sobel
FILELIST := $(RTL_DIR)/filelist.json
PCF := icebreaker.pcf
BUILD := build

YOSYS := yosys
NEXTPNR := nextpnr-ice40
ICEPACK := icepack

DEVICE := up5k
PACKAGE := sg48

VERILOG_SOURCES := $(shell python3 -c "import json; \
    j=json.load(open('$(FILELIST)')); \
    print(' '.join('$(RTL_DIR)/' + f for f in j['files']))")

JSON := $(BUILD)/$(TOP).json
ASC := $(BUILD)/$(TOP).asc
BIN := $(BUILD)/$(TOP).bin

.PHONY: all netlist place bitstream clean

all: bitstream

$(BUILD):
	mkdir -p $(BUILD)

netlist: $(JSON)

$(JSON): $(VERILOG_SOURCES) | $(BUILD)
	$(YOSYS) -p "read_verilog -sv $(VERILOG_SOURCES); synth_ice40 -top $(TOP) -json $(JSON)"

place: $(ASC)

$(ASC): $(JSON) $(PCF) | $(BUILD)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --json $(JSON) --pcf $(PCF) --asc $(ASC)

bitstream: $(BIN)

$(BIN): $(ASC) | $(BUILD)
	$(ICEPACK) $(ASC) $(BIN)

clean:
	rm -rf $(BUILD)
