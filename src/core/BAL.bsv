import FIFO::*;
import SpecialFIFOs::*;
import RVUtil::*;
import PEUtil::*;

module mkBAL(PE#(physicalRegSize, robTagSize));

    // Communication FIFOs //
    FIFO#(PEInput#(physicalRegSize, robTagSize)) inputFIFO <- mkBypassFIFO;
    FIFO#(PEResult#(physicalRegSize, robTagSize)) outputFIFO <- mkBypassFIFO;
    PulseWire flushing <- mkPulseWire;

    // RULES //
    rule process (!flushing);
        let in = inputFIFO.first;
        inputFIFO.deq;

        let inst = in.dInst.inst;
        let imm = in.imm;
        let pc = in.pc;

        Bool isJAL = (inst[2] == 1'b1) && (inst[3] == 1'b1);
        Bool isJALR = (inst[2] == 1'b1) && (inst[3] == 1'b0);
    
        Bit#(32) incPC = pc + 4;
        Bit#(3) funct3 = inst[14:12];
    
        Maybe#(Bit#(32)) result = Invalid;
    
        if (isJAL) begin
            result = tagged Valid (pc + imm);
        end else if (isJALR) begin
            result = tagged Valid ((pc + imm) & ~1); // zero out LSB
        end else begin
            // Branch
            let taken = case (funct3)
                        fn3_BEQ:    (in.src1 == in.src2);
                        fn3_BNE:    (in.src1 != in.src2);
                        fn3_BLT:    signedLT(in.src1, in.src2);
                        fn3_BGE:    signedGE(in.src1, in.src2);
                        fn3_BLTU:   (in.src1 < in.src2);
                        fn3_BGEU:   (in.src1 >= in.src2);
                    endcase;
            if (taken) begin
                result = tagged Valid(pc + imm);
            end else begin
                result = Invalid;
            end
        end

        outputFIFO.enq(PEResult{
            tag: in.tag,
            rd: in.rd,
            result: incPC,
            jump_pc: result,
            k_id: in.k_id
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

module mkBALSized(PE#(6, 6));
    PE#(6, 6) pe <- mkBAL;
    return pe;
endmodule