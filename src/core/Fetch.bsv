`include "Logging.bsv"
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import KonataHelper::*;

typedef struct {
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(32) inst;
    KonataId k_id;
} FetchToDecode deriving(Bits, FShow);

typedef struct {
    Bit#(32) pc;
    Bit#(32) ppc;
    Bool epoch;
    KonataId k_id;
} IMemBussiness deriving(Bits, FShow);

interface Fetch;
    method Action jumpTo(Bit#(32) addr);
    method ActionValue#(FetchToDecode) getInst;
    method ActionValue#(CacheReq) sendReq();
    method Action getResp(Word resp);
    method Action setFile(File file);
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

    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
    Reg#(Bool) starting <- mkReg(True);

    // RULES //
    rule rlJump (!starting && jumpFIFO.notEmpty);
        let addr = jumpFIFO.first;
        jumpFIFO.deq;
        pcReg <= addr;
        epochReg <= !epochReg;
        `LOG(("[IF] Jump to ", fshow(addr)));
    endrule

    rule rlAddressGeneration (!starting && !jumpFIFO.notEmpty);
        let iid <- fetch1Konata(lfh, fresh_id, 0);

        reqFIFO.enq(CacheReq{
            word_byte: 0,
            addr: pcReg,
            data: ?
        });
        
        let ppc = pcReg + 4;
        inflightFIFO.enq(IMemBussiness{
            pc: pcReg,
            ppc: ppc,
            epoch: epochReg,
            k_id: iid
        });

        labelKonataLeft(lfh, iid, $format("(e%d) 0x%x: ", epochReg, pcReg));
        `LOG(("[IF] Fetching 0x%x", pcReg));
        pcReg <= ppc;
    endrule

    rule rlGetResp (!starting && !jumpFIFO.notEmpty);
        let resp = respFIFO.first;
        respFIFO.deq;
        let info = inflightFIFO.first;
        inflightFIFO.deq;

        `LOG(("[IF] Received ", fshow(resp)));

        if(info.epoch == epochReg) begin
            outputFIFO.enq(FetchToDecode{
                pc: info.pc,
                ppc: info.ppc,
                inst: resp,
                k_id: info.k_id
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

    method Action setFile(File file) if(starting);
        lfh <= file;
        starting <= False;
    endmethod
endmodule

module mkFetchSized(Fetch);
    Fetch fetch <- mkFetch;
    return fetch;
endmodule