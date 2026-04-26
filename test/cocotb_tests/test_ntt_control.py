"""
Cocotb testbench for parallel NTT control FSM
Tests stage/butterfly scheduling and lane validity.

NOTE: The FSM has a STAGE_DRAIN state between stages to allow the butterfly
pipeline to drain before advancing. This adds PIPELINE_DEPTH cycles between
each stage.
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import os

# NTT parameters (must match DUT defaults)
N = int(os.getenv("NTT_N", "4096"))
PARALLEL = 8
PIPELINE_DEPTH = 3  # Default value in ntt_control_parallel
TOTAL_BUTTERFLIES = N // 2
CYCLES_PER_STAGE = (TOTAL_BUTTERFLIES + PARALLEL - 1) // PARALLEL
LOGN = N.bit_length() - 1


def expected_lane_valid(cycle_in_stage):
    """Calculate expected lane_valid mask for a given cycle within a stage."""
    base = cycle_in_stage * PARALLEL
    return [(base + lane) < TOTAL_BUTTERFLIES for lane in range(PARALLEL)]


@cocotb.test()
async def test_idle_to_done(dut):
    """Test basic state transitions: IDLE -> COMPUTE -> STAGE_DRAIN -> ... -> DONE"""
    dut._log.info("Testing FSM state transitions")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.stall.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    # Should be in IDLE
    assert int(dut.done.value) == 0, "Should not be done in IDLE"
    assert int(dut.busy.value) == 0, "Should not be busy in IDLE"

    # Start the FSM
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    # Should now be busy
    assert int(dut.busy.value) == 1, "Should be busy after start"
    assert int(dut.done.value) == 0, "Should not be done yet"

    # Run until done
    timeout = 5000
    cycles = 0
    while int(dut.done.value) == 0 and cycles < timeout:
        await RisingEdge(dut.clk)
        cycles += 1

    assert cycles < timeout, f"FSM did not complete within {timeout} cycles"
    dut._log.info(f"FSM completed in {cycles} cycles")

    # Verify done state
    await Timer(1, unit="ns")
    assert int(dut.done.value) == 1, "Should be done"


@cocotb.test()
async def test_stage_and_cycle_progression(dut):
    """Verify stage and cycle counters step as expected with STAGE_DRAIN."""
    dut._log.info("Testing stage/cycle progression with STAGE_DRAIN")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.stall.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Wait until controller is busy
    while int(dut.busy.value) == 0:
        await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    # Track stage transitions
    prev_stage = -1
    stage_start_cycles = []
    total_cycles = 0

    while int(dut.done.value) == 0:
        stage_val = int(dut.stage.value)
        cycle_val = int(dut.cycle.value)
        draining = int(dut.draining.value)

        if stage_val != prev_stage:
            stage_start_cycles.append(total_cycles)
            dut._log.info(
                f"Stage {stage_val} started at cycle {total_cycles} "
                f"(cycle_counter={cycle_val}, draining={draining})"
            )
            prev_stage = stage_val

        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        total_cycles += 1

        if total_cycles > 5000:
            raise RuntimeError("Test timeout")

    dut._log.info(f"Total cycles: {total_cycles}")
    dut._log.info(f"Stage start cycles: {stage_start_cycles}")

    # Verify we went through all LOGN stages (0 to LOGN-1)
    assert len(stage_start_cycles) == LOGN, (
        f"Expected {LOGN} stages, got {len(stage_start_cycles)}"
    )

    # Verify stage spacing accounts for STAGE_DRAIN
    # Each stage should be CYCLES_PER_STAGE + PIPELINE_DEPTH apart (except last)
    expected_spacing = CYCLES_PER_STAGE + PIPELINE_DEPTH
    for i in range(1, len(stage_start_cycles)):
        actual_spacing = stage_start_cycles[i] - stage_start_cycles[i - 1]
        # Allow +1 tolerance for the drain->compute transition
        assert (
            actual_spacing == expected_spacing or actual_spacing == expected_spacing + 1
        ), f"Stage {i} spacing: expected ~{expected_spacing}, got {actual_spacing}"

    dut._log.info("Stage progression test passed")


@cocotb.test()
async def test_lane_valid_mask(dut):
    """Verify lane_valid mask is correct during COMPUTE and zero during STAGE_DRAIN."""
    dut._log.info("Testing lane_valid mask")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.stall.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Wait until controller is busy
    while int(dut.busy.value) == 0:
        await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    # Test first two stages worth of cycles
    test_cycles = (CYCLES_PER_STAGE + PIPELINE_DEPTH) * 2 + 5
    compute_cycles = 0
    drain_cycles = 0

    for _ in range(test_cycles):
        if int(dut.done.value) == 1:
            break

        cycle_val = int(dut.cycle.value)
        draining = int(dut.draining.value)
        lane_valid_raw = int(dut.lane_valid.value)
        lane_valid = [(lane_valid_raw >> lane) & 1 for lane in range(PARALLEL)]

        if draining:
            # During STAGE_DRAIN, lane_valid should be all zeros
            drain_cycles += 1
            assert all(v == 0 for v in lane_valid), (
                f"lane_valid should be 0 during STAGE_DRAIN, got {lane_valid}"
            )
        else:
            # During COMPUTE, lane_valid should match expected pattern
            compute_cycles += 1
            expected = expected_lane_valid(cycle_val)
            assert lane_valid == [1 if v else 0 for v in expected], (
                f"lane_valid mismatch at cycle {cycle_val}: {lane_valid} != {expected}"
            )

        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

    dut._log.info(
        f"Verified {compute_cycles} COMPUTE cycles and {drain_cycles} STAGE_DRAIN cycles"
    )
    assert compute_cycles > 0, "Should have seen some COMPUTE cycles"
    assert drain_cycles > 0, "Should have seen some STAGE_DRAIN cycles"
    dut._log.info("lane_valid mask test passed")
