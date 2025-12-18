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

async def push_word(dut, data, history, delay_a, delay_b):
    """single valid handshake that also checks tap outputs"""
    await FallingEdge(dut.clk_i)
    dut.valid_i.value = 1
    dut.data_i.value = data
    await FallingEdge(dut.clk_i)
    dut.valid_i.value = 0
    dut.data_i.value = 0
    history.append(data)
    _check_taps(dut, history, delay_a, delay_b)

def _maybe_expected(history, delay):
    if len(history) <= delay:
        return None
    return history[-1 - delay]

def _check_taps(dut, history, delay_a, delay_b):
    exp_a = _maybe_expected(history, delay_a)
    if exp_a is not None:
        got_a = int(dut.data_a_o.value)
        assert got_a == exp_a, f"Port A mismatch got {got_a} exp {exp_a}"
    exp_b = _maybe_expected(history, delay_b)
    if exp_b is not None:
        got_b = int(dut.data_b_o.value)
        assert got_b == exp_b, f"Port B mismatch got {got_b} exp {exp_b}"

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

async def test_ramdelay_buffer_delay(dut, width, delay, delay_a, delay_b):
    """data emerges after exactly DELAY_A/B handshakes"""
    await init_dut(dut)
    dut.ready_i.value = 1
    history = []
    val = random.randint(1, (1 << width) - 1)

    await push_word(dut, val, history, delay_a, delay_b)
    for _ in range(delay):
        await push_word(dut, 0, history, delay_a, delay_b)

    exp_a = _maybe_expected(history, delay_a)
    assert exp_a == val, f"Expected delay tap A to replay {val} got {exp_a}"
    assert int(dut.data_a_o.value) == val, f"Delayed value mismatch got {int(dut.data_a_o.value)} exp {val}"
    exp_b = _maybe_expected(history, delay_b)
    if exp_b is not None:
        assert int(dut.data_b_o.value) == exp_b, f"Port B unexpected value got {int(dut.data_b_o.value)} exp {exp_b}"

async def test_ramdelay_buffer_wraparound(dut, width, delay, delay_a, delay_b):
    """pointers wrap correctly after depth crossings for both taps"""
    await init_dut(dut)
    dut.ready_i.value = 1
    history = []
    total = delay * 2 + 3
    sent = list(range(1, total + 1))

    observed_a = []
    observed_b = []
    for i in range(total + delay):
        data = sent[i] if i < total else 0
        await push_word(dut, data, history, delay_a, delay_b)
        exp_a = _maybe_expected(history, delay_a)
        if exp_a is not None and len(observed_a) < total:
            observed_a.append(int(dut.data_a_o.value))
        exp_b = _maybe_expected(history, delay_b)
        if exp_b is not None and len(observed_b) < total:
            observed_b.append(int(dut.data_b_o.value))

    assert observed_a == sent, f"Wraparound ordering mismatch port A got {observed_a} expected {sent}"
    assert observed_b == sent, f"Wraparound ordering mismatch port B got {observed_b} expected {sent}"

# coverage removed as stream buffer in convolution will assume consumer always ready
# async def test_ramdelay_buffer_backpressure(...):
#     ...

async def test_ramdelay_buffer_valid_gaps(dut, width, delay, delay_a, delay_b):
    """non valid_i sequences do not duplicate or skip outputs"""
    await init_dut(dut)
    dut.ready_i.value = 1
    history = []
    seq = [1, 3, 7, 2]

    for val in seq:
        await push_word(dut, val, history, delay_a, delay_b)

    for _ in range(max(delay - len(seq), 0)):
        await push_word(dut, 0, history, delay_a, delay_b)

    observed_a = []
    observed_b = []
    while len(observed_a) < len(seq):
        await push_word(dut, 0, history, delay_a, delay_b)
        exp_a = _maybe_expected(history, delay_a)
        if exp_a is not None and len(observed_a) < len(seq):
            observed_a.append(int(dut.data_a_o.value))
        exp_b = _maybe_expected(history, delay_b)
        if exp_b is not None and len(observed_b) < len(seq):
            observed_b.append(int(dut.data_b_o.value))

    assert observed_a == seq, f"Gapped valid sequence mismatch port A got {observed_a} expected {seq}"
    assert observed_b == seq, f"Gapped valid sequence mismatch port B got {observed_b} expected {seq}"

# coverage removed as stream buffer in convolution will assume consumer always ready
# async def test_ramdelay_buffer_ready_drop_on_boundary(...):
#     ...

@cocotb.test(skip=False)
async def run_ramdelay_buffer_tests(dut):
    """runner to execute all ramdelaybuffer tests."""
    await start_clock(dut)
    width = int(dut.WIDTH_P.value)
    delay = int(dut.DELAY_P.value)
    delay_a = int(dut.DELAY_A_P.value)
    delay_b = int(dut.DELAY_B_P.value)

    await test_ramdelay_buffer_reset_alignment(dut, width, delay)
    await test_ramdelay_buffer_delay(dut, width, delay, delay_a, delay_b)
    await test_ramdelay_buffer_wraparound(dut, width, delay, delay_a, delay_b)
    # await test_ramdelay_buffer_backpressure(...)
    await test_ramdelay_buffer_valid_gaps(dut, width, delay, delay_a, delay_b)
    # await test_ramdelay_buffer_ready_drop_on_boundary(...)
