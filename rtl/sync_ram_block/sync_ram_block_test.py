"""Coverage: reset, single and multi read/write, random traffic, boundary address, read/write priority, no dual read tests yet"""

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
    dut.rd_en_a_i.value = 0
    dut.rd_en_b_i.value = 0
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 0
    await FallingEdge(dut.clk_i)
    assert dut.data_a_o.value == 0, f"Reset failed: data_a_o={dut.data_a_o.value}"

async def test_sync_ram_block_write_read_single(dut, width, depth):
    """Test single write and read behavior of sync RAM block."""
    dut.rstn_i.value = 1
    dut.wr_en_i.value = 1
    dut.rd_en_a_i.value = 0
    dut.rd_en_b_i.value = 0
    dut.wr_addr_i.value = 0
    dut.rd_addr_a_i.value = 0
    dut.data_i.value = 42
    await FallingEdge(dut.clk_i)
    dut.wr_en_i.value = 0
    dut.rd_en_a_i.value = 1
    await FallingEdge(dut.clk_i)
    dut.rd_en_a_i.value = 0
    await FallingEdge(dut.clk_i)
    assert int(dut.data_a_o.value) == 42, f"Read data mismatch: got={int(dut.data_a_o.value)}, expected=42"

async def test_sync_ram_block_write_read_multi_separate(dut, width, depth):
    """Test multiple write and read behavior of sync RAM block."""
    random_stream = [random.randint(0, 2**width - 1) for _ in range(min(10, depth))]
    for i, val in enumerate(random_stream):
        dut.rstn_i.value = 1
        dut.wr_en_i.value = 1
        dut.rd_en_a_i.value = 0
        dut.wr_addr_i.value = i
        dut.rd_addr_a_i.value = i
        dut.data_i.value = val
        await FallingEdge(dut.clk_i)
    for i, val in enumerate(random_stream):
        dut.wr_en_i.value = 0
        dut.rd_en_a_i.value = 1
        dut.rd_addr_a_i.value = i
        await FallingEdge(dut.clk_i)
        await FallingEdge(dut.clk_i)
        assert int(dut.data_a_o.value) == val, f"Read data mismatch at addr {i}: got={int(dut.data_a_o.value)}, expected={val}"

async def test_sync_ram_block_boundary_addr(dut, width, depth):
    """Test write/read at last valid address."""
    last_addr = depth - 1
    dut.wr_en_i.value = 1
    dut.rd_en_a_i.value = 0
    dut.wr_addr_i.value = last_addr
    dut.data_i.value = (1 << width) - 1
    await FallingEdge(dut.clk_i)
    dut.wr_en_i.value = 0
    dut.rd_en_a_i.value = 1
    dut.rd_addr_a_i.value = last_addr
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    assert int(dut.data_a_o.value) == (1 << width) - 1, f"Boundary read mismatch: got={int(dut.data_a_o.value)}"

async def test_sync_ram_block_same_cycle_rd_wr(dut, width, depth):
    """Test same-cycle read and write to the same address (read returns old data)."""
    addr = 0
    old_val = 7
    new_val = 13

    # preload old value
    dut.wr_en_i.value = 1
    dut.rd_en_a_i.value = 0
    dut.wr_addr_i.value = addr
    dut.data_i.value = old_val
    await FallingEdge(dut.clk_i)

    # simultaneous rd/wr, expect old data on read
    dut.wr_en_i.value = 1
    dut.rd_en_a_i.value = 1
    dut.wr_addr_i.value = addr
    dut.rd_addr_a_i.value = addr
    dut.data_i.value = new_val
    await FallingEdge(dut.clk_i)
    assert int(dut.data_a_o.value) == old_val, f"Simultaneous rd/wr should return old data, got {int(dut.data_a_o.value)}"

    # confirm new data visible next read
    dut.wr_en_i.value = 0
    dut.rd_en_a_i.value = 1
    await FallingEdge(dut.clk_i)
    
    assert int(dut.data_a_o.value) == new_val, f"Updated data not visible: got {int(dut.data_a_o.value)}"

async def test_sync_ram_block_write_read_multi_random(dut, width, depth):
    """Test multiple random write and read behavior of sync RAM block."""
    random_stream = [random.randint(0, 2**width - 1) for _ in range(depth)]
    expected_ram = {} #{i:0 for i in range(depth)}
    wr_addr = 0
    rd_addr = 0
    pending_read = None 
    dut.wr_en_i.value = 0
    dut.rd_en_a_i.value = 0
    dut.rd_addr_a_i.value = 0
    dut.wr_addr_i.value = 0
    await FallingEdge(dut.clk_i)
    
    for cycle in range(50):
        # check previous cycle read
        if pending_read is not None:
            addr, expected_val = pending_read
            actual_val = int(dut.data_a_o.value)
            assert actual_val == expected_val, \
                f"Cycle {cycle}: Read mismatch at addr {addr}: expected {expected_val}, got {actual_val}"
            pending_read = None
        
        do_write = random.randint(0, 1)
        # required to fix reset 0,0 simultaneous issue(should not happen ideally)
        do_read = random.randint(0, 1) and (rd_addr in expected_ram) and (pending_read is None)
        
        # update dut
        if do_read:
            # should get old value if addresses collide, so expect value CURRENTLY inside the model pre update
            expected_val = expected_ram[rd_addr]
            pending_read = (rd_addr, expected_val)
            dut.rd_en_a_i.value = 1
            dut.rd_addr_a_i.value = rd_addr
        else:
            dut.rd_en_a_i.value = 0
        
        if do_write:
            val = random_stream.pop() if random_stream else random.randint(0, 2**width - 1)
            dut.wr_en_i.value = 1
            dut.wr_addr_i.value = wr_addr
            dut.data_i.value = val
        else:
            dut.wr_en_i.value = 0
        
        await FallingEdge(dut.clk_i)
        
        # updte model
        if do_write:
            expected_ram[wr_addr] = val
            wr_addr = (wr_addr + 1) % depth
        
        if do_read:
            # read value should update next cycle
            rd_addr = (rd_addr + 1) % depth
    
    if pending_read is not None:
        await FallingEdge(dut.clk_i)
        addr, expected_val = pending_read
        actual_val = int(dut.data_a_o.value)
        assert actual_val == expected_val, \
            f"Final: Read mismatch at addr {addr}: expected {expected_val}, got {actual_val}"

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
