"""coverage reset, sobel x and y convolution, trying to implement uvm like test plan"""
import numpy as np
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

CLK_PERIOD_NS = 10

# drivers

class ModelManager:
    def __init__(self, dut):
        self.width = int(dut.DEPTH_P.value)
        self.buf = np.zeros((3, self.width)) / 0  # NaN to detect first valid conv

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
            await RisingEdge(self.dut.clk_i)

            # drive valid and hold data stable until accepted
            self.dut.valid_i.value = 1
            self.dut.data_i.value = self.data[self.idx]

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
        # reminder: still needs a termination condition
        while True:
            await FallingEdge(self.dut.clk_i)
            if self.dut.valid_o.value and self.dut.ready_i.value:
                self.queue.append(
                    (
                        int(self.dut.gx_o.value.signed_integer),
                        int(self.dut.gy_o.value.signed_integer)
                    )
                )

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

        # stream is the stimulus, in_queue records accepted inputs
        self.input = InputManager(dut, stream)
        self.output = OutputManager(dut, self.out_queue)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)

    async def run(self):
        # record input into input queue
        cocotb.start_soon(self.input.run(self.in_queue))
        cocotb.start_soon(self.output.run())

        while True:
            if self.in_queue and self.out_queue:
                input = self.in_queue.popleft()
                output = self.out_queue.popleft()
                self.scoreboard.run(input, output)
            
# helpers

# unit tests


        

