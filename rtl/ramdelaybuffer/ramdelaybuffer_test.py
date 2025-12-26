"""coverage reset hold, expected delay, pointer wraparound, valid deasserts"""
import random
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

class ModelManager:
    def __init__(self, dut):
        self.delay = int(dut.DELAY_P.value)
        self.buf = np.full((self.delay + 1,), np.nan)

    def run(self, input):
        self.buf = np.roll(self.buf, -1)
        self.buf[-1] = int(input)
        exp_a = self.buf[-1 - self.delay]
        exp_b = self.buf[-1 - self.delay]
        exp_a = None if np.isnan(exp_a) else int(exp_a)
        exp_b = None if np.isnan(exp_b) else int(exp_b)
        return (exp_a, exp_b)

class InputManager:
    def __init__(self, stream):
        self.data = list(stream)
        self.idx = 0
        self.valid = False
        self.current = 0

    def has_next(self):
        return self.idx < len(self.data)

    def drive(self, handshake):
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
        if self.valid:
            self.idx += 1
            self.valid = False
            return self.current
        return None

class ScoreManager:
    def __init__(self, model):
        self.model = model
        self.pending = None
        self.checked_a = 0
        self.checked_b = 0

    def update_expected(self, input):
        exp_a, exp_b = self.model.run(input)
        if (exp_a is not None) and (exp_b is not None):
            self.pending = (exp_a, exp_b)
        else:
            self.pending = None

    def check_output(self, output):
        if output is None:
            return False
        if self.pending is None:
            return False
        got_a, got_b = output
        exp_a, exp_b = self.pending
        assert int(got_a) == int(exp_a), f"Port A mismatch got {int(got_a)} exp {int(exp_a)}"
        self.checked_a += 1
        assert int(got_b) == int(exp_b), f"Port B mismatch got {int(got_b)} exp {int(exp_b)}"
        self.checked_b += 1
        self.pending = None
        return True

class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        inputs = sum(1 for x in stream if x is not None)
        self.expected_outputs = max(0, inputs - self.model.delay)
        self.checked = 0

    async def run(self):
        try:
            self.input.drive(self.handshake)
            while self.checked < self.expected_outputs:
                await FallingEdge(self.handshake.dut.clk_i)

                if self.handshake.input_accepted():
                    inp = self.input.accept()
                    if inp is not None:
                        self.scoreboard.update_expected(inp)

                if self.handshake.output_accepted():
                    if self.scoreboard.check_output(self.handshake.output_value()):
                        self.checked += 1

                self.input.drive(self.handshake)
        finally:
            self.handshake.dut.valid_i.value = 0
            self.handshake.dut.ready_i.value = 0

class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut

    def drive(self, valid, data):
        self.dut.valid_i.value = 1 if valid else 0
        self.dut.data_i.value = int(data)
        self.dut.ready_i.value = 1

    def input_accepted(self):
        return bool(self.dut.valid_i.value and self.dut.ready_o.value)
    
    def output_accepted(self):
        return bool(self.dut.valid_o.value and self.dut.ready_i.value)

    def output_value(self):
        if (not self.dut.data_a_o.value.is_resolvable) or (not self.dut.data_b_o.value.is_resolvable):
            return None
        return (int(self.dut.data_a_o.value), int(self.dut.data_b_o.value))
    
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
    assert env.checked == max(0, len(stream) - delay)

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
    assert env.checked == max(0, len(stream) - delay)
    assert env.scoreboard.checked_a == env.scoreboard.checked_b
