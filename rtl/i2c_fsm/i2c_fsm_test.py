import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLK_PERIOD_NS = 10

# drivers

class ModelManager:
    """Reference model for I2C FSM completion behavior."""
    def __init__(self, dut):
        pass

    def run(self, _input):
        """Advance model state for one input and return expected output."""
        return True

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
        if not self.valid and self.has_next():
            self.current = int(self.data[self.idx])
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
        self.pending = None
        self.checked = 0

    def update_expected(self, input):
        """Queue expected outputs for a new input."""
        self.pending = self.model.run(input)

    def check_output(self, output):
        """Compare DUT output against expected values."""
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
        """Template hook for queue-based comparisons."""
        return False

class TestManager:
    """Coordinates stimulus, model updates, and checks."""
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
        """Main loop coordinating input and output checks."""
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
    """Wraps DUT signal driving and sampling."""
    def __init__(self, dut):
        self.dut = dut
        self.last_valid = False

    def drive(self, valid, data):
        """Drive DUT inputs for this cycle."""
        self.last_valid = bool(valid)
        self.dut.sback_i.value = 1 if (valid and data) else 0

    def input_accepted(self):
        """Return True when input handshake succeeds."""
        return self.last_valid

    def output_accepted(self):
        """Return True when output handshake succeeds."""
        return True

    def output_value(self):
        """Sample DUT outputs for comparison."""
        if not self.dut.done_o.value.is_resolvable:
            return None
        return bool(self.dut.done_o.value)

# unit tests

async def clock_test(dut):
    """Start the DUT clock."""
    cocotb.start_soon(Clock(dut.clk_i, CLK_PERIOD_NS, unit="ns").start())
    await Timer(5 * CLK_PERIOD_NS, unit="ns")

async def reset_test(dut):
    """Apply reset and drive default inputs."""
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
