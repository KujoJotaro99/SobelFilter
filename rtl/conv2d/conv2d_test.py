"""coverage reset, sobel x and y convolution, trying to implement uvm like test plan"""
import numpy as np
import cv2 as cv
from collections import deque

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
    def __init__(self, dut, stream):
        self.dut = dut
        self.data = stream.flatten()
        self.idx = 0

    def has_next(self):
        return self.idx < len(self.data)

    def next(self):
        val = int(self.data[self.idx])
        self.idx += 1
        return val

    async def run(self, in_queue):
        self.dut.valid_i.value = 0

        while self.has_next():
            await FallingEdge(self.dut.clk_i)

            # drive valid and hold data stable until accepted
            self.dut.valid_i.value = 1
            self.dut.data_i.value = int(self.data[self.idx])

            if self.dut.ready_o.value:
                in_queue.append(self.next())
        self.dut.valid_i.value = 0

class OutputManager:
    def __init__(self, dut, out_queue):
        self.dut = dut
        self.queue = out_queue

    async def run(self):
        # the consumer is always ready
        self.dut.ready_i.value = 1
        while True:
            await FallingEdge(self.dut.clk_i)

            if self.dut.valid_o.value and self.dut.ready_i.value:
                gx = self.dut.gx_o.value
                gy = self.dut.gy_o.value

                if not gx.is_resolvable or not gy.is_resolvable:
                    continue

                self.queue.append((gx.to_signed(), gy.to_signed()))

class ScoreManager:
    def __init__(self, model):
        self.model = model

    def run(self, input, output):
        gx_exp, gy_exp = self.model.run(input)
        gx_out, gy_out = output
        if gx_exp is not None and gy_exp is not None:
            assert gx_out == gx_exp, f"Mismatch: got {gx_out}, expected {gx_exp}"
            assert gy_out == gy_exp, f"Mismatch: got {gy_out}, expected {gy_exp}"

class TestManager:
    def __init__(self, dut, stream):
        self.in_queue = deque()
        self.out_queue = deque()

        # termination condition
        self.height, self.width = stream.shape
        self.expected_outputs = max(0, (self.height - 2) * (self.width - 2))
        self.checked = 0

        # stream is the stimulus, in_queue records accepted inputs
        self.input = InputManager(dut, stream)
        self.output = OutputManager(dut, self.out_queue)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)

    async def run(self):
        # record input into input queue
        cocotb.start_soon(self.input.run(self.in_queue))
        cocotb.start_soon(self.output.run())

        while self.checked < self.expected_outputs:
            await FallingEdge(self.input.dut.clk_i)

            if self.in_queue and self.out_queue:
                inp = self.in_queue.popleft()
                out = self.out_queue.popleft()
                self.scoreboard.run(inp, out)
                self.checked += 1
    
# unit tests

_clock_started = False

async def reset_test(dut):
    global _clock_started
    if not _clock_started:
        cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, unit="ns").start())
        _clock_started = True
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
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    height = 4 * width
    stream = np.zeros((height, width), dtype=np.uint8)
    env = TestManager(dut, stream)
    await env.run()

# all ones
@cocotb.test()
async def single_ones_test(dut):
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    height = 4 * width
    stream = np.ones((height, width), dtype=np.uint8)
    env = TestManager(dut, stream)
    await env.run()

# impulse
@cocotb.test()
async def single_impulse_test(dut):
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
    img = cv.imread("../jupyter/car.jpg", cv.IMREAD_GRAYSCALE)
    img = img[:, :width]
    env = TestManager(dut, img)
    await env.run()