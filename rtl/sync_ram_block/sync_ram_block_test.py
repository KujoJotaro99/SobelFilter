"""Coverage: reset, single and multi read/write, random traffic, boundary address, read/write priority."""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10

def get_params(dut):
    """Set parameters in Python from DUT"""
    return {
        "WIDTH_P": int(dut.WIDTH_P.value),
        "DEPTH_P": int(dut.DEPTH_P.value),
    }

async def test_sync_ram_block_reset(dut, width, depth):
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

async def test_sync_ram_block_write_read_single(dut, width, depth):
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

async def test_sync_ram_block_write_read_multi_separate(dut, width, depth):
    """Test multiple write and read behavior of sync RAM block."""
    random_stream = [random.randint(0, 2**width - 1) for _ in range(min(10, depth))]
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

async def test_sync_ram_block_boundary_addr(dut, width, depth):
    """Test write/read at last valid address."""
    last_addr = depth - 1
    dut.wr_en_i.value = 1
    dut.rd_en_i.value = 0
    dut.wr_addr_i.value = last_addr
    dut.data_i.value = (1 << width) - 1
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    dut.wr_en_i.value = 0
    dut.rd_en_i.value = 1
    dut.rd_addr_i.value = last_addr
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    assert int(dut.data_o.value) == (1 << width) - 1, f"Boundary read mismatch: got={int(dut.data_o.value)}"

async def test_sync_ram_block_same_cycle_rd_wr(dut, width, depth):
    """Test same-cycle read and write to the same address (read returns old data)."""
    addr = 0
    old_val = 7
    new_val = 13

    # preload old value
    dut.wr_en_i.value = 1
    dut.rd_en_i.value = 0
    dut.wr_addr_i.value = addr
    dut.data_i.value = old_val
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")

    # simultaneous rd/wr, expect old data on read
    dut.wr_en_i.value = 1
    dut.rd_en_i.value = 1
    dut.wr_addr_i.value = addr
    dut.rd_addr_i.value = addr
    dut.data_i.value = new_val
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    assert int(dut.data_o.value) == old_val, f"Simultaneous rd/wr should return old data, got {int(dut.data_o.value)}"

    # confirm new data visible next read
    dut.wr_en_i.value = 0
    dut.rd_en_i.value = 1
    await FallingEdge(dut.clk_i)
    await Timer(1, "step")
    assert int(dut.data_o.value) == new_val, f"Updated data not visible: got {int(dut.data_o.value)}"

async def test_sync_ram_block_write_read_multi_random(dut, width, depth):
    """Test multiple random write and read behavior of sync RAM block."""
    random_stream = [random.randint(0, 2**width - 1) for _ in range(depth)]
    addr_queue = []
    wr_addr = 0
    rd_addr = 0

    dut.wr_en_i.value = 0
    dut.rd_en_i.value = 0
    dut.rd_addr_i.value = rd_addr
    dut.wr_addr_i.value = wr_addr
    await FallingEdge(dut.clk_i)

    for _ in range(50):
        dut.wr_en_i.value = random.randint(0,1) if random_stream else 0
        dut.rd_en_i.value = random.randint(0,1) if addr_queue else 0

        if dut.wr_en_i.value:
            val = random_stream.pop() if random_stream else random.randint(0, 2**width - 1)
            dut.data_i.value = val
            addr_queue.append((wr_addr, val))

        await FallingEdge(dut.clk_i)

        if dut.wr_en_i.value:
            wr_addr = (wr_addr + 1) % depth
            dut.wr_addr_i.value = wr_addr

        if dut.rd_en_i.value:
            for a, v in addr_queue:
                if a == rd_addr:
                    assert int(dut.data_o.value) == v, f"Read mismatch at addr {rd_addr}: expected {v}, got {int(dut.data_o.value)}"
                    break

        await FallingEdge(dut.clk_i)

        if dut.rd_en_i.value:
            addr_queue = [entry for entry in addr_queue if entry[0] != rd_addr]
            rd_addr = (rd_addr + 1) % depth
            dut.rd_addr_i.value = rd_addr


@cocotb.test(skip=False)
async def run_sync_ram_block_tests(dut):
    """Run all sync ram block tests."""
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, units="ns").start())

    params = get_params(dut)
    width = params["WIDTH_P"]
    depth = params["DEPTH_P"]

    await test_sync_ram_block_reset(dut, width, depth)
    print("Reset test passed")

    await test_sync_ram_block_write_read_single(dut, width, depth)
    print("Single write/read test passed")

    await test_sync_ram_block_write_read_multi_separate(dut, width, depth)
    print("Multiple write/read test passed")

    await test_sync_ram_block_boundary_addr(dut, width, depth)
    print("Boundary address test passed")

    await test_sync_ram_block_same_cycle_rd_wr(dut, width, depth)
    print("Same-cycle rd/wr test passed")

    await test_sync_ram_block_write_read_multi_random(dut, width, depth)
    print("Random write/read test passed")
