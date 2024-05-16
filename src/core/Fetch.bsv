import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;

typedef struct {
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(32) instr;
} FetchToDecode deriving(Bits, FShow);

typedef struct {
    Bit#(32) pc;
    Bit#(32) ppc;
    Bool epoch;
} IMemBussiness deriving(Bits, FShow);

interface Fetch;
    method Action jumpTo(Bit#(32) addr);
    method ActionValue#(FetchToDecode) getInst;
    method ActionValue#(CacheReq) sendReq();
    method Action getResp(Word resp);
endinterface

module mkFetch(Fetch);
    // Communication FIFOs //
    FIFOF#(Bit#(32)) jumpFIFO <- mkBypassFIFOF;
    FIFO#(FetchToDecode) outputFIFO <- mkBypassFIFO;
    FIFO#(CacheReq) reqFIFO <- mkBypassFIFO;
    FIFO#(Word) respFIFO <- mkBypassFIFO;
    FIFO#(IMemBussiness) inflightFIFO <- mkFIFO;

    Reg#(Bit#(32)) pcReg <- mkReg(0);
    Reg#(Bool) epochReg <- mkReg(False);

    // RULES //
    rule rlJump (jumpFIFO.notEmpty);
        let addr = jumpFIFO.first;
        jumpFIFO.deq;
        pcReg <= addr;
        epochReg <= !epochReg;
    endrule

    rule rlAddressGeneration (!jumpFIFO.notEmpty);
        reqFIFO.enq(CacheReq{
            word_byte: 0,
            addr: pcReg,
            data: ?
        });
        
        let ppc = pcReg + 4;
        inflightFIFO.enq(IMemBussiness{
            pc: pcReg,
            ppc: ppc,
            epoch: epochReg
        });

        pcReg <= ppc;
    endrule

    rule rlGetResp (!jumpFIFO.notEmpty);
        let resp = respFIFO.first;
        respFIFO.deq;
        let info = inflightFIFO.first;
        inflightFIFO.deq;

        if(info.epoch == epochReg) begin
            outputFIFO.enq(FetchToDecode{
                pc: info.pc,
                ppc: info.ppc,
                instr: resp
            });
        end
    endrule

    // METHODS //
    method Action jumpTo(Bit#(32) addr);
        jumpFIFO.enq(addr);
    endmethod

    method ActionValue#(FetchToDecode) getInst;
        let val = outputFIFO.first;
        outputFIFO.deq;
        return val;
    endmethod

    method ActionValue#(CacheReq) sendReq();
        let req = reqFIFO.first;
        reqFIFO.deq;
        return req;
    endmethod

    method Action getResp(Word resp);
        respFIFO.enq(resp);
    endmethod
endmodule

module mkFetchSized(Fetch);
    Fetch fetch <- mkFetch;
    return fetch;
endmodule