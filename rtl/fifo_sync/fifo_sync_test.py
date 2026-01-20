"""coverage reset hold, expected delay, pointer wraparound, valid deasserts"""
import random
import numpy as np
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

class ModelManager:
    """Reference FIFO queue model for stream ordering."""
    def __init__(self, dut):
        self.queue = deque()

    def run(self, input):
        """Advance model state for one input and return expected output."""
        self.queue.append(int(input))
        return None

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
        self.pending = deque()
        self.checked = 0

    def update_expected(self, input):
        """Queue expected outputs for a new input."""
        self.model.run(input)

    def check_output(self, output):
        """Compare DUT output against expected values."""
        if output is None:
            return
        self.pending.append(int(output))

    def drain(self):
        """Only for queue-based comparisons."""
        matched = False
        while self.model.queue and self.pending:
            exp = self.model.queue.popleft()
            got = self.pending.popleft()
            assert int(got) == int(exp), f"Mismatch got {int(got)} exp {int(exp)}"
            self.checked += 1
            matched = True
        return matched

class TestManager:
    """Coordinates stimulus, model updates, and checks."""
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        inputs = sum(1 for x in stream if x is not None)
        self.expected_outputs = inputs
        self.checked = 0
        self.in_stride = 1
        self.out_stride = 1

    async def run(self):
        """Main loop coordinating input and output checks."""
        try:
            self.handshake.dut.ready_i.value = 1
            self.input.drive(self.handshake)
            producer = cocotb.start_soon(self.drive_inputs())
            consumer = cocotb.start_soon(self.consume_outputs())
            await producer
            await consumer
        finally:
            self.handshake.dut.valid_i.value = 0
            self.handshake.dut.ready_i.value = 0

    async def drive_inputs(self):
        """Drive inputs based on the stride configuration."""
        cycle = 0
        while self.input.has_next():
            await FallingEdge(self.handshake.dut.clk_i)
            cycle += 1
            if (cycle % self.in_stride) == 0:
                if self.handshake.input_accepted():
                    inp = self.input.accept()
                    if inp is not None:
                        self.scoreboard.update_expected(inp)
                self.input.drive(self.handshake)
            else:
                self.handshake.dut.valid_i.value = 0

    async def consume_outputs(self):
        """Consume outputs based on the stride configuration."""
        cycle = 0
        while self.scoreboard.checked < self.expected_outputs:
            await FallingEdge(self.handshake.dut.clk_i)
            cycle += 1
            if (cycle % self.out_stride) == 0:
                self.handshake.dut.ready_i.value = 1
            else:
                self.handshake.dut.ready_i.value = 0
            if self.handshake.output_accepted():
                self.scoreboard.check_output(self.handshake.output_value())
            if self.scoreboard.drain():
                self.checked = self.scoreboard.checked

class HandshakeManager:
    """Wraps DUT signal driving and sampling."""
    def __init__(self, dut):
        self.dut = dut

    def drive(self, valid, data):
        """Drive DUT inputs for this cycle."""
        self.dut.valid_i.value = 1 if valid else 0
        self.dut.data_i.value = int(data)

    def input_accepted(self):
        """Return True when input handshake succeeds."""
        return bool(self.dut.valid_i.value and self.dut.ready_o.value)
    
    def output_accepted(self):
        """Return True when output handshake succeeds."""
        return bool(self.dut.valid_o.value and self.dut.ready_i.value)

    def output_value(self):
        """Sample DUT outputs for comparison."""
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

    stream = [random.randint(0, (1 << width) - 1) for _ in range(1000)]
    env = TestManager(dut, stream)
    env.in_stride = 1
    env.out_stride = 2
    await env.run()
    assert env.checked == len(stream)
