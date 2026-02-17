"""
Cocotb testbench for parallel NTT control FSM
Tests stage/butterfly scheduling and lane validity.
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

# NTT parameters
N = 256
PARALLEL = 8
TOTAL_BUTTERFLIES = N // 2
CYCLES_PER_STAGE = (TOTAL_BUTTERFLIES + PARALLEL - 1) // PARALLEL


def expected_stage_cycle(cycle):
    stage = cycle // CYCLES_PER_STAGE
    stage_cycle = cycle % CYCLES_PER_STAGE
    return stage, stage_cycle


def expected_lane_valid(stage_cycle):
    base = stage_cycle * PARALLEL
    return [(base + lane) < TOTAL_BUTTERFLIES for lane in range(PARALLEL)]


@cocotb.test()
async def test_idle_to_done(dut):
    """Test basic state transitions: IDLE → COMPUTE → DONE"""
    dut._log.info("Testing FSM state transitions")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert int(dut.done.value) == 0
    assert int(dut.busy.value) == 0

    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert int(dut.busy.value) == 1
    assert int(dut.done.value) == 0

    for _ in range(20):
        await RisingEdge(dut.clk)

    assert int(dut.busy.value) == 1


@cocotb.test()
async def test_stage_and_cycle_progression(dut):
    """Verify stage and cycle counters step as expected."""
    dut._log.info("Testing stage/cycle progression")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.start.value = 1
    await RisingEdge(dut.clk)

    # Wait until controller is busy
    while int(dut.busy.value) == 0:
        await RisingEdge(dut.clk)

    total_cycles = CYCLES_PER_STAGE * (N.bit_length() - 1)

    for cycle in range(total_cycles):
        stage_val = int(dut.stage.value)
        cycle_val = int(dut.cycle.value)

        exp_stage, exp_cycle = expected_stage_cycle(cycle)
        assert stage_val == exp_stage, f"Stage mismatch at cycle {cycle}: {stage_val} != {exp_stage}"
        assert cycle_val == exp_cycle, f"Cycle mismatch at cycle {cycle}: {cycle_val} != {exp_cycle}"

        await RisingEdge(dut.clk)


@cocotb.test()
async def test_lane_valid_mask(dut):
    """Verify lane_valid mask for multiple cycles."""
    dut._log.info("Testing lane_valid mask")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.start.value = 1
    await RisingEdge(dut.clk)

    while int(dut.busy.value) == 0:
        await RisingEdge(dut.clk)

    for _ in range(CYCLES_PER_STAGE + 2):
        cycle_val = int(dut.cycle.value)
        lane_valid = [int(dut.lane_valid.value[lane]) for lane in range(PARALLEL)]
        expected = expected_lane_valid(cycle_val)

        assert lane_valid == [1 if v else 0 for v in expected], (
            f"lane_valid mismatch at cycle {cycle_val}: {lane_valid} != {expected}"
        )

        await RisingEdge(dut.clk)
