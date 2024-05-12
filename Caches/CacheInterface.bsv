// SINGLE CORE CACHE INTERFACE WITH NO PPP
import MainMem::*;
import MemTypes::*;
import Cache32::*;
import Cache32d::*;
import Cache512::*;
import Vector::*;
import FIFOF::*;
import SpecialFIFOs::*;


interface CacheInterface;
    method Action sendReqData(CacheReq req);
    method ActionValue#(Word) getRespData();
    method Action sendReqInstr(CacheReq req);
    method ActionValue#(Word) getRespInstr();
endinterface

typedef enum {
    INSTR,
    DATA
} CacheInterfaceRR deriving (Eq, FShow, Bits);

module mkCacheInterface(CacheInterface);
    let verbose = False;
    MainMem mainMem <- mkMainMem(); 
    Cache512 cacheL2 <- mkCache;
    Cache32 cacheI <- mkCache32;
    Cache32d cacheD <- mkCache32d;

    // You need to add rules and/or state elements.

    FIFOF#(MainMemReq) iToL2 <- mkBypassFIFOF;
    FIFOF#(MainMemReq) dToL2 <- mkBypassFIFOF;
    Reg#(CacheInterfaceRR) toL2RoundRobin <- mkReg(INSTR);

    Reg#(Bool) outstandingMiss <- mkReg(False);

    rule getFromMem;
        let resp <- mainMem.get();
        if (verbose) $display("CacheInterface: Getting from Mem");
        cacheL2.putFromMem(resp);
    endrule
    
    rule sendToMem;
        let req <- cacheL2.getToMem();
        if (verbose) $display("CacheInterface: Sending to Mem");
        mainMem.put(req);
    endrule
    
    rule getFromL2;
        let resp <- cacheL2.getToProc();
        if (verbose) $display("CacheInterface: Getting from L2");
        if (toL2RoundRobin == INSTR) begin
            cacheD.putFromMem(resp);
        end else begin
            cacheI.putFromMem(resp);
        end
        outstandingMiss <= False;
    endrule
    
    rule sendToL2 if (outstandingMiss == False);
        let req;
        if (toL2RoundRobin == INSTR && iToL2.notEmpty) begin
            req = iToL2.first;
            iToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1i to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= DATA;
            outstandingMiss <= True;
        end else if (toL2RoundRobin == DATA && dToL2.notEmpty) begin
            req = dToL2.first;
            dToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1d to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= INSTR;
            outstandingMiss <= True;
        end else if (toL2RoundRobin == INSTR && dToL2.notEmpty) begin
            req = dToL2.first;
            dToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1d to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= INSTR;
            outstandingMiss <= True;
        end else if (toL2RoundRobin == DATA && iToL2.notEmpty) begin
            req = iToL2.first;
            iToL2.deq;
            if (verbose) $display("CacheInterface: Sending from L1i to L2");
            cacheL2.putFromProc(req);
            toL2RoundRobin <= DATA;
            outstandingMiss <= True;
        end
    endrule 

    rule toL2Data;
        let req <- cacheD.getToMem();
        dToL2.enq(req);
    endrule

    rule toL2Instr;
        let req <- cacheI.getToMem();
        iToL2.enq(req);
    endrule

    method Action sendReqData(CacheReq req);
        cacheD.putFromProc(req);
    endmethod

    method ActionValue#(Word) getRespData() ;
        let resp <- cacheD.getToProc();
        return resp;
    endmethod


    method Action sendReqInstr(CacheReq req);
        cacheI.putFromProc(req);
    endmethod

    method ActionValue#(Word) getRespInstr();
        let resp <- cacheI.getToProc();
        return resp;
    endmethod
endmodule
