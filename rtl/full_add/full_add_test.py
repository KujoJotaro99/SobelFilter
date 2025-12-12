import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10

async def full_add_test(dut):
    """Test behavior of full_add."""
    a_val = random.randint(0, 1)
    b_val = random.randint(0, 1)
    c_val = random.randint(0, 1)
    dut.a_i.value = a_val
    dut.b_i.value = b_val
    dut.cin_i.value = c_val
    await Timer(1, "step")
    expected_sum = a_val ^ b_val ^ c_val 
    expected_carry = ((a_val ^ b_val) & c_val) | (a_val & b_val)
    assert dut.sum_o.value == expected_sum, f"SUM mismatch: a={a_val}, b={b_val}, got={int(dut.sum_o)}, expected={expected_sum}"
    assert dut.carry_o.value == expected_carry, f"CARRY mismatch: a={a_val}, b={b_val}, got={int(dut.carry_o)}, expected={expected_carry}"


@cocotb.test(skip=False)
async def run_full_add_tests(dut):
    """Run all full_add tests."""

    for _ in range(10):
        await full_add_test(dut)
    print("Half add test passed")
