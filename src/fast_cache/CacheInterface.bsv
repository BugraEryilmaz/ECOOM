// SINGLE CORE CACHE INTERFACE WITH NO PPP
import MainMem::*;
import MemTypes::*;
import Cache32::*;
import Cache512::*;
import FIFO::*;

typedef enum {I, D} L2ReqSource deriving (Eq, Bits, FShow);

interface CacheInterface;
    method Action sendReqData(CacheReq req);
    method ActionValue#(Word) getRespData();
    method Action sendReqInstr(CacheReq req);
    method ActionValue#(Word) getRespInstr();
endinterface


module mkCacheInterface(CacheInterface);
    let verbose = True;
    MainMem mainMem <- mkMainMem(); 
    Cache512 cacheL2 <- mkCache;
    Cache32 cacheI <- mkCache32;
    Cache32 cacheD <- mkCache32;
    FIFO#(L2ReqSource) l2ReqFifo <- mkFIFO;

    rule connectCacheL1IL2;
        let lineReq <- cacheI.getToMem();
        l2ReqFifo.enq(I);
        cacheL2.putFromProc(lineReq);
    endrule

    rule connectCacheL1DL2;
        let lineReq <- cacheD.getToMem();
        l2ReqFifo.enq(D);
        cacheL2.putFromProc(lineReq);
    endrule

    rule connectL2L1DICache;
        let resp <- cacheL2.getToProc();
        l2ReqFifo.deq(); let req = l2ReqFifo.first();
        if (req == D) cacheD.putFromMem(resp);
        else cacheI.putFromMem(resp);
    endrule

    rule connectCacheDram;
        let lineReq <- cacheL2.getToMem();
        mainMem.put(lineReq);
    endrule

    rule connectDramCache;
        let resp <- mainMem.get;
        cacheL2.putFromMem(resp);
    endrule

    method Action sendReqData(CacheReq req);
        cacheD.putFromProc(req);
    endmethod

    method ActionValue#(Word) getRespData();
        let word <- cacheD.getToProc();
        return word;
    endmethod

    method Action sendReqInstr(CacheReq req);
        cacheI.putFromProc(req);
    endmethod

    method ActionValue#(Word) getRespInstr();
        let word <- cacheI.getToProc();
        return word;
    endmethod
endmodule
