"""coverage reset, rgb2gray coefficient approximation, trying to implement uvm like test plan"""
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
    """Reference grayscale model using floating coefficients."""
    def __init__(self, dut):
        self.width = int(dut.WIDTH_P.value)
        self.frac = 8

    def run(self, input):
        """Advance model state for one input and return expected output."""
        # input format [r, g, b]
        r, g, b = input
        gray_exp = r*0.299 + g*0.587 + b*0.114
        return int(gray_exp)

class InputManager:
    """Drives input stream into the DUT with a valid buffer."""
    def __init__(self, stream):
        self.data = stream.reshape(-1, 3)
        self.idx = 0
        self.valid = False
        self.current = None

    def has_next(self):
        """Return True when more inputs remain."""
        return self.idx < len(self.data)

    def drive(self, handshake):
        """Drive the current input and valid flag."""
        if not self.valid and self.has_next():
            self.current = [int(x) for x in self.data[self.idx]]
            self.valid = True
        handshake.drive(self.valid, self.current if self.valid else [0, 0, 0])

    def accept(self):
        """Consume the current input after acceptance."""
        if self.valid:
            self.idx += 1
            self.valid = False
            return self.current
        return None

class ScoreManager:
    """Tracks expected outputs and compares against DUT results."""
    def __init__(self, model, expected_outputs, rms_threshold=10):
        self.model = model
        self.expected_outputs = expected_outputs
        self.rms_threshold = rms_threshold
        self.pending = deque()
        self.sse = 0
        self.n = 0

    def update_expected(self, input):
        """Queue expected outputs for a new input."""
        gray_exp = self.model.run(input)
        if gray_exp is not None:
            self.pending.append(gray_exp)

    def check_output(self, output):
        """Compare DUT output against expected values."""
        gray_out = output
        if gray_out is None:
            return False
        if not self.pending:
            return False
        gray_exp = self.pending.popleft()
        err = int(gray_out) - int(gray_exp)
        self.sse += err * err
        self.n += 1
        if self.n == self.expected_outputs:
            rms = float(np.sqrt(self.sse / self.n))
            assert rms < self.rms_threshold, f"RMS error too high: {rms} (threshold {self.rms_threshold})"
        return True

    def drain(self):
        """Only for queue-based comparisons."""
        return False

class TestManager:
    """Coordinates stimulus, model updates, and checks."""
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)

        self.expected_outputs = int(stream.reshape(-1, 3).shape[0])
        self.checked = 0

        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model, self.expected_outputs, rms_threshold=12)
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
                    self.handshake.dut.valid_i.value = 0

                if (cycle % self.out_stride) == 0:
                    self.handshake.dut.ready_i.value = 1
                else:
                    self.handshake.dut.ready_i.value = 0

                if self.handshake.output_accepted():
                    gray_out = self.handshake.output_value()
                    if self.scoreboard.check_output(gray_out):
                        self.checked += 1

        finally:
            self.handshake.dut.valid_i.value = 0
            self.handshake.dut.ready_i.value = 0

class HandshakeManager:
    """Wraps DUT signal driving and sampling."""
    def __init__(self, dut):
        self.dut = dut

    def drive(self, valid, data_rgb):
        """Drive DUT inputs for this cycle."""
        self.dut.valid_i.value = 1 if valid else 0
        self.dut.red_i.value = int(data_rgb[0])
        self.dut.green_i.value = int(data_rgb[1])
        self.dut.blue_i.value = int(data_rgb[2])

    def input_accepted(self):
        """Return True when input handshake succeeds."""
        return bool(self.dut.valid_i.value and self.dut.ready_o.value)

    def output_accepted(self):
        """Return True when output handshake succeeds."""
        return bool(self.dut.valid_o.value and self.dut.ready_i.value)

    def output_value(self):
        """Sample DUT outputs for comparison."""
        if not self.dut.gray_o.value.is_resolvable:
            return None
        return self.dut.gray_o.value.integer

# unit tests

async def clock_test(dut):
    """Start the DUT clock."""
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, unit="ns").start())
    await Timer(5 * CLK_PERIOD_NS, unit="ns")

async def reset_test(dut):
    """Apply reset and drive default inputs."""
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
    stream = np.zeros((100, 3), dtype=np.uint8)
    env = TestManager(dut, stream)
    await env.run()

# all ones
@cocotb.test()
async def single_ones_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    stream = np.ones((100, 3), dtype=np.uint8)
    env = TestManager(dut, stream)
    await env.run()

# impulse
@cocotb.test()
async def single_impulse_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    stream = np.zeros((100, 3), dtype=np.uint8)
    stream[50, :] = 1
    env = TestManager(dut, stream)
    await env.run()    

# alternate
@cocotb.test()
async def single_alternate_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    stream = np.zeros((100, 3), dtype=np.uint8)
    stream[::2, :] = 1
    env = TestManager(dut, stream)
    await env.run()    

# random
@cocotb.test()
async def single_random_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    np.random.seed(42)
    stream = np.random.randint(0, 256, size=(100, 3), dtype=np.uint8)
    env = TestManager(dut, stream)
    await env.run()   

@cocotb.test()
async def single_image_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.WIDTH_P.value)
    img_path = Path(__file__).resolve().parents[2] / "jupyter" / "car.jpg"
    img = cv.imread(str(img_path))
    # pass in rgb hues in list within list of inputs
    if img is None:
        raise FileNotFoundError(img_path)
    img = cv.cvtColor(img, cv.COLOR_BGR2RGB)
    img = img[:, :width, :]
    env = TestManager(dut, img.astype(np.uint8))
    await env.run()
