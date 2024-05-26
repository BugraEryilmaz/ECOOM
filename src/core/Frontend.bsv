`include "Logging.bsv"
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
import KonataHelper::*;

interface Frontend#(numeric type nPhysicalRegs, numeric type nRobElements, numeric type nRSEntries);
    // IMEM Interface
    method ActionValue#(CacheReq) sendReq();
    method Action getResp(Word resp);

    // Push to backend
    method ActionValue#(RSEntry#(TLog#(nPhysicalRegs), TLog#(nRobElements))) getLSU(); 
    method ActionValue#(RSEntry#(TLog#(nPhysicalRegs), TLog#(nRobElements))) getALU(); 

    // ROB Interface
    method Action complete(PEResult#(TLog#(nPhysicalRegs), TLog#(nRobElements)) result);
    method ActionValue#(ROBResult#(TLog#(nPhysicalRegs))) drain();
    method Action graduate (Maybe#(Bit#(TLog#(nPhysicalRegs))) old_src);

    // Jump and rewind
    method Action jumpAndRewind(Bit#(32) addr, Vector#(32, Maybe#(Bit#(TLog#(nPhysicalRegs)))) oldRegRename, Bit#(nPhysicalRegs) oldFreeList);

    method Action setFile(File file);
    `ifdef debug
    method Action dumpState();
    `endif
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

    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
    Reg#(Bool) starting <- mkReg(True);

    // Communication FIFOs //
    FIFO#(FetchToDecode) f2i <- mkBypassFIFO;
    FIFO#(rsEntry) i2d <- mkFIFO;

    // RULES
    rule rlF2Q (!starting);
        let val <- fetch.getInst;
        f2i.enq(val);
    endrule

    rule rlQ2I (!starting);
        let val = f2i.first;
        f2i.deq;
        issue.put(val);
    endrule

    rule rlI2Q (!starting);
        let val <- issue.get;
        i2d.enq(val);
    endrule

    rule rlQ2D (!starting);
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
    method ActionValue#(rsEntry) getALU() if(!flushing); 
        let val <- dispatch.getALU();
        return val;
    endmethod

    method ActionValue#(rsEntry) getLSU() if(!flushing); 
        let val <- dispatch.getLSU();
        return val;
    endmethod

    // ROB Interface    
    method Action complete(PEResult#(TLog#(nPhysicalRegs), TLog#(nRobElements)) result) if(!flushing);
        issue.complete(result);
        if(result.rd matches tagged Valid .rd) begin
            dispatch.makeReady(WakeUpRegVal{
                rs: result.rd, 
                src: result.result
            });
        end
    endmethod
    
    method ActionValue#(ROBResult#(TLog#(nPhysicalRegs))) drain() if(!flushing);
        let val <- issue.drain;
        return val;
    endmethod

    method Action graduate (Maybe#(Bit#(TLog#(nPhysicalRegs))) old_src);
        issue.graduate(old_src);
    endmethod

    // Jump and rewind
    method Action jumpAndRewind(Bit#(32) addr, Vector#(32, Maybe#(Bit#(TLog#(nPhysicalRegs)))) oldRegRename, Bit#(nPhysicalRegs) oldFreeList);
        fetch.jumpTo(addr);
        issue.flush(oldRegRename, oldFreeList);
        dispatch.flush();
        flushing.send();
        f2i.clear;
        i2d.clear;
    endmethod

    method Action setFile(File file) if(starting);
        lfh <= file;
        starting <= False;
        fetch.setFile(file);
        issue.setFile(file);
        dispatch.setFile(file);
    endmethod

    `ifdef debug
    method Action dumpState();
        $display("Frontend");
        fetch.dumpState();
        issue.dumpState();
    endmethod
    `endif
endmodule

module mkFrontendSized(Frontend#(64, 64, 24));
    Frontend#(64, 64, 24) frontend <- mkFrontend;
    return frontend;
endmodule

