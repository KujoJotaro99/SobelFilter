"""Coverage: reset, long stream rd/wr, dual read sync ram block"""

import random
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

# drivers

class ModelManager:
    def __init__(self, dut):
        self.depth = int(dut.DEPTH_P.value)
        self.mem = np.full((self.depth,), np.nan)

    def run(self, input):
        wr_en, wr_addr, data, rd_en_a, rd_addr_a, rd_en_b, rd_addr_b = input

        exp_a = None
        exp_b = None

        if rd_en_a:
            val_a = self.mem[int(rd_addr_a)]
            exp_a = None if np.isnan(val_a) else int(val_a)

        if rd_en_b:
            val_b = self.mem[int(rd_addr_b)]
            exp_b = None if np.isnan(val_b) else int(val_b)

        if wr_en:
            self.mem[int(wr_addr)] = int(data)

        return (exp_a, exp_b)

class InputManager:
    def __init__(self, stream):
        self.data = list(stream)
        self.idx = 0
        self.valid = False
        self.current = None

    def has_next(self):
        return self.idx < len(self.data)

    def drive(self, handshake):
        if not self.has_next():
            self.valid = False
            handshake.drive(False, (0, 0, 0, 0, 0, 0, 0))
            return
        if not self.valid:
            self.current = self.data[self.idx]
            self.valid = True
        handshake.drive(self.valid, self.current if self.valid else (0, 0, 0, 0, 0, 0, 0))

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
        exp_a, exp_b = self.model.run(input)
        if (exp_a is not None) or (exp_b is not None):
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
        if exp_a is not None:
            if got_a is None:
                return False
            assert int(got_a) == int(exp_a), f"Port A mismatch got {int(got_a)} exp {int(exp_a)}"
        if exp_b is not None:
            if got_b is None:
                return False
            assert int(got_b) == int(exp_b), f"Port B mismatch got {int(got_b)} exp {int(exp_b)}"
        self.pending = None
        return True

class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        self.expected_outputs = 0
        self.checked = 0

        preview = ModelManager(dut)
        for op in stream:
            exp_a, exp_b = preview.run(op)
            if (exp_a is not None) or (exp_b is not None):
                self.expected_outputs += 1

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
            self.handshake.dut.wr_en_i.value = 0
            self.handshake.dut.rd_en_a_i.value = 0
            self.handshake.dut.rd_en_b_i.value = 0

class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut

    def drive(self, valid, data):
        wr_en, wr_addr, data_i, rd_en_a, rd_addr_a, rd_en_b, rd_addr_b = data

        self.dut.wr_en_i.value = 1 if (valid and wr_en) else 0
        self.dut.data_i.value = int(data_i)
        self.dut.wr_addr_i.value = int(wr_addr)

        self.dut.rd_en_a_i.value = 1 if (valid and rd_en_a) else 0
        self.dut.rd_addr_a_i.value = int(rd_addr_a)

        self.dut.rd_en_b_i.value = 1 if (valid and rd_en_b) else 0
        self.dut.rd_addr_b_i.value = int(rd_addr_b)

    def input_accepted(self):
        return True

    def output_accepted(self):
        return bool(self.dut.rd_en_a_i.value or self.dut.rd_en_b_i.value)

    def output_value(self):
        got_a = None if (not self.dut.data_a_o.value.is_resolvable) else int(self.dut.data_a_o.value)
        got_b = None if (not self.dut.data_b_o.value.is_resolvable) else int(self.dut.data_b_o.value)
        return (got_a, got_b)

# unit tests

async def counter_clock_test(dut):
    """Clock gen"""
    await Timer(100, unit="ns")
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, unit="ns").start())
    await Timer(10, unit="ns")

async def init_dut(dut):
    """drive known defaults"""
    dut.rstn_i.value = 0
    dut.wr_en_i.value = 0
    dut.rd_en_a_i.value = 0
    dut.rd_en_b_i.value = 0
    dut.data_i.value = 0
    dut.wr_addr_i.value = 0
    dut.rd_addr_a_i.value = 0
    dut.rd_addr_b_i.value = 0
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await FallingEdge(dut.clk_i)

@cocotb.test(skip=False)
async def test_sync_ram_block_a_only(dut):
    await counter_clock_test(dut)
    await init_dut(dut)
    width = int(dut.WIDTH_P.value)
    depth = int(dut.DEPTH_P.value)

    stream = []
    for _ in range(500):
        wr_en = random.randint(0, 1)
        wr_addr = random.randint(0, depth - 1)
        data = random.randint(0, (1 << width) - 1)
        rd_en_a = random.randint(0, 1)
        rd_addr_a = random.randint(0, depth - 1)
        rd_en_b = 0
        rd_addr_b = 0
        # tuple shape expected in handshake manager
        stream.append((wr_en, wr_addr, data, rd_en_a, rd_addr_a, rd_en_b, rd_addr_b))

    env = TestManager(dut, stream)
    await env.run()

@cocotb.test(skip=False)
async def test_sync_ram_block_b_only(dut):
    await counter_clock_test(dut)
    await init_dut(dut)
    width = int(dut.WIDTH_P.value)
    depth = int(dut.DEPTH_P.value)

    stream = []
    for _ in range(500):
        wr_en = random.randint(0, 1)
        wr_addr = random.randint(0, depth - 1)
        data = random.randint(0, (1 << width) - 1)
        rd_en_a = 0
        rd_addr_a = 0
        rd_en_b = random.randint(0, 1)
        rd_addr_b = random.randint(0, depth - 1)
        # tuple shape expected in handshake manager
        stream.append((wr_en, wr_addr, data, rd_en_a, rd_addr_a, rd_en_b, rd_addr_b))

    env = TestManager(dut, stream)
    await env.run()

@cocotb.test(skip=False)
async def test_sync_ram_block_both_random(dut):
    await counter_clock_test(dut)
    await init_dut(dut)
    width = int(dut.WIDTH_P.value)
    depth = int(dut.DEPTH_P.value)

    stream = []
    for _ in range(500):
        wr_en = random.randint(0, 1)
        wr_addr = random.randint(0, depth - 1)
        data = random.randint(0, (1 << width) - 1)
        rd_en_a = random.randint(0, 1)
        rd_addr_a = random.randint(0, depth - 1)
        rd_en_b = random.randint(0, 1)
        rd_addr_b = random.randint(0, depth - 1)
        # tuple shape expected in handshake manager
        stream.append((wr_en, wr_addr, data, rd_en_a, rd_addr_a, rd_en_b, rd_addr_b))

    env = TestManager(dut, stream)
    await env.run()

@cocotb.test(skip=False)
async def test_sync_ram_block_both_same_addr(dut):
    await counter_clock_test(dut)
    await init_dut(dut)
    width = int(dut.WIDTH_P.value)
    depth = int(dut.DEPTH_P.value)

    stream = []
    for _ in range(500):
        wr_en = random.randint(0, 1)
        wr_addr = random.randint(0, depth - 1)
        data = random.randint(0, (1 << width) - 1)
        rd_en = random.randint(0, 1)
        rd_addr = random.randint(0, depth - 1)
        # tuple shape expected in handshake manager
        stream.append((wr_en, wr_addr, data, rd_en, rd_addr, rd_en, rd_addr))

    env = TestManager(dut, stream)
    await env.run()
