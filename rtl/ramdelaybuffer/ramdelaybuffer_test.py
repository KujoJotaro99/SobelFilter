"""coverage reset hold, expected delay, pointer wraparound, valid deasserts"""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

async def start_clock(dut):
    """Clock gen"""
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, units="ns").start())
    await Timer(5, units="ns")

async def init_dut(dut):
    """drive known defaults"""
    dut.rstn_i.value = 0
    dut.valid_i.value = 0
    dut.ready_i.value = 1
    dut.data_i.value = 0
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await FallingEdge(dut.clk_i)


async def push_word(dut, data):
    """single valid handshake"""
    await FallingEdge(dut.clk_i)
    dut.valid_i.value = 1
    dut.data_i.value = data
    await FallingEdge(dut.clk_i)
    dut.valid_i.value = 0
    dut.data_i.value = 0

async def test_ramdelay_buffer_reset_alignment(dut, width, delay):
    """reset and initial pointer offset/delay correctness"""
    await init_dut(dut)
    dut.ready_i.value = 1
    dut.valid_i.value = 0
    dut.rstn_i.value = 0
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1

    for cycle in range(delay + 3):
        await FallingEdge(dut.clk_i)
        assert dut.valid_o.value == 0, f"valid_o should stay low after {cycle+1} cycles"

async def test_ramdelay_buffer_delay(dut, width, delay):
    """data emerges after exactly DELAY_P handshakes, not cycles since only counting valid delays"""
    await init_dut(dut)
    dut.ready_i.value = 1
    val = random.randint(1, (1 << width) - 1)

    await push_word(dut, val)
    for _ in range(delay):
        await push_word(dut, 0)

    assert int(dut.data_o.value) == val, f"Delayed value mismatch got {int(dut.data_o.value)} exp {val}"

async def test_ramdelay_buffer_wraparound(dut, width, delay):
    """pointers wrap correctly after depth crossings"""
    await init_dut(dut)
    dut.ready_i.value = 1
    total = delay * 2 + 3
    sent = list(range(1, total + 1))

    observed = []
    for i in range(total + delay):
        data = sent[i] if i < total else 0
        await push_word(dut, data)
        if i >= delay and (i - delay) < total:
            observed.append(int(dut.data_o.value))

    assert observed == sent, f"Wraparound ordering mismatch got {observed} expected {sent}"

# coverage removed as stream buffer in convolution will assume consumer always ready
# async def test_ramdelay_buffer_backpressure(dut, width, delay):
#     """ready_i backpressure stalls internal writes/reads and holds last value at output"""
#     await init_dut(dut)
#     dut.ready_i.value = 1

#     token = random.randint(1, (1 << width) - 1)

#     for data in [token] + [0] * max(delay - 1, 0):
#         await push_word(dut, data)

#     # apply backpressure right as output expected
#     await FallingEdge(dut.clk_i)
#     dut.ready_i.value = 0
#     for _ in range(delay + 2):
#         await FallingEdge(dut.clk_i)
#         if dut.valid_o.value:
#             assert int(dut.data_o.value) == token, "Data changed under backpressure"

#     dut.ready_i.value = 1
#     await FallingEdge(dut.clk_i)
#     assert int(dut.data_o.value) == token

async def test_ramdelay_buffer_valid_gaps(dut, width, delay):
    """non valid_i sequences do not duplicate or skip outputs"""
    await init_dut(dut)
    dut.ready_i.value = 1
    seq = [1, 3, 7, 2]
    
    for val in seq:
        await push_word(dut, val)

    observed = []
    for _ in range(delay - len(seq)):
        await push_word(dut, 0)
        await FallingEdge(dut.clk_i)
    
    for _ in range(len(seq)):
        await push_word(dut, 0)
        await FallingEdge(dut.clk_i)
        observed.append(int(dut.data_o.value))
        
    assert observed == seq, f"Gapped valid sequence mismatch got {observed} expected {seq}"

# coverage removed as stream buffer in convolution will assume consumer always ready
# async def test_ramdelay_buffer_ready_drop_on_boundary(dut, width, delay):
#     """ready drops exactly when output becomes valid, holds output"""
#     await init_dut(dut)
#     dut.ready_i.value = 1
#     token = random.randint(1, (1 << width) - 1)
#     await push_word(dut, token)
#     for _ in range(delay - 1):
#         await push_word(dut, 0)

#     for _ in range(delay + 1):
#         await FallingEdge(dut.clk_i)
#     dut.ready_i.value = 0
#     await FallingEdge(dut.clk_i)
#     assert int(dut.data_o.value) == token
#     dut.ready_i.value = 1

@cocotb.test(skip=False)
async def run_ramdelay_buffer_tests(dut):
    """runner to execute all ramdelaybuffer tests."""
    await start_clock(dut)
    width = int(dut.WIDTH_P.value)
    delay = int(dut.DELAY_P.value)

    await test_ramdelay_buffer_reset_alignment(dut, width, delay)
    await test_ramdelay_buffer_delay(dut, width, delay)
    await test_ramdelay_buffer_wraparound(dut, width, delay)
    # await test_ramdelay_buffer_backpressure(dut, width, delay)
    await test_ramdelay_buffer_valid_gaps(dut, width, delay)
    # await test_ramdelay_buffer_ready_drop_on_boundary(dut, width, delay)
