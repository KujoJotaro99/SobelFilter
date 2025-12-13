"""Coverage: truth table over 1-bit inputs."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10

def get_params(dut):
    """Set parameters in Python from DUT"""
    return {"WIDTH": len(dut.a_i)}


@cocotb.test(skip=False)
async def run_half_add_tests(dut):
    """Run all half_add tests."""

    params = get_params(dut)
    width = params["WIDTH"]
    for a_val in (0, 1):
        for b_val in (0, 1):
            dut.a_i.value = a_val
            dut.b_i.value = b_val
            await Timer(1, "step")
            expected_sum = a_val ^ b_val
            expected_carry = a_val & b_val
            assert dut.sum_o.value == expected_sum, f"SUM mismatch: a={a_val}, b={b_val}, got={int(dut.sum_o)}, expected={expected_sum}"
            assert dut.carry_o.value == expected_carry, f"CARRY mismatch: a={a_val}, b={b_val}, got={int(dut.carry_o)}, expected={expected_carry}"
    print("Half add truth table passed")
