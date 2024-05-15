import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import Ehr::*;
import RVUtil::*;

typedef struct {
    Bit#(robTagSize) tag;
    Bit#(32) pc;
    DecodedInst inst;
    Bool ready_rs1;
    Bool ready_rs2;
    Bit#(physicalRegSize) rs1;
    Bit#(physicalRegSize) rs2;
    Maybe#(Bit#(physicalRegSize)) rd;
} RSEntry#(numeric type physicalRegSize, numeric type robTagSize) deriving (Bits, Eq, FShow);

interface RS#(numeric type nEntries, numeric type physicalRegSize, numeric type robTagSize);
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry);
    method Action makeReady(Bit#(physicalRegSize) rs);
    method ActionValue#(RSEntry#(physicalRegSize, robTagSize)) issue();
    method Action flush();
endinterface

module mkReservationStation(RS#(nEntries, physicalRegSize, robTagSize))
    provisos(
        Alias#(RSEntry#(physicalRegSize, robTagSize), element)
    );
    Vector#(nEntries, Ehr#(3, Maybe#(element))) entries <- replicateM(mkEhr(Invalid));
    FIFO#(element) putQueue <- mkBypassFIFO;
    FIFO#(Bit#(physicalRegSize)) readyQueue <- mkBypassFIFO;
    FIFO#(RSEntry#(physicalRegSize, robTagSize)) issueQueue <- mkBypassFIFO;
    PulseWire flushing <- mkPulseWire;

    // HELPERS //
    function Bool isElemFree(Ehr#(3, Maybe#(element)) elem);
        return !isValid(elem[1]);
    endfunction

    function Bool isElemReady(Ehr#(3, Maybe#(element)) elem);
        let valElem = fromMaybe(?, elem[2]);
        return isValid(elem[2]) && valElem.ready_rs1 && valElem.ready_rs2;
    endfunction

    // RULES //
    rule wakeUpReg (!flushing);
        let rs = readyQueue.first;
        readyQueue.deq;
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            if(isValid(entries[i][0])) begin
                let val = fromMaybe(?, entries[i][0]);
                val.ready_rs1 = val.ready_rs1 || (val.rs1 == rs);
                val.ready_rs2 = val.ready_rs2 || (val.rs2 == rs);
                entries[i][0] <= tagged Valid(val);
            end
        end
    endrule

    rule putEntry (!flushing);
        let ptr = findIndex(isElemFree, entries);
        if(isValid(ptr)) begin
            let idx = fromMaybe(?, ptr);
            entries[idx][1] <= tagged Valid(putQueue.first);
            putQueue.deq;
        end
    endrule

    rule prepareIssue (!flushing);
        let ptr = findIndex(isElemReady, entries);
        if(isValid(ptr)) begin
            let idx = fromMaybe(?, ptr);
            issueQueue.enq(fromMaybe(?, entries[idx][2]));
            entries[idx][2] <= tagged Invalid;
        end
    endrule

    rule flushEntries (flushing);
        putQueue.clear;
        readyQueue.clear;
        issueQueue.clear;

        for(Integer i = 0; i < valueOf(nEntries); i = i + 1)
            entries[i][0] <= tagged Invalid;
    endrule

    // INTERFACE //
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry) if (!flushing);
        putQueue.enq(entry);
    endmethod

    method Action makeReady(Bit#(physicalRegSize) rs) if (!flushing);
        readyQueue.enq(rs);
    endmethod

    method ActionValue#(RSEntry#(physicalRegSize, robTagSize)) issue() if (!flushing);
        let elem = issueQueue.first;
        issueQueue.deq;
        return elem;
    endmethod

    method Action flush();
        flushing.send();
    endmethod
endmodule

module mkReservationStationSized(RS#(32, 5, 6));
    RS#(32, 5, 6) reservation <- mkReservationStation;

    method Action put(RSEntry#(5, 6) entry);
        reservation.put(entry);
    endmethod

    method Action makeReady(Bit#(5) rs);
        reservation.makeReady(rs);
    endmethod

    method ActionValue#(RSEntry#(5, 6)) issue();
        let val <- reservation.issue();
        return val;
    endmethod

    method Action flush();
        reservation.flush();
    endmethod
endmodule