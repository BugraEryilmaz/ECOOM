// SINGLE CORE ASSOIATED CACHE -- stores words

import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector::*;
import CacheUnit::*;
import GenericCache::*;

// The types live in MemTypes.bsv

// Notice the asymmetry in this interface, as mentioned in lecture.
// The processor thinks in 32 bits, but the other side thinks in 512 bits.
interface Cache32;
    method Action putFromProc(CacheReq e);
    method ActionValue#(Word) getToProc();
    method ActionValue#(MainMemReq) getToMem();
    method Action putFromMem(MainMemResp e);
endinterface

(* synthesize *)
module mkCache32(Cache32);
    // addrcpuBits, datacpuBits, addrmemBits, datamemBits, numWords, numLogLines, numBanks, numWays, idx
    GenericCache#(30, 32, 26, 512, 16, 6, 1, 2, 1) cache <- mkGenericCache();

    method Action putFromProc(CacheReq e);
        GenericCacheReq#(30, 32) req = GenericCacheReq{addr: e.addr[31:2], data: e.data, word_byte: e.word_byte};
        cache.putFromProc(req);
    endmethod
        
    method ActionValue#(Word) getToProc();
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