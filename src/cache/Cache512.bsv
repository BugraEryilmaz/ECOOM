import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector::*;
import CacheUnit::*;
import GenericCache::*;

// Note that this interface *is* symmetric. 
interface Cache512;
    method Action putFromProc(MainMemReq e);
    method ActionValue#(MainMemResp) getToProc();
    method ActionValue#(MainMemReq) getToMem();
    method Action putFromMem(MainMemResp e);
endinterface

(* synthesize *)
module mkCache(Cache512);
    // addrcpuBits, datacpuBits, addrmemBits, datamemBits, numWords, numLogLines, numBanks, numWays, idx
    GenericCache#(26, 512, 26, 512, 1, 6, 1, 4, 3) cache <- mkGenericCache();

    method Action putFromProc(MainMemReq e);
        GenericCacheReq#(26, 512) req = GenericCacheReq{addr: e.addr, data: e.data, word_byte: e.write==0 ? 0 : ~0};
        cache.putFromProc(req);
    endmethod

    method ActionValue#(MainMemResp) getToProc();
        let resp <- cache.getToProc();
        return resp;
    endmethod

    method ActionValue#(MainMemReq) getToMem();
        let req <- cache.getToMem();
        return MainMemReq{write: req.word_byte==0 ? 0 : 1, addr: req.addr, data: req.data};
    endmethod

    method Action putFromMem(MainMemResp e);
        cache.putFromMem(e);
    endmethod
endmodule
