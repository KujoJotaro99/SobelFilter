"""coverage reset, up/down, enable, wrap"""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

# drivers

class ModelManager:
    """Reference counter model with wrap and enable behavior."""
    def __init__(self, dut):
        try:
            self.width = int(dut.WIDTH_P.value)
        except Exception:
            self.width = len(dut.count_o)
        self.mask = (1 << self.width) - 1

        try:
            self.max_val = int(dut.MAX_VAL_P.value) & self.mask
        except Exception:
            self.max_val = self.mask

        self.count = 0

    def reset(self, rstn_data):
        self.count = int(rstn_data) & self.mask

    def run(self, input):
        """Advance model state for one input and return expected output."""
        en, up, down = input
        en = 1 if en else 0
        up = 1 if up else 0
        down = 1 if down else 0

        if en:
            if up and (not down):
                if self.count == self.max_val:
                    self.count = 0
                else:
                    self.count = (self.count + 1) & self.mask
            elif down and (not up):
                if self.count == 0:
                    self.count = self.max_val
                else:
                    self.count = (self.count - 1) & self.mask

        return self.count

class InputManager:
    """Drives input stream into the DUT with a valid buffer."""
    def __init__(self, stream):
        self.data = list(stream)
        self.idx = 0
        self.valid = False
        self.current = None

    def has_next(self):
        """Return True when more inputs remain."""
        return self.idx < len(self.data)

    def drive(self, handshake):
        """Drive the current input and valid flag."""
        if not self.valid and self.has_next():
            self.current = self.data[self.idx]
            self.valid = True
        handshake.drive(self.valid, self.current if self.valid else (0, 0, 0))

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
        self.pending = []

    def update_expected(self, input):
        """Queue expected outputs for a new input."""
        self.pending.append(self.model.run(input))

    def check_output(self, output):
        """Compare DUT output against expected values."""
        if output is None:
            return False
        if not self.pending:
            return False
        expected = self.pending.pop(0)
        assert int(output) == int(expected), f"Mismatch: got {int(output)} expected {int(expected)}"
        return True

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
        self.expected_outputs = len(stream)
        self.checked = 0
        self.in_stride = 1
        self.out_stride = 1

    async def run(self):
        """Main loop coordinating input and output checks."""
        try:
            self.input.drive(self.handshake)
            cycle = 0
            while self.checked < self.expected_outputs:
                await FallingEdge(self.handshake.dut.clk_i)
                cycle += 1

                if (cycle % self.in_stride) == 0:
                    if self.handshake.input_accepted():
                        inp = self.input.accept()
                        if inp is not None:
                            self.scoreboard.update_expected(inp)
                    self.input.drive(self.handshake)
                else:
                    self.handshake.drive(False, (0, 0, 0))

                if (cycle % self.out_stride) == 0:
                    if self.scoreboard.pending:
                        if self.scoreboard.check_output(self.handshake.output_value()):
                            self.checked += 1

        finally:
            self.handshake.dut.en_i.value = 0
            self.handshake.dut.up_i.value = 0
            self.handshake.dut.down_i.value = 0

class HandshakeManager:
    """Wraps DUT signal driving and sampling."""
    def __init__(self, dut):
        self.dut = dut
        self.last_valid = False

    def drive(self, valid, data):
        """Drive DUT inputs for this cycle."""
        en, up, down = data
        self.last_valid = bool(valid)

        self.dut.en_i.value = 1 if en else 0
        self.dut.up_i.value = 1 if up else 0
        self.dut.down_i.value = 1 if down else 0

    def input_accepted(self):
        """Return True when input handshake succeeds."""
        return self.last_valid

    def output_accepted(self):
        """Return True when output handshake succeeds."""
        return self.last_valid

    def output_value(self):
        """Sample DUT outputs for comparison."""
        if not self.dut.count_o.value.is_resolvable:
            return None
        return int(self.dut.count_o.value)

# unit tests

async def counter_clock_test(dut):
    """Clock gen"""
    await Timer(100, unit="ns")
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, unit="ns").start())
    await Timer(10, unit="ns")

async def init_dut(dut):
    """drive known defaults"""
    dut.rstn_i.value = 0
    dut.rstn_data_i.value = 0
    dut.en_i.value = 1
    dut.up_i.value = 0
    dut.down_i.value = 0
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await FallingEdge(dut.clk_i)

@cocotb.test(skip=False)
async def test_counter_stream(dut):
    await counter_clock_test(dut)
    await init_dut(dut)

    model = ModelManager(dut)
    model.reset(0)

    width = model.width
    stream = []
    for _ in range(300):
        en = 1
        up = 0
        down = 0
        r = random.randint(0, 2)
        up = 1 if r == 1 else 0
        down = 1 if r == 2 else 0
        stream.append((en, up, down))

    env = TestManager(dut, stream)
    await env.run()
