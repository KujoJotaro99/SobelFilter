"""Coverage: edge patterns (including negative for SRA), invalid op default, plus random."""

import random

import cocotb
from cocotb.triggers import Timer

SLL = 0
SRL = 1
SRA = 2

def get_params(dut):
    """Set parameters in Python from DUT"""
    return {"WIDTH_P": int(dut.WIDTH_P.value)}

def mask_width(value: int, width: int) -> int:
    """Function to model the overflow in hardware """
    return value & ((1 << width) - 1) # mask with 1 << 32 - 1 = 4294967295

def sra(value: int, shamt: int, width: int) -> int:
    """Arithmetic right shift model with sign extension for WIDTH-bit values."""
    signed_val = value if value < (1 << (width - 1)) else value - (1 << width)
    return mask_width(signed_val >> shamt, width)


async def shift_case(dut, op: int, data: int, shamt: int, width: int):
    """Shift test sequence"""
    dut.data_i.value = data
    dut.shamt_i.value = shamt
    dut.op_i.value = op

    await Timer(1, "step")

    if op == SLL:
        expected = mask_width(data << shamt, width)
    elif op == SRL:
        expected = mask_width(data, width) >> shamt
    elif op == SRA:
        expected = sra(mask_width(data, width), shamt, width)
    else:
        expected = mask_width(data, width)

    assert int(dut.shift_o.value) == expected, (
        f"Shift mismatch: op={op}, data=0x{data:08X}, shamt={shamt}, "
        f"got=0x{int(dut.shift_o.value):08X}, expected=0x{expected:08X}"
    )


@cocotb.test()
async def run_shift_tests(dut):
    """Wrapper for logical/arithmetic shift tests across random data."""

    params = get_params(dut)
    width = params["WIDTH_P"]
    msb_mask = (1 << (width - 1)) if width else 0
    edge_data = [
        0x00000000,  # all zeros
        (1 << width) - 1,  # all ones
        msb_mask,  # MSB set (negative for SRA)
        msb_mask | 0x1,  # negative odd pattern
        0x01234567 & ((1 << width) - 1),  # mixed pattern
    ]
    edge_shifts = [0, 1, width // 2, max(width - 1, 0)]
    for data in edge_data:
        for shamt in edge_shifts:
            for op in (SLL, SRL, SRA, 3):
                await shift_case(dut, op, data, shamt, width)

    # randomized checks
    for _ in range(50):
        data = random.randint(0, (1 << width) - 1)
        shamt = random.randint(0, max(width - 1, 0))
        for op in (SLL, SRL, SRA):
            await shift_case(dut, op, data, shamt, width)

    print("Shift tests passed")
