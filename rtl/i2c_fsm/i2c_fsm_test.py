import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

# drivers

class ModelManager:
    def __init__(self, dut):
        pass

    def run(self, _input):
        return True

class InputManager:
    def __init__(self, stream):
        self.data = list(stream)
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
        self.checked = 0

    def update_expected(self, input):
        self.pending = self.model.run(input)

    def check_output(self, output):
        if output is None:
            return False
        if self.pending is None:
            return False
        if output:
            self.checked += 1
            self.pending = None
            return True
        return False

    def drain(self):
        return False

class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        self.expected_outputs = 1
        self.checked = 0
        self.in_stride = 1
        self.out_stride = 1
        self.max_cycles = 500

    async def run(self):
        try:
            self.input.drive(self.handshake)
            cycle = 0
            while (self.checked < self.expected_outputs) and (cycle < self.max_cycles):
                await FallingEdge(self.handshake.dut.clk_i)
                cycle += 1

                if (cycle % self.in_stride) == 0:
                    if self.handshake.input_accepted():
                        inp = self.input.accept()
                        if inp is not None:
                            self.scoreboard.update_expected(inp)
                    self.input.drive(self.handshake)
                else:
                    self.handshake.drive(False, 0)

                if (cycle % self.out_stride) == 0:
                    if self.handshake.output_accepted():
                        if self.scoreboard.check_output(self.handshake.output_value()):
                            self.checked = self.scoreboard.checked
        finally:
            self.handshake.dut.sback_i.value = 0

class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut
        self.last_valid = False

    def drive(self, valid, data):
        self.last_valid = bool(valid)
        self.dut.sback_i.value = 1 if (valid and data) else 0

    def input_accepted(self):
        return self.last_valid

    def output_accepted(self):
        return True

    def output_value(self):
        if not self.dut.done_o.value.is_resolvable:
            return None
        return bool(self.dut.done_o.value)

# unit tests

async def clock_test(dut):
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, unit="ns").start())
    await Timer(5 * CLK_PERIOD_NS, unit="ns")

async def reset_test(dut):
    dut.rstn_i.value = 0
    dut.sback_i.value = 0
    await Timer(10 * CLK_PERIOD_NS, unit="ns")
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await Timer(10 * CLK_PERIOD_NS, unit="ns")
    await FallingEdge(dut.clk_i)

@cocotb.test()
async def test_i2c_fsm_done(dut):
    await clock_test(dut)
    await reset_test(dut)
    stream = [1] * 200
    env = TestManager(dut, stream)
    await env.run()
    assert env.checked == env.expected_outputs
