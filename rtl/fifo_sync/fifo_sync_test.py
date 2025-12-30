"""coverage reset hold, expected delay, pointer wraparound, valid deasserts"""
import random
import numpy as np
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

class ModelManager:
    def __init__(self, dut):
        self.queue = deque()

    def run(self, input):
        self.queue.append(int(input))
        return None

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
        self.checked = 0

    def update_expected(self, input):
        self.model.run(input)

    def check_output(self, output):
        if output is None:
            return False
        if not self.model.queue:
            return False
        exp = self.model.queue.popleft()
        assert int(output) == int(exp), f"Mismatch got {int(output)} exp {int(exp)}"
        self.checked += 1
        return True

class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        inputs = sum(1 for x in stream if x is not None)
        self.expected_outputs = inputs
        self.checked = 0

    async def run(self):
        try:
            self.input.drive(self.handshake)
            while self.checked < self.expected_outputs:
                await FallingEdge(self.handshake.dut.clk_i)

                if self.scoreboard.check_output(self.handshake.output_value()):
                    self.checked += 1

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
        if not self.dut.data_o.value.is_resolvable:
            return None
        return int(self.dut.data_o.value)
    
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
async def test_fifo_sync_reset(dut):
    """reset and initial pointer offset/delay correctness"""
    await counter_clock_test(dut)
    await init_dut(dut)
    dut.valid_i.value = 0

    for cycle in range(10):
        await FallingEdge(dut.clk_i)
        assert dut.valid_o.value == 0, f"valid_o should stay low after {cycle+1} cycles"

@cocotb.test(skip=False)
async def test_fifo_sync_stream(dut):
    """simple A/B tap checks over a stream"""
    await counter_clock_test(dut)
    width = int(dut.WIDTH_P.value)
    depth = int(dut.DEPTH_P.value)
    await init_dut(dut)

    stream = [random.randint(0, (1 << width) - 1) for _ in range((2 * depth) + 50)]
    env = TestManager(dut, stream)
    await env.run()
    assert env.checked == len(stream)

@cocotb.test(skip=False)
async def test_fifo_sync_bypass(dut):
    """check behavior when DELAY_B_P is same as DELAY_P"""
    await counter_clock_test(dut)
    width = int(dut.WIDTH_P.value)
    await init_dut(dut)

    word = random.randint(1, (1 << width) - 1)
    stream = [word]
    env = TestManager(dut, stream)
    await env.run()
    assert env.checked == len(stream)
