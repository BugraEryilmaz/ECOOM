`include "Logging.bsv"
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Ehr::*;
import BTB::*;
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
    method Action jumpTo(Bit#(32) pc, Bit#(32) target, Bool taken);
    method ActionValue#(FetchToDecode) getInst;
    method ActionValue#(CacheReq) sendReq();
    method Action getResp(Word resp);
    method Action setFile(File file);
    `ifdef debug
    method Action dumpState();
    `endif
endinterface

module mkFetch(Fetch);
    // Internal Structures
    BTB#(32) btb <- mkBTB;

    // Communication FIFOs //
    FIFO#(FetchToDecode) outputFIFO <- mkBypassFIFO;
    FIFO#(CacheReq) reqFIFO <- mkBypassFIFO;
    FIFO#(Word) respFIFO <- mkBypassFIFO;
    FIFO#(IMemBussiness) inflightFIFO <- mkSizedFIFO(4);

    Ehr#(2, Bit#(32)) pcReg <- mkEhr(0);
    Ehr#(2, Bool) epochReg <- mkEhr(False);

    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
    Reg#(Bool) starting <- mkReg(True);

    // RULES //
    rule rlAddressGeneration (!starting);
        let iid <- fetch1Konata(lfh, fresh_id, 0);

        reqFIFO.enq(CacheReq{
            word_byte: 0,
            addr: pcReg[0],
            data: ?
        });
        
        let ppc = btb.predict(pcReg[0]); // pcReg[0] + 4;
        inflightFIFO.enq(IMemBussiness{
            pc: pcReg[0],
            ppc: ppc,
            epoch: epochReg[0],
            k_id: iid
        });

        labelKonataLeft(lfh, iid, $format("(e%d) 0x%x: ", epochReg[0], pcReg[0]));
        `LOG(("[IF] Fetching 0x%x", pcReg[0]));
        pcReg[0] <= ppc;
    endrule

    rule rlGetResp (!starting);
        let resp = respFIFO.first;
        respFIFO.deq;
        let info = inflightFIFO.first;
        inflightFIFO.deq;

        `LOG(("[IF] Received ", fshow(resp)));

        if(info.epoch == epochReg[0]) begin
            outputFIFO.enq(FetchToDecode{
                pc: info.pc,
                ppc: info.ppc,
                inst: resp,
                k_id: info.k_id
            });
        end
    endrule

    // METHODS //
    method Action jumpTo(Bit#(32) pc, Bit#(32) target, Bool taken);
        pcReg[1] <= target;
        epochReg[1] <= !epochReg[1];
        outputFIFO.clear();
        btb.update(pc, taken ? tagged Valid target : tagged Invalid);
        `LOG(("[IF] Jump to ", fshow(target)));
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

    `ifdef debug
    method Action dumpState();
        $display("Fetch State:");
        $display("  PC: 0x%x", pcReg[0]);
        $display("  Epoch: %d", epochReg[0]);
    endmethod
    `endif
endmodule

module mkFetchSized(Fetch);
    Fetch fetch <- mkFetch;
    return fetch;
endmodule