"""coverage reset, line framing, expected latency"""
import numpy as np
import cv2 as cv
from pathlib import Path
from collections import deque

import sys
sys.stdout.flush()
sys.stderr.flush()

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

# drivers

class ModelManager:
    def __init__(self, dut):
        pass

    def run(self, input):
        return input

class InputManager:
    def __init__(self, stream):
        self.seq = stream
        self.idx = 0
        self.current = None

    def has_next(self):
        return self.idx < len(self.seq)

    def drive(self, handshake):
        if self.has_next():
            hsync, data, vsync, last = self.seq[self.idx]
            self.current = (hsync, data, vsync, last)
            handshake.drive(hsync, vsync, data)
        else:
            self.current = None
            handshake.drive(False, False, 0)

    def accept(self):
        if self.current and self.current[0]:
            return (self.current[1], self.current[3])
        return None

    def step(self):
        if self.has_next():
            self.idx += 1

class ScoreManager:
    def __init__(self, model, expected_outputs):
        self.model = model
        self.expected_outputs = expected_outputs
        self.pending = deque()
        self.checked = 0

    def update_expected(self, input):
        exp = self.model.run(input)
        if exp is not None:
            self.pending.append(exp)

    def check_output(self, output):
        if output is None:
            return False
        if not self.pending:
            return False
        exp_data, exp_last = self.pending.popleft()
        out_data, out_last = output
        assert int(out_data) == int(exp_data), f"Mismatch got {int(out_data)} exp {int(exp_data)}"
        assert int(out_last) == int(exp_last), f"TLAST mismatch got {int(out_last)} exp {int(exp_last)}"
        self.checked += 1
        return True

class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)

        self.expected_outputs = sum(1 for hsync, _, _, _ in stream if hsync)
        self.checked = 0

        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model, self.expected_outputs)

    async def run(self):
        try:
            self.input.drive(self.handshake)
            while self.checked < self.expected_outputs:
                await FallingEdge(self.handshake.dut.pclk_i)

                if self.handshake.input_accepted():
                    inp = self.input.accept()
                    if inp is not None:
                        self.scoreboard.update_expected(inp)

                if self.handshake.output_accepted():
                    out = self.handshake.output_value()
                    if self.scoreboard.check_output(out):
                        self.checked += 1

                self.input.step()
                self.input.drive(self.handshake)
        finally:
            self.handshake.dut.hsync_i.value = 0
            self.handshake.dut.vsync_i.value = 0
            self.handshake.dut.data_i.value = 0
            self.handshake.dut.tready_i.value = 0

class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut

    def drive(self, hsync, vsync, data):
        self.dut.hsync_i.value = 1 if hsync else 0
        self.dut.vsync_i.value = 1 if vsync else 0
        self.dut.data_i.value = int(data)
        self.dut.tready_i.value = 1

    def input_accepted(self):
        return bool(self.dut.hsync_i.value)

    def output_accepted(self):
        return bool(self.dut.tvalid_o.value and self.dut.tready_i.value)

    def output_value(self):
        if not self.dut.tdata_o.value.is_resolvable:
            return None
        if not self.dut.tlast_o.value.is_resolvable:
            return None
        return (self.dut.tdata_o.value.integer, int(self.dut.tlast_o.value))

# unit tests

async def clock_test(dut):
    cocotb.start_soon(Clock(dut.pclk_i, CLK_PERIOD_NS, unit="ns").start())
    await Timer(5 * CLK_PERIOD_NS, unit="ns")

async def reset_test(dut):
    dut.rstn_i.value = 0
    dut.hsync_i.value = 0
    dut.vsync_i.value = 0
    dut.data_i.value = 0
    dut.tready_i.value = 1
    await Timer(10 * CLK_PERIOD_NS, unit="ns")
    await FallingEdge(dut.pclk_i)
    dut.rstn_i.value = 1
    await Timer(10 * CLK_PERIOD_NS, unit="ns")
    await FallingEdge(dut.pclk_i)

def build_sequence(img):
    height, width = img.shape
    seq = []
    for r in range(height):
        for c in range(width):
            last = (c == (width - 1))
            seq.append((1, int(img[r, c]), 1, last))
        seq.append((0, 0, 1, False))
    seq.append((0, 0, 0, False))
    return seq

@cocotb.test()
async def single_zeroes_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    img = np.zeros((8, 16), dtype=np.uint8)
    env = TestManager(dut, build_sequence(img))
    await env.run()

@cocotb.test()
async def single_ones_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    img = np.ones((8, 16), dtype=np.uint8)
    env = TestManager(dut, build_sequence(img))
    await env.run()

@cocotb.test()
async def single_impulse_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    img = np.zeros((8, 16), dtype=np.uint8)
    img[3, 7] = 1
    env = TestManager(dut, build_sequence(img))
    await env.run()

@cocotb.test()
async def single_alternate_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    img = np.zeros((8, 16), dtype=np.uint8)
    img[::2, ::2] = 1
    img[1::2, 1::2] = 1
    env = TestManager(dut, build_sequence(img))
    await env.run()

@cocotb.test()
async def single_random_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    np.random.seed(42)
    img = np.random.randint(0, 256, size=(12, 20), dtype=np.uint8)
    env = TestManager(dut, build_sequence(img))
    await env.run()

@cocotb.test()
async def single_image_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    img_path = Path(__file__).resolve().parents[2] / "jupyter" / "car.jpg"
    img = cv.imread(str(img_path), cv.IMREAD_GRAYSCALE)
    if img is None:
        raise FileNotFoundError(img_path)
    img = img[:32, :64]
    env = TestManager(dut, build_sequence(img.astype(np.uint8)))
    await env.run()
