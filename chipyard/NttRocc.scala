package nttacc

import chisel3._
import chisel3.util._
import chisel3.BlackBox
import chisel3.experimental.IntParam

import org.chipsalliance.cde.config.Parameters
import freechips.rocketchip.tile._

class NttAccelBlackBox(nttN: Int, nttWidth: Int) extends BlackBox(
  Map(
    "N" -> IntParam(nttN),
    "WIDTH" -> IntParam(nttWidth)
  )) with HasBlackBoxResource {
  override def desiredName: String = "ntt_poly_mult_openroad"

  private val addrWidth = log2Ceil(nttN)

  val io = IO(new Bundle {
    val clk = Input(Clock())
    val rst_n = Input(Bool())
    val start = Input(Bool())
    val done = Output(Bool())
    val busy = Output(Bool())
    val debug_state = Output(UInt(4.W))
    val fwd_done = Output(Bool())
    val inv_done = Output(Bool())
    val fwd_started = Output(Bool())
    val inv_started = Output(Bool())
    val load_coeff = Input(Bool())
    val load_sel = Input(Bool())
    val load_addr = Input(UInt(addrWidth.W))
    val load_data = Input(UInt(nttWidth.W))
    val debug_read_sel = Input(Bool())
    val debug_read_addr = Input(UInt(addrWidth.W))
    val debug_read_data = Output(UInt(nttWidth.W))
    val read_addr = Input(UInt(addrWidth.W))
    val read_data = Output(UInt(nttWidth.W))
    val a_input_mem_we = Output(Bool())
    val a_input_mem_waddr = Output(UInt(addrWidth.W))
    val a_input_mem_wdata = Output(UInt(nttWidth.W))
    val b_input_mem_we = Output(Bool())
    val b_input_mem_waddr = Output(UInt(addrWidth.W))
    val b_input_mem_wdata = Output(UInt(nttWidth.W))
    val input_mem_read_addr = Output(UInt(addrWidth.W))
    val a_mem_read_data = Input(UInt(nttWidth.W))
    val b_mem_read_data = Input(UInt(nttWidth.W))
    val a_ntt_mem_we = Output(Bool())
    val a_ntt_mem_addr = Output(UInt(addrWidth.W))
    val a_ntt_mem_wdata = Output(UInt(nttWidth.W))
    val a_ntt_mem_rdata = Input(UInt(nttWidth.W))
    val b_ntt_mem_we = Output(Bool())
    val b_ntt_mem_addr = Output(UInt(addrWidth.W))
    val b_ntt_mem_wdata = Output(UInt(nttWidth.W))
    val b_ntt_mem_rdata = Input(UInt(nttWidth.W))
    val c_ntt_mem_we = Output(Bool())
    val c_ntt_mem_addr = Output(UInt(addrWidth.W))
    val c_ntt_mem_wdata = Output(UInt(nttWidth.W))
    val c_ntt_mem_rdata = Input(UInt(nttWidth.W))
  })

  addResource("/ntt_poly_mult_openroad.sv")
  addResource("/ntt_forward.sv")
  addResource("/ntt_inverse.sv")
  addResource("/ntt_cg_address_gen.v")
  addResource("/ntt_bank_switch.v")
  addResource("/ntt_coeff_banks.v")
  addResource("/ntt_coeff_bank_single.v")
  addResource("/twiddle_bram.v")
  addResource("/twiddle_bram_multiport.v")
  addResource("/bram_tdp.v")
  addResource("/ntt_pointwise_mult.v")
  addResource("/ntt_control_parallel.v")
  addResource("/ntt_butterfly.v")
  addResource("/ntt_butterfly_inverse.v")
  addResource("/coeff_ram.v")
  addResource("/mod_add.v")
  addResource("/mod_sub.v")
  addResource("/mod_mult.v")
  addResource("/barrett_reduction.v")
  addResource("/barrett_mult.v")
  addResource("/montgomery_reduction.v")
  addResource("/twiddle_rom.v")
  addResource("/inverse_twiddle_rom.v")
}

class NttRoCC(opcodes: OpcodeSet)(implicit p: Parameters) extends LazyRoCC(opcodes) {
  override lazy val module = new NttRoCCModuleImp(this)
}

class NttRoCCModuleImp(outer: NttRoCC)(implicit p: Parameters) extends LazyRoCCModuleImp(outer)
  with HasCoreParameters {
  private val nttN = 4096
  private val nttWidth = 32
  private val addrWidth = log2Ceil(nttN)

  private val functStart = 0.U(7.W)
  private val functLoadA = 1.U(7.W)
  private val functLoadB = 2.U(7.W)
  private val functRead = 3.U(7.W)
  private val functStatus = 4.U(7.W)
  private val functDebugReadA = 5.U(7.W)
  private val functDebugReadB = 6.U(7.W)

  val blackbox = Module(new NttAccelBlackBox(nttN, nttWidth))
  val aInputMem = SyncReadMem(nttN, UInt(nttWidth.W))
  val bInputMem = SyncReadMem(nttN, UInt(nttWidth.W))
  val aNttMem = SyncReadMem(nttN, UInt(nttWidth.W))
  val bNttMem = SyncReadMem(nttN, UInt(nttWidth.W))
  val cNttMem = SyncReadMem(nttN, UInt(nttWidth.W))
  aInputMem.suggestName("ntt_a_input_mem")
  bInputMem.suggestName("ntt_b_input_mem")
  aNttMem.suggestName("ntt_a_ntt_mem")
  bNttMem.suggestName("ntt_b_ntt_mem")
  cNttMem.suggestName("ntt_c_ntt_mem")

  blackbox.io.clk := clock
  blackbox.io.rst_n := !reset.asBool
  blackbox.io.a_mem_read_data := aInputMem.readWrite(
    Mux(blackbox.io.a_input_mem_we, blackbox.io.a_input_mem_waddr, blackbox.io.input_mem_read_addr),
    blackbox.io.a_input_mem_wdata,
    true.B,
    blackbox.io.a_input_mem_we
  )
  blackbox.io.b_mem_read_data := bInputMem.readWrite(
    Mux(blackbox.io.b_input_mem_we, blackbox.io.b_input_mem_waddr, blackbox.io.input_mem_read_addr),
    blackbox.io.b_input_mem_wdata,
    true.B,
    blackbox.io.b_input_mem_we
  )
  blackbox.io.a_ntt_mem_rdata := aNttMem.readWrite(
    blackbox.io.a_ntt_mem_addr,
    blackbox.io.a_ntt_mem_wdata,
    true.B,
    blackbox.io.a_ntt_mem_we
  )
  blackbox.io.b_ntt_mem_rdata := bNttMem.readWrite(
    blackbox.io.b_ntt_mem_addr,
    blackbox.io.b_ntt_mem_wdata,
    true.B,
    blackbox.io.b_ntt_mem_we
  )
  blackbox.io.c_ntt_mem_rdata := cNttMem.readWrite(
    blackbox.io.c_ntt_mem_addr,
    blackbox.io.c_ntt_mem_wdata,
    true.B,
    blackbox.io.c_ntt_mem_we
  )

  val cmd = Queue(io.cmd)
  val respValidReg = RegInit(false.B)
  val respDataReg = RegInit(0.U(xLen.W))
  val savedRd = Reg(UInt(5.W))
  val readAddrReg = RegInit(0.U(addrWidth.W))
  val readPending = RegInit(false.B)
  val readWait = RegInit(false.B)
  val debugReadPending = RegInit(false.B)
  val debugReadWait = RegInit(false.B)
  val debugReadSel = RegInit(false.B)
  val waitForDone = RegInit(false.B)
  val doneLatched = RegInit(false.B)
  val fwdDoneLatched = RegInit(false.B)
  val invDoneLatched = RegInit(false.B)
  val fwdStartedLatched = RegInit(false.B)
  val invStartedLatched = RegInit(false.B)

  val funct = cmd.bits.inst.funct
  val isStart = funct === functStart
  val isLoadA = funct === functLoadA
  val isLoadB = funct === functLoadB
  val isRead = funct === functRead
  val isStatus = funct === functStatus
  val isDebugReadA = funct === functDebugReadA
  val isDebugReadB = funct === functDebugReadB

  val cmdBusy = respValidReg || readPending || readWait || debugReadPending || debugReadWait || waitForDone || blackbox.io.busy
  val canAcceptStatus = isStatus && !respValidReg && !readPending && !readWait && !debugReadPending && !debugReadWait && !waitForDone
  cmd.ready := !cmdBusy || canAcceptStatus

  val acceptCmd = cmd.fire

  blackbox.io.start := acceptCmd && isStart
  blackbox.io.load_coeff := acceptCmd && (isLoadA || isLoadB)
  blackbox.io.load_sel := isLoadB
  blackbox.io.load_addr := cmd.bits.rs1(addrWidth - 1, 0)
  blackbox.io.load_data := cmd.bits.rs2(nttWidth - 1, 0)
  blackbox.io.debug_read_addr := readAddrReg
  blackbox.io.debug_read_sel := debugReadSel
  blackbox.io.read_addr := readAddrReg

  when(acceptCmd && cmd.bits.inst.xd) {
    savedRd := cmd.bits.inst.rd
  }

  when(acceptCmd && isRead) {
    readAddrReg := cmd.bits.rs1(addrWidth - 1, 0)
    readPending := cmd.bits.inst.xd
    readWait := cmd.bits.inst.xd
  }

  when(acceptCmd && (isDebugReadA || isDebugReadB)) {
    readAddrReg := cmd.bits.rs1(addrWidth - 1, 0)
    debugReadSel := isDebugReadB
    debugReadPending := cmd.bits.inst.xd
    debugReadWait := cmd.bits.inst.xd
  }

  when(acceptCmd && isStart) {
    waitForDone := cmd.bits.inst.xd
    doneLatched := false.B
    fwdDoneLatched := false.B
    invDoneLatched := false.B
    fwdStartedLatched := false.B
    invStartedLatched := false.B
  }

  when(blackbox.io.done) {
    doneLatched := true.B
  }

  when(blackbox.io.fwd_done) {
    fwdDoneLatched := true.B
  }

  when(blackbox.io.inv_done) {
    invDoneLatched := true.B
  }

  when(blackbox.io.fwd_started) {
    fwdStartedLatched := true.B
  }

  when(blackbox.io.inv_started) {
    invStartedLatched := true.B
  }

  when(acceptCmd && isStatus && cmd.bits.inst.xd) {
    respValidReg := true.B
    respDataReg := (doneLatched.asUInt | (blackbox.io.busy.asUInt << 1) | (blackbox.io.debug_state.asUInt << 4) | (fwdDoneLatched.asUInt << 8) | (invDoneLatched.asUInt << 9) | (fwdStartedLatched.asUInt << 10) | (invStartedLatched.asUInt << 11)).pad(xLen)
  }

  when(acceptCmd && cmd.bits.inst.xd && !(isRead || isStart || isStatus || isDebugReadA || isDebugReadB)) {
    respValidReg := true.B
    respDataReg := 0.U
  }

  when(debugReadWait) {
    debugReadWait := false.B
  }

  when(readWait) {
    readWait := false.B
  }

  when(debugReadPending && !debugReadWait && !respValidReg) {
    respValidReg := true.B
    respDataReg := blackbox.io.debug_read_data
    debugReadPending := false.B
  }

  when(readPending && !readWait && !respValidReg) {
    respValidReg := true.B
    respDataReg := blackbox.io.read_data
    readPending := false.B
  }

  when(waitForDone && blackbox.io.done && !respValidReg) {
    respValidReg := true.B
    respDataReg := 0.U
    waitForDone := false.B
  }

  when(io.resp.fire) {
    respValidReg := false.B
  }

  io.resp.valid := respValidReg
  io.resp.bits.rd := savedRd
  io.resp.bits.data := respDataReg

  io.mem.req.valid := false.B
  io.mem.req.bits := DontCare
  io.mem.s1_kill := false.B
  io.mem.s2_kill := false.B
  io.mem.s1_data := DontCare
  io.mem.keep_clock_enabled := true.B

  io.busy := respValidReg || readPending || readWait || debugReadPending || debugReadWait || waitForDone || blackbox.io.busy
  io.interrupt := false.B
}
