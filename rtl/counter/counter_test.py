"""Coverage: reset (sync/async), up/down/hold/load, enable gating, wrap behavior."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10

def get_params(dut):
    """Set parameters in Python from DUT"""
    return {
        "WIDTH_P": int(dut.WIDTH_P.value),
        "MAX_VAL_P": int(dut.MAX_VAL_P.value),
        "SATURATE_P": int(dut.SATURATE_P.value),
    }

async def counter_clock_test(dut):
    """Start clock sequence"""
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, units="ns").start())
    await Timer(5 * CLK_PERIOD_NS, units="ns")

async def init_dut(dut):
    """Drive known reset/default values to clear Xs before testing."""
    dut.rstn_i.value = 0
    dut.en_i.value = 0
    dut.load_i.value = 0
    dut.up_i.value = 0
    dut.down_i.value = 0
    dut.data_i.value = 0
    await FallingEdge(dut.clk_i)
    
    dut.rstn_i.value = 1
    await FallingEdge(dut.clk_i)
    

async def counter_reset_sync_test(dut):
    """Reset sync test"""
    width = int(dut.WIDTH_P.value)
    preload = (1 << (width - 1)) if width > 1 else 1

    dut.rstn_i.value = 1
    dut.en_i.value = 1
    dut.load_i.value = 1
    dut.up_i.value = 0
    dut.down_i.value = 0
    dut.data_i.value = preload
    await FallingEdge(dut.clk_i)
    
    pre_reset_val = int(dut.count_o.value) & ((1 << width) - 1)
    assert pre_reset_val == preload, f"Preload failed expected {preload} got {pre_reset_val}"

    dut.rstn_i.value = 0
    dut.load_i.value = 0
    await FallingEdge(dut.clk_i)
    
    cleared = int(dut.count_o.value) & ((1 << width) - 1)
    assert cleared == 0, f"Sync reset failed to clear from {pre_reset_val}, got {cleared}"
    dut.rstn_i.value = 1

async def counter_reset_async_test(dut):
    """Reset async test"""
    width = int(dut.WIDTH_P.value)
    preload = (1 << (width - 1)) if width > 1 else 1

    dut.rstn_i.value = 1
    dut.en_i.value = 1
    dut.load_i.value = 1
    dut.up_i.value = 0
    dut.down_i.value = 0
    dut.data_i.value = preload
    await FallingEdge(dut.clk_i)
    
    pre_reset_val = int(dut.count_o.value) & ((1 << width) - 1)
    assert pre_reset_val == preload, f"Preload failed expected {preload} got {pre_reset_val}"

    await Timer(CLK_PERIOD_NS // 2, units="ns")
    dut.rstn_i.value = 0
    await FallingEdge(dut.clk_i)
    
    cleared = int(dut.count_o.value) & ((1 << width) - 1)
    assert cleared == 0, f"Async reset failed to clear from {pre_reset_val}, got {cleared}"
    dut.rstn_i.value = 1

async def counter_up_test(dut):
    """Counter increment test"""
    width = int(dut.WIDTH_P.value)
    dut.rstn_i.value = 1
    dut.en_i.value = 1
    dut.load_i.value = 1
    dut.up_i.value = 1
    dut.down_i.value = 0
    dut.data_i.value = 0
    await FallingEdge(dut.clk_i)
    
    dut.load_i.value = 0
    pre_increment = int(dut.count_o.value) & ((1 << width) - 1)
    await FallingEdge(dut.clk_i)
    
    got = int(dut.count_o.value) & ((1 << width) - 1)
    assert got == (pre_increment + 1) & ((1 << width) - 1), f"Increment failed expected {pre_increment + 1} got {got}"

async def counter_down_test(dut):
    """Counter decrement test"""
    width = int(dut.WIDTH_P.value)
    dut.en_i.value = 1
    dut.load_i.value = 1
    dut.up_i.value = 0
    dut.down_i.value = 1
    dut.data_i.value = 3
    await FallingEdge(dut.clk_i)
    
    dut.load_i.value = 0
    pre_decrement = int(dut.count_o.value) & ((1 << width) - 1)
    await FallingEdge(dut.clk_i)
    
    got = int(dut.count_o.value) & ((1 << width) - 1)
    assert got == (pre_decrement - 1) & ((1 << width) - 1), f"Decrement failed expected {pre_decrement - 1} got {got}"

async def counter_up_down_test(dut):
    """Counter simulataneous up down test"""
    width = int(dut.WIDTH_P.value)
    dut.en_i.value = 1
    dut.load_i.value = 1
    dut.up_i.value = 1
    dut.down_i.value = 1
    dut.data_i.value = 0
    await FallingEdge(dut.clk_i)
    
    dut.load_i.value = 0
    pre_increment = int(dut.count_o.value) & ((1 << width) - 1)
    await FallingEdge(dut.clk_i)
    
    got = int(dut.count_o.value) & ((1 << width) - 1)
    assert got == pre_increment, f"Simultaneous up/down should hold: expected {pre_increment} got {got}"

async def counter_none_test(dut):
    """Counter no up down test"""
    width = int(dut.WIDTH_P.value)
    dut.en_i.value = 1
    dut.load_i.value = 1
    dut.up_i.value = 0
    dut.down_i.value = 0
    dut.data_i.value = 0
    await FallingEdge(dut.clk_i)
    
    dut.load_i.value = 0
    pre_increment = int(dut.count_o.value) & ((1 << width) - 1)
    await FallingEdge(dut.clk_i)
    
    got = int(dut.count_o.value) & ((1 << width) - 1)
    assert got == pre_increment, f"No-op count mismatch expected {pre_increment} got {got}"

async def counter_load_test(dut):
    """Counter load test"""
    width = int(dut.WIDTH_P.value)
    load_val = ((1 << width) - 1) >> 1 if width > 1 else 1
    dut.en_i.value = 1
    dut.load_i.value = 1
    dut.up_i.value = 0
    dut.down_i.value = 0
    dut.data_i.value = load_val
    await FallingEdge(dut.clk_i)
    
    got = int(dut.count_o.value) & ((1 << width) - 1)
    assert got == load_val, f"Load failed expected {load_val} got {got}"
    dut.load_i.value = 0

async def counter_saturate_test(dut):
    """Counter saturating increment test"""
    width = int(dut.WIDTH_P.value)
    max_val = (1 << width) - 1
    dut.en_i.value = 1
    dut.load_i.value = 1
    dut.up_i.value = 1
    dut.down_i.value = 0
    dut.data_i.value = max_val
    await FallingEdge(dut.clk_i)
    
    dut.load_i.value = 0
    await FallingEdge(dut.clk_i)
    
    wrapped = int(dut.count_o.value) & ((1 << width) - 1)
    assert wrapped == 0, f"Wrap from max expected 0 got {wrapped}"

async def counter_enable_test(dut):
    """Counter enable test"""
    width = int(dut.WIDTH_P.value)
    dut.en_i.value = 0
    dut.load_i.value = 1
    dut.up_i.value = 1
    dut.down_i.value = 0
    dut.data_i.value = 5 & ((1 << width) - 1)
    await FallingEdge(dut.clk_i)
    
    dut.load_i.value = 0
    held = int(dut.count_o.value) & ((1 << width) - 1)

    await FallingEdge(dut.clk_i)
    
    got = int(dut.count_o.value) & ((1 << width) - 1)
    assert got == held, f"Enable low should hold count expected {held} got {got}"

    dut.en_i.value = 1
    await FallingEdge(dut.clk_i)
    
    expected = (held + 1) & ((1 << width) - 1)
    got = int(dut.count_o.value) & ((1 << width) - 1)
    assert got == expected, f"Enable high should increment expected {expected} got {got}"

@cocotb.test()
async def run_counter_tests(dut):
    """Test runner"""
    params = get_params(dut)
    await counter_clock_test(dut)
    await init_dut(dut)
    await counter_reset_sync_test(dut)
    await counter_up_test(dut)
    await counter_down_test(dut)
    await counter_up_down_test(dut)
    await counter_none_test(dut)
    await counter_load_test(dut)
    await counter_saturate_test(dut)
    await counter_enable_test(dut)
    await counter_reset_async_test(dut)
    await counter_reset_sync_test(dut)
