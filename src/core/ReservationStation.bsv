import Vector::*;
import FIFO::*;
import SpecialFIFO::*;
import Ehr::*;

typedef struct {
    Bit#(robTagSize) tag;
    Bit#(32) pc;
    DecodedInst inst;
    Bool ready_rs1;
    Bool ready_rs2;
    Bit#(physicalRegSize) rs1;
    Bit#(physicalRegSize) rs2;
    Maybe#(Bit#(physicalRegSize)) rd;
} RSEntry#(numeric type physicalRegSize, numeric type robTagSize) deriving (Bits, Eq, Show)

interface RS#(numeric type nEntries, numeric type physicalRegSize, numeric type robTagSize);
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry);
    method Action makeReady(Bit#(physicalRegSize) rs);
    method ActionValue#(RSEntry#(physicalRegSize, robTagSize)) issue();
endinterface

module mkReservationStation(RS#(nEntries, physicalRegSize, robTagSize))
    provisos(
        Alias#(RSEntry#(physicalRegSize, robTagSize), element)
    );
    Vector#(nEntries, Ehr#(3, Maybe#(element))) entries <- replicateM(mkEhr(Invalid));
    FIFO#(element) putQueue <- mkBypassFIFO;
    FIFO#(Bit#(physicalRegSize)) readyQueue <- mkBypassFIFO;
    FIFO#(RSEntry#(physicalRegSize, robTagSize)) issueQueue <- mkBypassFIFO;

    // HELPERS //
    function isElemFree(Ehr#(3, Maybe#(element) elem);
        return !isValid(elem[1]);
    endfunction

    function isElemReady(Ehr#(3, Maybe#(element) elem);
        let valElem = fromMaybe(?, elem[2]);
        return isValid(elem[2]) && valElem.ready_rs1 && valElem.ready_rs2;
    endfunction

    // RULES //
    rule wakeUpReg;
        let rs = readyQueue.first;
        readyQueue.deq;
        for(Integer i = 0; i < nEntries; i = i + 1) begin
            if(entries[i][0].isValid) begin
                let val = fromMaybe(?, entries[i][0]);
                val.ready_rs1 = val.ready_rs1 || (val.rs1 == rs);
                val.ready_rs2 = val.ready_rs2 || (val.rs2 == rs);
                entries[i][0] = val;
            end
        end
    endrule

    rule putEntry;
        let ptr = findIndex(isElemFree, entries);
        entries[ptr][1] <= tagged Valid(putQueue.first);
        putQueue.deq;
    endrule

    rule prepareIssue;
        let ptr = findIndex(isElemReady, entries);
        issueQueue.enq(entries[ptr][2]);
        entries[ptr][2] <= tagged Invalid;
    endrule

    // INTERFACE //
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry);
        putQueue.enq(entry);
    endmethod

    method Action makeReady(Bit#(physicalRegSize) rs);
        readyQueue.enq(rs);
    endmethod

    method ActionValue#(RSEntry#(physicalRegSize, robTagSize)) issue();
        let elem = issueQueue.first;
        issueQueue.deq;
        return elem;
    endmethod
endmodule
