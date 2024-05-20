`include "Logging.bsv"
import FIFO::*;
import SpecialFIFOs::*;
import Ehr::*;
import RVUtil::*;
import PEUtil::*;
import MemTypes::*;

interface LSU#(numeric type physicalRegSize, numeric type robTagSize, numeric type nInflight);
    interface PE#(physicalRegSize, robTagSize) pe;
    method Action sendStore();

    method ActionValue#(CacheReq) sendReq();
    method Action getResp(Word resp);
endinterface

module mkLSU(LSU#(physicalRegSize, robTagSize, nInflight));
    // Communication FIFOs //
    FIFO#(PEInput#(physicalRegSize, robTagSize)) inputFIFO <- mkBypassFIFO;
    FIFO#(PEResult#(physicalRegSize, robTagSize)) outputFIFO <- mkBypassFIFO;
    FIFO#(Bool) sendStoreFIFO <- mkBypassFIFO;
    
    Ehr#(2, Bit#(TLog#(TAdd#(nInflight, 1)))) inflightCounter <- mkEhr(0);
    Ehr#(2, Bit#(TLog#(TAdd#(nInflight, 1)))) poisonCounter <- mkEhr(0);
    FIFO#(MemBussiness#(physicalRegSize, robTagSize)) inflightFIFO <- mkSizedFIFO(valueOf(nInflight));

    FIFO#(CacheReq) cacheReqFIFO <- mkBypassFIFO;
    FIFO#(Word) cacheRespFIFO <- mkBypassFIFO;

    PulseWire flushing <- mkPulseWire;
    
    // RULES //
    rule addressGenerate (!flushing);
        let in = inputFIFO.first;
        inputFIFO.deq;
        inflightCounter[0] <= inflightCounter[0] + 1;

        let addr = in.src1 + in.imm;
        let offset = addr[1: 0];
        let isLoad = getInstFields(in.dInst.inst).opcode == op_LOAD;
        let funct3 = getInstFields(in.dInst.inst).funct3;
        if (isLoad) begin
            cacheReqFIFO.enq(CacheReq{
                word_byte: 0,
                addr: {addr[31:2], 2'b00},
                data: ?
                });
            end
        else begin
            sendStoreFIFO.deq;

            let shift_amount = {offset, 3'b000};
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

        let op = MemBussiness{
            tag: in.tag,
            rd: in.rd,
            funct3: funct3,
            isStore: !isLoad,
            offset: offset,
            k_id: in.k_id
        };

        `LOG(("[LSU] Sending ", fshow(op)));

        inflightFIFO.enq(op);
    endrule

    rule waitRequest (!flushing);
        let resp = cacheRespFIFO.first;
        cacheRespFIFO.deq;
        let req = inflightFIFO.first;
        inflightFIFO.deq;
        inflightCounter[1] <= inflightCounter[1] - 1;
        
        `LOG(("[LSU] Received ", fshow(resp)));

        if(poisonCounter[1] > 0) begin
            poisonCounter[1] <= poisonCounter[1] - 1;
        end
        else if(!req.isStore) begin
            Bit#(32) result = ?;
            resp = resp >> {req.offset, 3'b000};
            case(req.funct3) matches
                3'b000 : result = signExtend(resp[7:0]);
                3'b001 : result = signExtend(resp[15:0]);
                3'b100 : result = zeroExtend(resp[7:0]);
                3'b101 : result = zeroExtend(resp[15:0]);
                3'b010 : result = resp;
            endcase
            outputFIFO.enq(PEResult{
                tag: req.tag,
                rd: req.rd,
                result: result,
                jump_pc: Invalid,
                k_id: req.k_id
            });
        end
    endrule

    rule flushEntries (flushing);
        poisonCounter[0] <= inflightCounter[0];
        inputFIFO.clear;
        outputFIFO.clear;
    endrule

    // INTERFACE //
    interface pe = interface PE#(physicalRegSize, robTagSize);
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
    endinterface;
    
    method Action sendStore() if (!flushing);
        sendStoreFIFO.enq(True);
    endmethod
    
    method ActionValue#(CacheReq) sendReq();
        let val = cacheReqFIFO.first;
        cacheReqFIFO.deq;
        return val;
    endmethod

    method Action getResp(Word resp);
        cacheRespFIFO.enq(resp);
    endmethod
endmodule

module mkLSUSized(LSU#(6, 6, 16));
    LSU#(6, 6, 16) lsu <- mkLSU;
    return lsu;
endmodule
