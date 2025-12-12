import random

import cocotb
from cocotb.triggers import Timer

WIDTH = 32
SLL = 0
SRL = 1
SRA = 2

def mask_width(value: int) -> int:
    """Function to model the overflow in hardware """
    return value & ((1 << WIDTH) - 1) # mask with 1 << 32 - 1 = 4294967295


def sra(value: int, shamt: int) -> int:
    """Arithmetic right shift model with sign extension for WIDTH-bit values."""
    # need to subtract by ma value to get negative($signed) representation in python
    # 0111 is 7
    # 1000 is 8 in python not -8 so 8-16 is -8
    signed_val = value if value < (1 << (WIDTH - 1)) else value - (1 << WIDTH) 
    return mask_width(signed_val >> shamt)


async def shift_case(dut, op: int, data: int, shamt: int):
    """Shift test sequence"""
    dut.data_i.value = data
    dut.shamt_i.value = shamt
    dut.op_i.value = op

    await Timer(1, "step")

    if op == SLL:
        expected = mask_width(data << shamt)
    elif op == SRL:
        expected = mask_width(data) >> shamt
    elif op == SRA:
        expected = sra(mask_width(data), shamt)
    else:
        expected = mask_width(data)

    assert int(dut.shift_o.value) == expected, (
        f"Shift mismatch: op={op}, data=0x{data:08X}, shamt={shamt}, "
        f"got=0x{int(dut.shift_o.value):08X}, expected=0x{expected:08X}"
    )


@cocotb.test()
async def run_shift_tests(dut):
    """Wrapper for logical/arithmetic shift tests across random data."""

    edge_data = [
        0x00000000,  # all zeros
        0xFFFFFFFF,  # all ones
        0x80000000,  # MSB set
        0x7FFFFFFF,  # MSB clear
        0x01234567,  # mixed pattern
    ]
    edge_shifts = [0, 1, WIDTH // 2, WIDTH - 1]
    for data in edge_data:
        for shamt in edge_shifts:
            for op in (SLL, SRL, SRA):
                await shift_case(dut, op, data, shamt)

    # randomized checks
    for _ in range(50):
        data = random.randint(0, (1 << WIDTH) - 1)
        shamt = random.randint(0, WIDTH - 1)
        for op in (SLL, SRL, SRA):
            await shift_case(dut, op, data, shamt)

    print("Shift tests passed")
