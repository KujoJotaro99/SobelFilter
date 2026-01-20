SIM ?= icarus
TOPLEVEL_LANG ?= verilog

FILELIST_JSON := filelist.json

RTL_SOURCES := $(shell python3 -c "import json; \
    j=json.load(open('$(FILELIST_JSON)')); \
    print(' '.join(j['files']))")

VERILOG_SOURCES := $(RTL_SOURCES)

TOPLEVEL := $(shell python3 -c "import json; \
    print(json.load(open('$(FILELIST_JSON)'))['top'])")
	
MODULE := dvp_axis_test

COCOTB_LOG_LEVEL ?= INFO

COMPILE_ARGS += -g2012

WAVES ?= 1

TB_SV := i2c_fsm_tb.sv

ifneq ($(filter sv,$(MAKECMDGOALS)),)
    # skip cocotb i jsut include for pure SystemVerilog run
else
include $(shell cocotb-config --makefile)/Makefile.sim
endif

.PHONY: clean
clean::
	rm -rf sim_build __pycache__ .pytest_cache *.pyc *.vcd *.fst results.xml sim_sv

.PHONY: sweep

sweep:
	$(MAKE) WIDTH_P=8
	$(MAKE) WIDTH_P=16
	$(MAKE) WIDTH_P=32

lint:
	verilator --lint-only $(RTL_SOURCES) --top-module $(TOPLEVEL)

.PHONY: python
python: SIM=icarus
python: clean
	$(MAKE) MODULE=$(MODULE)

.PHONY: sv
sv: clean
	iverilog $(COMPILE_ARGS) -s i2c_fsm_tb -o sim_sv $(VERILOG_SOURCES) $(TB_SV)
	vvp sim_sv
