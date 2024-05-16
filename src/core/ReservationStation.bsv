import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import Ehr::*;
import RVUtil::*;

typedef struct {
    Bit#(robTagSize) tag;
    Bit#(32) pc;
    DecodedInst dInst;
    Bool ready_rs1;
    Bool ready_rs2;
    Maybe#(Bit#(physicalRegSize)) rs1;
    Maybe#(Bit#(physicalRegSize)) rs2;
} RSEntry#(numeric type physicalRegSize, numeric type robTagSize) deriving (Bits, FShow);

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
    RWire#(Vector#(nEntries, Maybe#(element))) entriesWire <- mkRWire;
    FIFO#(element) putQueue <- mkBypassFIFO;
    FIFO#(Bit#(physicalRegSize)) readyQueue <- mkBypassFIFO;
    FIFO#(RSEntry#(physicalRegSize, robTagSize)) issueQueue <- mkBypassFIFO;
    PulseWire flushing <- mkPulseWire;

    // HELPERS //
    function Bool isElemFree(Maybe#(element) elem);
        return !isValid(elem);
    endfunction

    function Bool isElemReady(Maybe#(element) elem);
        let valElem = fromMaybe(?, elem);
        return isValid(elem) && valElem.ready_rs1 && valElem.ready_rs2;
    endfunction

    // RULES //
    rule updateEntries (!flushing);
        Vector#(nEntries, Maybe#(element)) entriesSignal = ?;
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            entriesSignal[i] = entries[i][0];
        end
        entriesWire.wset(entriesSignal);
    endrule

    rule wakeUpReg (!flushing && isValid(entriesWire.wget));
        let rs = readyQueue.first;
        readyQueue.deq;
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            let x = fromMaybe(?, entriesWire.wget());
            if(isValid(x[i])) begin
                let val = fromMaybe(?, x[i]);
                if(val.rs1 matches tagged Valid .rs1)
                    val.ready_rs1 = val.ready_rs1 || (rs1 == rs);

                if(val.rs2 matches tagged Valid .rs2)
                    val.ready_rs2 = val.ready_rs2 || (rs2 == rs);
                entries[i][0] <= tagged Valid(val);
            end
        end
    endrule

    rule putEntry (!flushing && isValid(entriesWire.wget));
        let ptr = findIndex(isElemFree, fromMaybe(?, entriesWire.wget));
        if(isValid(ptr)) begin
            let idx = fromMaybe(?, ptr);
            entries[idx][1] <= tagged Valid(putQueue.first);
            putQueue.deq;
        end
    endrule

    rule prepareIssue (!flushing && isValid(entriesWire.wget));
        let ptr = findIndex(isElemReady, fromMaybe(?, entriesWire.wget));
        if(isValid(ptr)) begin
            let idx = fromMaybe(?, ptr);
            issueQueue.enq(fromMaybe(?, fromMaybe(?, entriesWire.wget)[idx]));
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
    return reservation;
endmodule