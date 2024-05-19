import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import MemTypes::*;
import PEUtil::*;
import Fetch::*;
import Issue::*;
import Dispatch::*;
import ReorderBuffer::*;
import ReservationStation::*;

interface Frontend#(numeric type nPhysicalRegs, numeric type nRobElements, numeric type nRSEntries);
    // IMEM Interface
    method ActionValue#(CacheReq) sendReq();
    method Action getResp(Word resp);

    // Push to backend
    method ActionValue#(RSEntry#(TLog#(nPhysicalRegs), TLog#(nRobElements))) get(); 

    // ROB Interface
    method Action complete(PEResult#(TLog#(nPhysicalRegs), TLog#(nRobElements)) result);
    method ActionValue#(ROBResult#(TLog#(nPhysicalRegs))) drain();
    method Action graduate (Maybe#(Bit#(TLog#(nPhysicalRegs))) old_src);

    // Jump and rewind
    method Action jumpAndRewind(Bit#(32) addr, Vector#(32, Maybe#(Bit#(TLog#(nPhysicalRegs)))) oldRegRename, Bit#(nPhysicalRegs) oldFreeList);
endinterface


module mkFrontend(Frontend#(nPhysicalRegs, nRobElements, nRSEntries))
    provisos (
        NumAlias#(TLog#(nPhysicalRegs), physicalRegSize),
        NumAlias#(TLog#(nRobElements), robTagSize),
        Alias#(RSEntry#(physicalRegSize, robTagSize), rsEntry)
    );

    // Internal Modules //
    Fetch fetch <- mkFetch;
    Issue#(nPhysicalRegs, nRobElements) issue <- mkIssue;
    Dispatch#(physicalRegSize, robTagSize, nRSEntries) dispatch <- mkDispatch;
    PulseWire flushing <- mkPulseWire;

    // Communication FIFOs //
    FIFO#(FetchToDecode) f2i <- mkFIFO;
    FIFO#(rsEntry) i2d <- mkFIFO;

    // RULES
    rule rlF2Q (!flushing);
        let val <- fetch.getInst;
        f2i.enq(val);
    endrule

    rule rlQ2I (!flushing);
        let val = f2i.first;
        f2i.deq;
        issue.put(val);
    endrule

    rule rlI2Q (!flushing);
        let val <- issue.get;
        i2d.enq(val);
    endrule

    rule rlQ2D (!flushing);
        let val = i2d.first;
        i2d.deq;
        dispatch.put(val);
    endrule

    // METHODS //
    // IMEM Interface
    method ActionValue#(CacheReq) sendReq();
        let val <- fetch.sendReq();
        return val;
    endmethod

    method Action getResp(Word resp);
        fetch.getResp(resp);
    endmethod

    // Push to backend
    method ActionValue#(rsEntry) get() if(!flushing); 
        let val <- dispatch.get();
        return val;
    endmethod

    // ROB Interface    
    method Action complete(PEResult#(TLog#(nPhysicalRegs), TLog#(nRobElements)) result) if(!flushing);
        issue.complete(result);
    endmethod
    
    method ActionValue#(ROBResult#(TLog#(nPhysicalRegs))) drain() if(!flushing);
        let val <- issue.drain;
        return val;
    endmethod

    method Action graduate (Maybe#(Bit#(TLog#(nPhysicalRegs))) old_src) if(!flushing);
        issue.graduate(old_src);
    endmethod

    // Jump and rewind
    method Action jumpAndRewind(Bit#(32) addr, Vector#(32, Maybe#(Bit#(TLog#(nPhysicalRegs)))) oldRegRename, Bit#(nPhysicalRegs) oldFreeList);
        fetch.jumpTo(addr);
        issue.flush(oldRegRename, oldFreeList);
        dispatch.flush();
        flushing.send();
    endmethod
endmodule

module mkFrontendSized(Frontend#(64, 64, 24));
    Frontend#(64, 64, 24) frontend <- mkFrontend;
    return frontend;
endmodule
