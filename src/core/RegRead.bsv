import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import RVUtil::*;
import PEUtil::*;
import RegisterFile::*;
import ReservationStation::*;

interface RegRead#(numeric type physicalRegSize, numeric type robTagSize);
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry);
    method ActionValue#(PEInput#(physicalRegSize, robTagSize)) get();
    method Action flush();

    method Action putToRF(Bit#(physicalRegSize) rd, Bit#(32) val);
endinterface

module mkRegRead(RegRead#(physicalRegSize, robTagSize));
    // Communication FIFOs //
    FIFO#(RSEntry#(physicalRegSize, robTagSize)) inputFIFO <- mkBypassFIFO;
    FIFO#(PEInput#(physicalRegSize, robTagSize)) outputFIFO <- mkBypassFIFO;
    PulseWire flushing <- mkPulseWire;

    RFIfc#(physicalRegSize, 32) rf <- mkRegisterFile;

    // RULES //
    rule rlProcess (!flushing);
        let val = inputFIFO.first;
        inputFIFO.deq;

        Bit#(32) src1 = 0;
        if (val.rs1 matches tagged Valid .rs1)
            src1 <- rf.read(rs1);

        Bit#(32) src2 = 0;
        if (val.rs2 matches tagged Valid .rs2)
            src2 <- rf.read(rs2);

        Bit#(32) imm = getImmediate(val.dInst);

        outputFIFO.enq(PEInput {
            pe: val.pe,
            tag: val.tag,
            pc: val.pc,
            dInst: val.dInst,
            imm: imm,
            src1: src1,
            src2: src2,
            rd: val.rd
        });
    endrule

    rule rlFlush (flushing);
        inputFIFO.clear;
        outputFIFO.clear;
    endrule

    // METHODS //
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry) if (!flushing);
        inputFIFO.enq(entry);
    endmethod

    method ActionValue#(PEInput#(physicalRegSize, robTagSize)) get() if (!flushing);
        let val = outputFIFO.first;
        outputFIFO.deq;
        return val;
    endmethod

    method Action flush() = flushing.send;
    method Action putToRF(Bit#(physicalRegSize) rd, Bit#(32) val) if (!flushing) = rf.write(rd, val);
endmodule

module mkRegReadSized(RegRead#(6, 6));
    RegRead#(6, 6) regRead <- mkRegRead;
    return regRead;
endmodule