"""Coverage: deterministic edges (zeros, ones, carry ripple) plus random vectors."""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10

def get_params(dut):
    """Set parameters in Python from DUT"""
    return {"WIDTH_P": int(dut.WIDTH_P.value)}

@cocotb.test()
async def run_add_tests(dut):
    """Run all add tests."""

    params = get_params(dut)
    width = params["WIDTH_P"]

    edge_vectors = [
        (0, 0, 0),
        ((1 << width) - 1, 0, 0),
        ((1 << width) - 1, 1, 0),  # overflow to carry
        ((1 << (width - 1)), (1 << (width - 1)), 0),  # MSB carry
        (0xAAAAAAAA & ((1 << width) - 1), 0x55555555 & ((1 << width) - 1), 1),
    ]

    for a_val, b_val, c_val in edge_vectors:
        dut.a_i.value = a_val
        dut.b_i.value = b_val
        dut.cin_i.value = c_val
        await Timer(1, "step")
        total = a_val + b_val + c_val
        expected_sum = total & ((1 << width) - 1)
        expected_carry = (total >> width) & 0x1
        assert int(dut.sum_o.value) == int(expected_sum), f"SUM mismatch: a={a_val}, b={b_val}, c={c_val}, got={int(dut.sum_o)}, expected={expected_sum}"
        assert int(dut.carry_o.value) == int(expected_carry), f"CARRY mismatch: a={a_val}, b={b_val}, c={c_val}, got={int(dut.carry_o)}, expected={expected_carry}"

    for _ in range(500):
        a_val = random.randint(0, 2**width-1)
        b_val = random.randint(0, 2**width-1)
        c_val = random.randint(0, 1)
        dut.a_i.value = a_val
        dut.b_i.value = b_val
        dut.cin_i.value = c_val
        await Timer(1, "step")
        total = a_val + b_val + c_val
        expected_sum = total & ((1 << width) - 1)
        expected_carry = (total >> width) & 0x1
        assert int(dut.sum_o.value) == int(expected_sum), f"SUM mismatch: a={a_val}, b={b_val}, c={c_val}, got={int(dut.sum_o)}, expected={expected_sum}"
        assert int(dut.carry_o.value) == int(expected_carry), f"CARRY mismatch: a={a_val}, b={b_val}, c={c_val}, got={int(dut.carry_o)}, expected={expected_carry}"

    print("Add edge and random tests passed")
