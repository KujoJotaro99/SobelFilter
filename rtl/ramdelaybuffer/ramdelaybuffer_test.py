"""Test headers for ramdelaybuffer; fill in implementations."""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10


async def start_clock(dut):
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, units="ns").start())
    await Timer(5, units="ns")


async def init_dut(dut):
    """Drive known defaults."""
    dut.rstn_i.value = 0
    dut.valid_i.value = 0
    dut.ready_i.value = 1
    dut.data_i.value = 0
    await RisingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await RisingEdge(dut.clk_i)


@cocotb.test()
async def test_ramdelay_buffer_reset_alignment(dut, width, delay):
    """Reset and initial pointer offset/delay correctness."""
    await start_clock(dut)
    await init_dut(dut)
    # todo: preload a word and verify output holds/reset state
    raise NotImplementedError("Implement reset alignment check")


@cocotb.test()
async def test_ramdelay_buffer_delay(dut, width, delay):
    """Data emerges after exactly DELAY_P handshakes."""
    await start_clock(dut)
    await init_dut(dut)

    dut.ready_i.value = 1
    dut.valid_i.value = 0
    dut.data_i.value = 0

    val = random.randint(1, (1 << width) - 1)

    await FallingEdge(dut.clk_i)
    dut.valid_i.value = 1
    dut.data_i.value = val
    await FallingEdge(dut.clk_i)
    dut.valid_i.value = 0
    dut.data_i.value = 0

    cycles = 0
    seen = False
    # might have to adjust delay off by one
    while cycles <= delay + 2:
        await RisingEdge(dut.clk_i)
        if dut.valid_o.value:
            seen = True
            got = int(dut.data_o.value)
            assert cycles == delay, f"valid_o after {cycles} cycles, expected {delay}"
            assert got == val, f"data_o mismatch got {got} expected {val}"
            break
        cycles += 1

    assert seen, f"valid_o never asserted within {delay + 2} cycles after launch"


@cocotb.test()
async def test_ramdelay_buffer_wraparound(dut, width, delay):
    """Pointers wrap correctly after depth crossings."""
    await start_clock(dut)
    await init_dut(dut)
    # todo: stream more than DEPTH samples and check ordering across wrap
    raise NotImplementedError("Implement wraparound test")


@cocotb.test()
async def test_ramdelay_buffer_backpressure(dut, width, delay):
    """Ready_i backpressure stalls internal writes/reads cleanly."""
    await start_clock(dut)
    await init_dut(dut)
    # todo: toggle ready_i low/high mid-stream and ensure valid_o/data_o behavior matches elastic handshake
    raise NotImplementedError("Implement backpressure test")


@cocotb.test()
async def test_ramdelay_buffer_valid_gaps(dut, width, delay):
    """Gapped valid_i sequences do not duplicate or skip outputs."""
    await start_clock(dut)
    await init_dut(dut)
    # todo: pulse valid_i with gaps, ensure outputs line up with handshakes only
    raise NotImplementedError("Implement valid gap test")


@cocotb.test()
async def test_ramdelay_buffer_ready_drop_on_boundary(dut, width, delay):
    """Ready drops exactly when output becomes valid."""
    await start_clock(dut)
    await init_dut(dut)
    # todo: hold valid_i high, drop ready_i when valid_o asserts, ensure data holds until handshake
    raise NotImplementedError("Implement ready drop boundary test")
