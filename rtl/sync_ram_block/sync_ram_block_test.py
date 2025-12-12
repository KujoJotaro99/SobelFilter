import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10
WIDTH_P = 8
DEPTH_P = 128

async def test_sync_ram_block_reset(dut):
    """Test reset behavior of sync RAM block."""
    dut.rstn_i.value = 1
    dut.wr_en_i.value = 0
    dut.rd_en_i.value = 0
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    dut.rstn_i.value = 0
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    assert dut.data_o.value == 0, f"Reset failed: data_o={dut.data_o.value}"

async def test_sync_ram_block_write_read_single(dut):
    """Test single write and read behavior of sync RAM block."""
    dut.rstn_i.value = 1
    dut.wr_en_i.value = 1
    dut.rd_en_i.value = 0
    dut.wr_addr_i.value = 0
    dut.rd_addr_i.value = 0
    dut.data_i.value = 42
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    dut.wr_en_i.value = 0
    dut.rd_en_i.value = 1
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    assert int(dut.data_o.value) == 42, f"Read data mismatch: got={int(dut.data_o.value)}, expected=42"

async def test_sync_ram_block_write_read_multi_separate(dut):
    """Test multiple write and read behavior of sync RAM block."""
    random_stream = [random.randint(0, 2**WIDTH_P - 1) for _ in range(10)]
    for i, val in enumerate(random_stream):
        dut.rstn_i.value = 1
        dut.wr_en_i.value = 1
        dut.rd_en_i.value = 0
        dut.wr_addr_i.value = i
        dut.rd_addr_i.value = i
        dut.data_i.value = val
        await FallingEdge(dut.clk_i)
        await Timer(1, "step")
    for i, val in enumerate(random_stream):
        dut.wr_en_i.value = 0
        dut.rd_en_i.value = 1
        dut.rd_addr_i.value = i
        await FallingEdge(dut.clk_i)
        await Timer(1, "step")
        await FallingEdge(dut.clk_i)
        await Timer(1, "step")
        assert int(dut.data_o.value) == val, f"Read data mismatch at addr {i}: got={int(dut.data_o.value)}, expected={val}"

async def test_sync_ram_block_write_read_multi_random(dut):
    """Test multiple random write and read behavior of sync RAM block."""
    random_stream = [random.randint(0, 2**WIDTH_P - 1) for _ in range(128)]
    addr_queue = []
    wr_addr = 0
    rd_addr = 0

    dut.wr_en_i.value = 0
    dut.rd_en_i.value = 0
    dut.rd_addr_i.value = rd_addr
    dut.wr_addr_i.value = wr_addr
    await FallingEdge(dut.clk_i)

    for _ in range(50):
        dut.wr_en_i.value = random.randint(0,1)
        dut.rd_en_i.value = random.randint(0,1) if (rd_addr < wr_addr) else 0

        if dut.wr_en_i.value:
            val = random_stream.pop() if random_stream else random.randint(0, 2**WIDTH_P - 1)
            dut.data_i.value = val
            addr_queue.append((wr_addr, val))

        await FallingEdge(dut.clk_i)

        if dut.wr_en_i.value:
            wr_addr += 1
            dut.wr_addr_i.value = wr_addr

        if dut.rd_en_i.value:
            for a, v in addr_queue:
                if a == rd_addr:
                    assert int(dut.data_o.value) == v, f"Read mismatch at addr {rd_addr}: expected {v}, got {int(dut.data_o.value)}"
                    break

        await FallingEdge(dut.clk_i)

        if dut.rd_en_i.value:
            rd_addr += 1
            dut.rd_addr_i.value = rd_addr


@cocotb.test(skip=False)
async def run_sync_ram_block_tests(dut):
    """Run all sync ram block tests."""
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, units="ns").start())

    await test_sync_ram_block_reset(dut)
    print("Reset test passed")

    await test_sync_ram_block_write_read_single(dut)
    print("Single write/read test passed")

    await test_sync_ram_block_write_read_multi_separate(dut)
    print("Multiple write/read test passed")

    await test_sync_ram_block_write_read_multi_random(dut)
    print("Random write/read test passed")
