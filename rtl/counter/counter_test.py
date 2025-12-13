import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

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

async def counter_reset_sync_test(dut):
    """Reset sync test"""
    width = int(dut.WIDTH_P.value)
    # load in 2^width-1
    preload = (1 << (width - 1)) if width > 1 else 1

    dut.rstn_i.value = 1
    dut.en_i.value = 1
    dut.load_i.value = 1
    dut.up_i.value = 0
    dut.down_i.value = 0
    dut.data_i.value = preload
    await RisingEdge(dut.clk_i)
    await Timer(1, units="ns")
    pre_reset_val = int(dut.count_o.value)
    assert pre_reset_val == preload, f"Preload failed expected {preload} got {pre_reset_val}"

    dut.rstn_i.value = 0
    dut.load_i.value = 0
    await RisingEdge(dut.clk_i)
    await Timer(1, units="ns")
    assert int(dut.count_o.value) == 0, f"Sync reset failed to clear from {pre_reset_val}, got {int(dut.count_o.value)}"
    dut.rstn_i.value = 1

async def counter_reset_async_test(dut):
    """Reset async test"""
    width = int(dut.WIDTH_P.value)
    # load in 2^width-1
    preload = (1 << (width - 1)) if width > 1 else 1

    dut.rstn_i.value = 1
    dut.en_i.value = 1
    dut.load_i.value = 1
    dut.up_i.value = 0
    dut.down_i.value = 0
    dut.data_i.value = preload
    await RisingEdge(dut.clk_i)
    await Timer(1, units="ns")
    pre_reset_val = int(dut.count_o.value)
    assert pre_reset_val == preload, f"Preload failed expected {preload} got {pre_reset_val}"

    # assert reset between edges to mimic async request; counter is synchronous so clearing occurs on next edge
    await Timer(CLK_PERIOD_NS // 2, units="ns")
    dut.rstn_i.value = 0
    await RisingEdge(dut.clk_i)
    await Timer(1, units="ns")
    assert int(dut.count_o.value) == 0, f"Async reset failed to clear from {pre_reset_val}, got {int(dut.count_o.value)}"
    dut.rstn_i.value = 1

async def counter_up_test(dut):
    """Counter increment test"""
    pass

async def counter_down_test(dut):
    """Counter decrement test"""
    pass

async def counter_load_test(dut):
    """Counter load test"""
    pass

async def counter_saturate_test(dut):
    """Counter saturating increment test"""
    pass

async def counter_enable_test(dut):
    """Counter enable test"""
    pass

@cocotb.test()
async def run_counter_tests(dut):
    """Test runner"""
    params = get_params(dut)
    await counter_clock_test(dut)
    await counter_reset_sync_test(dut)
    await counter_up_test(dut)
    await counter_down_test(dut)
    await counter_load_test(dut)
    await counter_saturate_test(dut)
    await counter_enable_test(dut)
    await counter_reset_async_test(dut)
    await counter_reset_sync_test(dut)
