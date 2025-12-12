#!/bin/bash

# CLI/venv setup script for project

# python install check
if ! command python3 --version &> /dev/null
then
    echo "python3 could not be found, please install Python 3."
    exit 1
fi

# create venv
python3 -m venv venv

# activate venv
source venv/bin/activate

# verilator install check
if ! command -v verilator > /dev/null 2>&1
then
    echo "Verilator could not be found, installing..."
    command brew install verilator > /dev/null 2>&1
fi 

# icarus install check
if ! command -v iverilog > /dev/null 2>&1
then
    echo "Icarus could not be found, installing..."
    command brew install icarus-verilog --HEAD > /dev/null 2>&1
fi

# yosys install check
if ! command -v yosys > /dev/null 2>&1
then
    echo "Yosys could not be found, installing..."
    command brew install yosys > /dev/null 2>&1
fi

# icestorm install check
if ! command -v icepack >/dev/null 2>&1
then 
    echo "Icestorm could not be found, installing..."
    command brew install --HEAD ktemkin/oss-fpga/icestorm > /dev/null 2>&1
    command brew reinstall icestorm > /dev/null 2>&1
fi

# nextpnr install check
if ! command -v nextpnr-ice40 >/dev/null 2>&1
then 
    echo "Nextpnr could not be found, installing..."
    command brew install nextpnr-ice40 > /dev/null 2>&1
fi

# submodules install check
if [ ! -d submodules/basejump_stl ] || [ -z "$(ls -A submodules/basejump_stl 2>/dev/null)" ]; 
then
    echo "BaseJump STL submodule could not be found, initializing..."
    git submodule update --init --recursive
fi

# misc dependencies
pip install -r requirements.txt > /dev/null 2>&1
 

