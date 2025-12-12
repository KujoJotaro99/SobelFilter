import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10

async def test_dff_posedge_sync_reset(dut):
    """Test reset behavior on posedge clock."""
    dut.rstn_i.value = 1
    dut.d_i.value = 1
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 0
    await RisingEdge(dut.clk_i)
    await Timer(1, "step")
    assert dut.q_o.value == 0, f"Reset failed: q_o={dut.q_o.value}"


async def test_dff_posedge_sync_sample(dut):
    """Test data sampling behavior on posedge clock."""
    dut.rstn_i.value = 1
    dut.d_i.value = 1
    await FallingEdge(dut.clk_i)
    dut.d_i.value = 0
    await RisingEdge(dut.clk_i)
    await Timer(1, "step")
    assert dut.q_o.value == dut.d_i.value, f"Sample failed: q_o={dut.q_o.value}"


async def test_dff_posedge_sync_reset_negedge(dut):
    """Test reset behavior on negedge clock."""
    dut.rstn_i.value = 1
    dut.d_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.rstn_i.value = 0
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    assert dut.q_o.value == dut.d_i.value, f"Reset failed: q_o={dut.q_o.value}"


async def test_dff_posedge_sync_sample_negedge(dut):
    """Test data sampling behavior on negedge clock."""
    dut.rstn_i.value = 1
    dut.d_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.d_i.value = 0
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    assert dut.q_o.value == 1, f"Sample failed: q_o={dut.q_o.value}"


@cocotb.test(skip=False)
async def run_dff_posedge_sync_tests(dut):
    """Run all DFF posedge sync tests."""
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, units="ns").start())

    await test_dff_posedge_sync_reset(dut)
    print("Posedge sync reset test passed")

    await test_dff_posedge_sync_sample(dut)
    print("Posedge sync sample test passed")

    await test_dff_posedge_sync_reset_negedge(dut)
    print("Negedge sync reset test passed")

    await test_dff_posedge_sync_sample_negedge(dut)
    print("Negedge sync sample test passed")
