"""coverage reset, sobel x and y convolution, trying to implement uvm like test plan"""
import numpy as np
import cv2 as cv
from collections import deque

import sys
sys.stdout.flush()
sys.stderr.flush()

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10

# drivers

class ModelManager:
    def __init__(self, dut):
        self.width = int(dut.DEPTH_P.value)
        self.buf = np.full((3, self.width), np.nan)  # NaN to detect first valid conv

    x_kernel = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]])
    y_kernel = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]])

    def run(self, input):
        # convert buffer to 1d and shift left new data
        flat = self.buf.flatten()
        flat = np.roll(flat, -1)
        flat[-1] = input
        self.buf = flat.reshape(self.buf.shape)

        # if the window still has any NaN values ignore
        window = self.buf[:, -3:]
        if np.isnan(window).any():
            return (None, None)

        gx = int(np.sum(window * self.x_kernel))
        gy = int(np.sum(window * self.y_kernel))
        return gx, gy

class InputManager:
    def __init__(self, stream):
        self.data = stream.flatten()
        self.idx = 0
        self.valid = False
        self.current = 0

    def has_next(self):
        return self.idx < len(self.data)

    def drive(self, handshake):
        if not self.valid and self.has_next():
            self.current = int(self.data[self.idx])
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

    def update_expected(self, input):
        gx_exp, gy_exp = self.model.run(input)
        if gx_exp is not None and gy_exp is not None:
            self.pending = (gx_exp, gy_exp)
        else:
            self.pending = None

    def check_output(self, output):
        gx_out, gy_out = output
        if gx_out is None or gy_out is None:
            return False
        if self.pending is None:
            return False
        exp_gx, exp_gy = self.pending
        assert gx_out == exp_gx, f"Mismatch: got {gx_out}, expected {exp_gx}"
        assert gy_out == exp_gy, f"Mismatch: got {gy_out}, expected {exp_gy}"
        self.pending = None
        return True

class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)

        self.height, self.width = stream.shape
        self.expected_outputs = max(0, (self.height - 2) * (self.width - 2))
        self.checked = 0

        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)

    async def run(self):
        try:
            while self.checked < self.expected_outputs:
                await FallingEdge(self.handshake.dut.clk_i)
                self.input.drive(self.handshake)
                await RisingEdge(self.handshake.dut.clk_i)

                if self.handshake.output_accepted():
                    gx_out, gy_out = self.handshake.output_value()
                    if self.scoreboard.check_output((gx_out, gy_out)):
                        self.checked += 1

                if self.handshake.input_accepted():
                    inp = self.input.accept()
                    if inp is not None:
                        self.scoreboard.update_expected(inp)
        finally:
            self.handshake.dut.valid_i.value = 0
            self.handshake.dut.ready_i.value = 0

class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut

    def drive(self, valid, data):
        self.dut.valid_i.value = 1 if valid else 0
        self.dut.data_i.value = data
        self.dut.ready_i.value = 1

    def input_accepted(self):
        return bool(self.dut.valid_i.value and self.dut.ready_o.value)

    def output_accepted(self):
        return bool(self.dut.valid_o.value and self.dut.ready_i.value)

    def output_value(self):
        if (not self.dut.gx_o.value.is_resolvable) or (not self.dut.gy_o.value.is_resolvable):
            return (None, None)
        return (self.dut.gx_o.value.to_signed(), self.dut.gy_o.value.to_signed())

# unit tests

async def clock_test(dut):
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, unit="ns").start())
    await Timer(5 * CLK_PERIOD_NS, unit="ns")

async def reset_test(dut):
    dut.rstn_i.value = 0
    dut.valid_i.value = 0
    dut.ready_i.value = 0
    await Timer(10 * CLK_PERIOD_NS, unit="ns")
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await Timer(10 * CLK_PERIOD_NS, unit="ns")
    await FallingEdge(dut.clk_i)

# all zeroes
@cocotb.test()
async def single_zeroes_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    height = 4 * width
    stream = np.zeros((height, width), dtype=np.uint8)
    env = TestManager(dut, stream)
    await env.run()

# all ones
@cocotb.test()
async def single_ones_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    height = 4 * width
    stream = np.ones((height, width), dtype=np.uint8)
    env = TestManager(dut, stream)
    await env.run()

# impulse
@cocotb.test()
async def single_impulse_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    height = 4 * width
    stream = np.zeros((height, width), dtype=np.uint8)
    stream[height // 2, width // 2] = 1
    env = TestManager(dut, stream)
    await env.run()    

# alternate
@cocotb.test()
async def single_alternate_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    height = 4 * width
    stream = np.zeros((height, width), dtype=np.uint8)
    stream[::2, ::2] = 1
    stream[1::2, 1::2] = 1
    env = TestManager(dut, stream)
    await env.run()    

# random
@cocotb.test()
async def single_random_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    height = 4 * width
    np.random.seed(42)
    stream = np.random.randint(0, 256, size=(height, width), dtype=np.uint8)
    env = TestManager(dut, stream)
    await env.run()   

@cocotb.test()
async def single_image_test(dut):
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    img = cv.imread("../../jupyter/car.jpg", cv.IMREAD_GRAYSCALE)
    img = img[:, :width]
    env = TestManager(dut, img)
    await env.run()
