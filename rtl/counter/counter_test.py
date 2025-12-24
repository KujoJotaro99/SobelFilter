"""coverage reset, load, up/down, enable, saturate"""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

# drivers

class ModelManager:
    def __init__(self, dut):
        try:
            self.width = int(dut.WIDTH_P.value)
        except Exception:
            self.width = len(dut.count_o)
        self.mask = (1 << self.width) - 1

        try:
            self.saturate = int(dut.SATURATE_P.value)
        except Exception:
            self.saturate = 0

        try:
            self.max_val = int(dut.MAX_VAL_P.value) & self.mask
        except Exception:
            self.max_val = self.mask

        self.count = 0

    def reset(self, rstn_data):
        self.count = int(rstn_data) & self.mask

    def run(self, input):
        en, load, data, up, down = input
        en = 1 if en else 0
        load = 1 if load else 0
        up = 1 if up else 0
        down = 1 if down else 0
        data = int(data) & self.mask

        if en:
            if load:
                if self.saturate:
                    self.count = min(data, self.max_val)
                else:
                    self.count = data
            elif up and (not down):
                if self.saturate:
                    if self.count != self.max_val:
                        self.count = (self.count + 1) & self.mask
                else:
                    self.count = (self.count + 1) & self.mask
            elif down and (not up):
                if self.saturate:
                    if self.count != 0:
                        self.count = (self.count - 1) & self.mask
                else:
                    self.count = (self.count - 1) & self.mask

        return self.count

class InputManager:
    def __init__(self, stream):
        self.data = list(stream)
        self.idx = 0
        self.valid = False
        self.current = None

    def has_next(self):
        return self.idx < len(self.data)

    def drive(self, handshake):
        if not self.valid and self.has_next():
            self.current = self.data[self.idx]
            self.valid = True
        handshake.drive(self.valid, self.current if self.valid else (1, 0, 0, 0, 0))

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

    def update_expected(self, input):
        self.pending = self.model.run(input)

    def check_output(self, output):
        if output is None:
            return False
        if self.pending is None:
            return False
        assert int(output) == int(self.pending), f"Mismatch: got {int(output)} expected {int(self.pending)}"
        self.pending = None
        return True

class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        self.expected_outputs = len(stream)
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
            self.handshake.dut.en_i.value = 0
            self.handshake.dut.load_i.value = 0
            self.handshake.dut.up_i.value = 0
            self.handshake.dut.down_i.value = 0

class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut
        self.last_valid = False

    def drive(self, valid, data):
        en, load, data_i, up, down = data
        self.last_valid = bool(valid)

        self.dut.en_i.value = 1 if en else 0
        self.dut.load_i.value = 1 if load else 0
        self.dut.data_i.value = int(data_i)
        self.dut.up_i.value = 1 if up else 0
        self.dut.down_i.value = 1 if down else 0

    def input_accepted(self):
        return self.last_valid

    def output_accepted(self):
        return self.last_valid

    def output_value(self):
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
    dut.load_i.value = 0
    dut.up_i.value = 0
    dut.down_i.value = 0
    dut.data_i.value = 0
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
        load = 1 if (random.randint(0, 15) == 0) else 0
        data = random.randint(0, (1 << width) - 1)
        up = 0
        down = 0
        if not load:
            r = random.randint(0, 2)
            up = 1 if r == 1 else 0
            down = 1 if r == 2 else 0
        stream.append((en, load, data, up, down))

    env = TestManager(dut, stream)
    await env.run()
