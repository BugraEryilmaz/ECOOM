import FIFO::*;
import SpecialFIFOs::*;
import Ehr::*;
import RVUtil::*;
import PEUtil::*;
import MemTypes::*;

interface LSU#(numeric type physicalRegSize, numeric type robTagSize, numeric type inflightCounterSize);
    interface PE#(physicalRegSize, robTagSize) pe;
    method Action sendStore();

    method Action sendReq(CacheReq req);
    method ActionValue#(Word) getResp();
endinterface

module mkLSU(LSU#(physicalRegSize, robTagSize, nInflight));
    // Communication FIFOs //
    FIFO#(PEInput#(physicalRegSize, robTagSize)) inputFIFO <- mkBypassFIFO;
    FIFO#(PEResult#(physicalRegSize, robTagSize)) outputFIFO <- mkBypassFIFO;
    FIFO#(Bool) sendStoreFIFO <- mkBypassFIFO;
    
    Reg#(Bit#(TLog#(nInflight))) inflightCounter <- mkReg(0);
    Reg#(Bit#(TLog#(nInflight))) poisonCounter <- mkReg(0);
    FIFO#(DecodedInst) inflightFIFO <- mkFIFO;

    FIFO#(CacheReq) cacheReqFIFO <- mkBypassFIFO;
    FIFO#(Word) cacheRespFIFO <- mkBypassFIFO;

    PulseWire flushing <- mkPulseWire;
    
    // RULES //
    rule addressGenerate (!flushing && (inflightCounter < fromInteger(valueOf(nInflight) - 1)));
        let in = inputFIFO.first;
        inputFIFO.deq;
        inflightCounter <= inflightCounter + 1;

        let addr = in.src1 + in.imm;
        if (getInstFields(in.dInst.inst).opcode == op_LOAD) begin
            cacheReqFIFO.enq(CacheReq{
                word_byte: 0,
                addr: {addr[31:2], 2'b00},
                data: ?
                });
            end
        else begin
            sendStoreFIFO.deq;

            let offset = addr[1: 0];
            let shift_amount = {offset, 3'b000};
            let funct3 = getInstFields(in.dInst.inst).funct3;
            let size = funct3[1:0];
            let byte_en = 0;
            case (size) matches
                2'b00: // Byte
                    byte_en = 4'b0000 << offset;
                2'b01: // Half 
                    byte_en = 4'b0011 << offset;
                2'b10: // Word
                    byte_en = 4'b1111 << offset;
            endcase

            let data = in.src2 << shift_amount;
        end

        inflightFIFO.enq(in.dInst);
    endrule

    rule waitRequest (!flushing);

    endrule

    rule flushEntries (flushing);
        poisonCounter <= inflightCounter;
        inputFIFO.clear;
        outputFIFO.clear;
    endrule

    // INTERFACE //
    interface pe = interface PE#(physicalRegSize, robTagSize);
        method Action put(PEInput#(physicalRegSize, robTagSize) entry);
            noAction;
        endmethod

        method ActionValue#(PEResult#(physicalRegSize, robTagSize)) get();
            noAction;
            return ?;
        endmethod
        
        method Action flush();
            noAction;
        endmethod
    endinterface;
    
    method Action sendStore();
        noAction;
    endmethod
    
    method Action sendReq(CacheReq req);
        noAction;
    endmethod

    method ActionValue#(Word) getResp();
        noAction;
        return ?;
    endmethod
endmodule

module mkLSUSized(LSU#(6, 6, 16));
    LSU#(6, 6, 16) lsu <- mkLSU;
    return lsu;
endmodule
