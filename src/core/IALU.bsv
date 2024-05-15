import FIFO::*;
import SpecialFIFOs::*;
import RVUtil::*;
import PEUtil::*;

module mkIALU(PE#(physicalRegSize, robTagSize));

    // Communication FIFOs //
    FIFO#(PEInput#(physicalRegSize, robTagSize)) inputFIFO <- mkBypassFIFO;
    FIFO#(PEResult#(physicalRegSize, robTagSize)) outputFIFO <- mkBypassFIFO;
    PulseWire flushing <- mkPulseWire;

    // RULES //
    rule process (!flushing);
        let in = inputFIFO.first;
        inputFIFO.deq;

        let dInst = in.dInst;
        let inst = dInst.inst;
        let res = execALU32(inst, in.src1, in.src2, in.imm, in.pc);

        outputFIFO.enq(PEResult{
            tag: in.tag,
            result: res,
            rd: in.rd,
            jump_pc: Invalid
        });
    endrule

    rule flushEntries (flushing);
        inputFIFO.clear;
        outputFIFO.clear;
    endrule

    // INTERFACE //
    method Action put(PEInput#(physicalRegSize, robTagSize) entry) if (!flushing);
        inputFIFO.enq(entry);
    endmethod

    method ActionValue#(PEResult#(physicalRegSize, robTagSize)) get() if (!flushing);
        let val = outputFIFO.first;
        outputFIFO.deq;
        return val;
    endmethod

    method Action flush();
        flushing.send;
    endmethod
endmodule

module mkIALUSized(PE#(6, 6));
    PE#(6, 6) ialu <- mkIALU;

    method Action put(PEInput#(6, 6) entry) = ialu.put(entry);
    method ActionValue#(PEResult#(6, 6)) get() = ialu.get();
    method Action flush() = ialu.flush();
endmodule