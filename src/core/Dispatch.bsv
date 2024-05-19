import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import RVUtil::*;
import PEUtil::*;
import Fetch::*;
import ReservationStation::*;
import ReservationStationOrdered::*;
import ReorderBuffer::*;
import RegRename::*;
import RDYB::*;

interface Dispatch#(numeric type physicalRegSize, numeric type robTagSize, numeric type nRSEntries);
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry);
    method ActionValue#(RSEntry#(physicalRegSize, robTagSize)) get(); 
    method Action makeReady(Bit#(physicalRegSize) rs);
    method Action flush();
endinterface

module mkDispatch(Dispatch#(physicalRegSize, robTagSize, nRSEntries))
    provisos (
        Alias#(RSEntry#(physicalRegSize, robTagSize), rsEntry),
        Alias#(PEInput#(physicalRegSize, robTagSize), peInput)
    );
    
    // Internal Modules //
    PulseWire flushing <- mkPulseWire;
    RS#(nRSEntries, physicalRegSize, robTagSize) rsInteger <- mkReservationStation;
    RS#(nRSEntries, physicalRegSize, robTagSize) rsLSU <- mkReservationStationOrdered;
    RDYBIfc#(physicalRegSize) rdby <- mkRDYB;

    // Communication FIFOs //
    FIFO#(rsEntry) putFIFO <- mkBypassFIFO;
    FIFO#(rsEntry) getFIFO <- mkBypassFIFO;
    FIFOF#(rsEntry) aluIssue <- mkBypassFIFOF;
    FIFOF#(rsEntry) lsuIssue <- mkBypassFIFOF;

    // RULES //
    rule rlEnqueue (!flushing);
        let entry = putFIFO.first;
        putFIFO.deq;

        let ready_rs1 <- rdby.read(fromMaybe(?, entry.rs1));
        let ready_rs2 <- rdby.read(fromMaybe(?, entry.rs2));
        entry.ready_rs1 = isValid(entry.rs1) ? (ready_rs1 == 1 ? True : False) : True;
        entry.ready_rs2 = isValid(entry.rs2) ? (ready_rs2 == 1 ? True : False) : True;
        if(entry.rd matches tagged Valid .rd) begin
            rdby.rst(rd);
        end

        if(entry.pe == LSU) rsLSU.put(entry);
        else rsInteger.put(entry);
    endrule

    rule rlIntDispatch (!flushing && aluIssue.notFull);
        let val <- rsInteger.issue;
        aluIssue.enq(val);
    endrule

    rule rlLsuDispatch (!flushing && lsuIssue.notFull);
        let val <- rsLSU.issue;
        lsuIssue.enq(val);
    endrule

    rule rlDispatch (!flushing && (aluIssue.notEmpty || lsuIssue.notEmpty));
        let val = ?;
        if(lsuIssue.notEmpty) begin
            val = lsuIssue.first;
            lsuIssue.deq;
        end else begin
            val = aluIssue.first;
            aluIssue.deq;
        end

        getFIFO.enq(val);
    endrule

    rule rlFlush (flushing);
        rsInteger.flush();
        rsLSU.flush();
        rdby.flush();
    endrule

    // METHODS //
    method Action put(rsEntry entry) if(!flushing);
        putFIFO.enq(entry);
    endmethod

    method ActionValue#(rsEntry) get() if(!flushing);
        let val = getFIFO.first;
        getFIFO.deq;
        return val;
    endmethod

    method Action makeReady(Bit#(physicalRegSize) rs) if(!flushing);
        rsInteger.makeReady(rs);
        rsLSU.makeReady(rs);
        rdby.set(rs);
    endmethod

    method Action flush() = flushing.send();
endmodule

module mkDispatchSized(Dispatch#(6, 6, 16));
    Dispatch#(6, 6, 16) dispatch <- mkDispatch;
    return dispatch;
endmodule