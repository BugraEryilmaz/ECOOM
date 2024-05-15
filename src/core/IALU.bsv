import FIFO::*;
import SpecialFIFOs::*;
import RVUtil::*;
import PEUtil::*;

interface IALU#(numeric type physicalRegSize, numeric type robTagSize);
    method Action put(PEInput#(physicalRegSize, robTagSize) entry);
    method ActionValue#(PEResult#(physicalRegSize, robTagSize)) get();
    method Action flush();
endinterface

module mkIALU(IALU#(physicalRegSize, robTagSize));

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
        let res = execALU32(inst, in.src1, in.src2, getImmediate(dInst), in.pc);

        outputFIFO.enq(PEResult{
            tag: in.tag,
            result: res,
            rd: in.rd,
            pc: in.pc
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

module mkIALUSized(IALU#(6, 6));
    IALU#(6, 6) ialu <- mkIALU;

    method Action put(PEInput#(6, 6) entry);
        ialu.put(entry);
    endmethod

    method ActionValue#(PEResult#(6, 6)) get();
        let val <- ialu.get();
        return val;
    endmethod

    method Action flush();
        ialu.flush();
    endmethod

endmodule