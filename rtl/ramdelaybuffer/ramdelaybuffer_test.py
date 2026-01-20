"""coverage reset hold, expected delay, pointer wraparound, valid deasserts"""
import random
import numpy as np
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

class ModelManager:
    """Reference dual-tap delay-line model for A/B outputs."""
    def __init__(self, dut):
        self.delay = int(dut.DELAY_P.value)
        self.delay_a = int(dut.DELAY_A_P.value)
        self.delay_b = int(dut.DELAY_B_P.value)
        self.buf = np.full((self.delay + 1,), np.nan)

    def run(self, input):
        """Advance model state for one input and return expected output."""
        self.buf = np.roll(self.buf, -1)
        self.buf[-1] = int(input)
        exp_a = self.buf[-1 - self.delay_a]
        exp_b = self.buf[-1 - self.delay_b]
        exp_a = None if np.isnan(exp_a) else int(exp_a)
        exp_b = None if np.isnan(exp_b) else int(exp_b)
        return (exp_a, exp_b)

class InputManager:
    """Drives input stream into the DUT with a valid buffer."""
    def __init__(self, stream):
        self.data = list(stream)
        self.idx = 0
        self.valid = False
        self.current = 0

    def has_next(self):
        """Return True when more inputs remain."""
        return self.idx < len(self.data)

    def drive(self, handshake):
        """Drive the current input and valid flag."""
        if not self.has_next():
            self.valid = False
            handshake.drive(False, 0)
            return
        if not self.valid:
            item = self.data[self.idx]
            if item is None:
                self.idx += 1
                handshake.drive(False, 0)
                return
            self.current = int(item)
            self.valid = True
        handshake.drive(self.valid, self.current if self.valid else 0)

    def accept(self):
        """Consume the current input after acceptance."""
        if self.valid:
            self.idx += 1
            self.valid = False
            return self.current
        return None

class ScoreManager:
    """Tracks expected outputs and compares against DUT results."""
    def __init__(self, model):
        self.model = model
        self.pending_a = deque()
        self.pending_b = deque()
        self.checked_a = 0
        self.checked_b = 0

    def update_expected(self, input):
        """Queue expected outputs for a new input."""
        exp_a, exp_b = self.model.run(input)
        if exp_a is not None:
            self.pending_a.append(exp_a)
        if exp_b is not None:
            self.pending_b.append(exp_b)

    def check_output(self, output):
        """Compare DUT output against expected values."""
        if output is None:
            return False
        got_a, got_b = output
        matched = False
        if (got_a is not None) and self.pending_a:
            exp_a = self.pending_a.popleft()
            assert int(got_a) == int(exp_a), f"Port A mismatch got {int(got_a)} exp {int(exp_a)}"
            self.checked_a += 1
            matched = True
        if (got_b is not None) and self.pending_b:
            exp_b = self.pending_b.popleft()
            assert int(got_b) == int(exp_b), f"Port B mismatch got {int(got_b)} exp {int(exp_b)}"
            self.checked_b += 1
            matched = True
        return matched

    def drain(self):
        """Template hook for queue-based comparisons."""
        return False

class TestManager:
    """Coordinates stimulus, model updates, and checks."""
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        inputs = sum(1 for x in stream if x is not None)
        self.expected_a = max(0, inputs - self.model.delay_a)
        self.expected_b = max(0, inputs - self.model.delay_b)

    async def run(self):
        """Main loop coordinating input and output checks."""
        try:
            self.input.drive(self.handshake)
            while (self.scoreboard.checked_a < self.expected_a) or (self.scoreboard.checked_b < self.expected_b):
                await FallingEdge(self.handshake.dut.clk_i)

                if self.handshake.input_accepted():
                    inp = self.input.accept()
                    if inp is not None:
                        self.scoreboard.update_expected(inp)

                if self.handshake.output_accepted():
                    self.scoreboard.check_output(self.handshake.output_value())

                self.input.drive(self.handshake)
        finally:
            self.handshake.dut.valid_i.value = 0
            self.handshake.dut.ready_i.value = 0

class HandshakeManager:
    """Wraps DUT signal driving and sampling."""
    def __init__(self, dut):
        self.dut = dut

    def drive(self, valid, data):
        """Drive DUT inputs for this cycle."""
        self.dut.valid_i.value = 1 if valid else 0
        self.dut.data_i.value = int(data)
        self.dut.ready_i.value = 1

    def input_accepted(self):
        """Return True when input handshake succeeds."""
        return bool(self.dut.valid_i.value and self.dut.ready_o.value)
    
    def output_accepted(self):
        """Return True when output handshake succeeds."""
        return bool(self.dut.valid_o.value and self.dut.ready_i.value)

    def output_value(self):
        """Sample DUT outputs for comparison."""
        got_a = None
        got_b = None
        if self.dut.data_a_o.value.is_resolvable:
            got_a = int(self.dut.data_a_o.value)
        if self.dut.data_b_o.value.is_resolvable:
            got_b = int(self.dut.data_b_o.value)
        if (got_a is None) and (got_b is None):
            return None
        return (got_a, got_b)
    
async def counter_clock_test(dut):
    """Clock gen"""
    await Timer(100, unit="ns")
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, unit="ns").start())
    await Timer(10, unit="ns")

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

@cocotb.test(skip=False)
async def test_ramdelay_buffer_reset(dut):
    """reset and initial pointer offset/delay correctness"""
    await counter_clock_test(dut)
    await init_dut(dut)
    dut.valid_i.value = 0

    for cycle in range(10):
        await FallingEdge(dut.clk_i)
        assert dut.valid_o.value == 0, f"valid_o should stay low after {cycle+1} cycles"

@cocotb.test(skip=False)
async def test_ramdelay_buffer_stream(dut):
    """simple A/B tap checks over a stream"""
    await counter_clock_test(dut)
    width = int(dut.WIDTH_P.value)
    delay = int(dut.DELAY_P.value)
    await init_dut(dut)

    stream = [random.randint(0, (1 << width) - 1) for _ in range((2 * delay) + 50)]
    env = TestManager(dut, stream)
    await env.run()
    assert env.scoreboard.checked_a == max(0, len(stream) - int(dut.DELAY_A_P.value))
    assert env.scoreboard.checked_b == max(0, len(stream) - int(dut.DELAY_B_P.value))

@cocotb.test(skip=False)
async def test_ramdelay_buffer_same_delay(dut):
    """check behavior when DELAY_B_P is same as DELAY_P"""
    await counter_clock_test(dut)
    width = int(dut.WIDTH_P.value)
    delay = int(dut.DELAY_P.value)
    await init_dut(dut)

    stream = [random.randint(0, (1 << width) - 1) for _ in range((2 * delay) + 50)]
    env = TestManager(dut, stream)
    await env.run()
    assert env.scoreboard.checked_a == env.scoreboard.checked_b
