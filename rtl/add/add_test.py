import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10
WIDTH = 32

async def add_random_test(dut):
    """Test behavior of carry lookahead add."""
    a_val = random.randint(0, 2**WIDTH-1)
    b_val = random.randint(0, 2**WIDTH-1)
    c_val = random.randint(0, 1)
    dut.a_i.value = a_val
    dut.b_i.value = b_val
    dut.cin_i.value = c_val
    await Timer(1, "step")
    total = a_val + b_val + c_val
    expected_sum = total & ((1 << WIDTH) - 1) # everything except msb
    expected_carry = (total >> WIDTH) & 0x1 # only msb
    assert int(dut.sum_o.value) == int(expected_sum), f"SUM mismatch: a={a_val}, b={b_val}, c={c_val}, got={int(dut.sum_o)}, expected={expected_sum}"
    assert int(dut.carry_o.value) == int(expected_carry), f"CARRY mismatch: a={a_val}, b={b_val}, c={c_val}, got={int(dut.carry_o)}, expected={expected_carry}"

@cocotb.test()
async def run_add_tests(dut):
    """Run all add tests."""

    for _ in range(1000):
        await add_random_test(dut)
    print("add random test passed")
