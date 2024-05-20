import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import Ehr::*;
import RVUtil::*;
import PEUtil::*;
import ReservationStation::*;

module mkReservationStationOrdered(RS#(nEntries, physicalRegSize, robTagSize))
    provisos(
        Alias#(RSEntry#(physicalRegSize, robTagSize), element),
        NumAlias#(entrySize, TLog#(nEntries))
    );
    Vector#(nEntries, Ehr#(3, Maybe#(element))) entries <- replicateM(mkEhr(Invalid));
    FIFO#(element) putQueue <- mkBypassFIFO;
    FIFO#(Bit#(physicalRegSize)) readyQueue <- mkBypassFIFO;
    FIFO#(RSEntry#(physicalRegSize, robTagSize)) issueQueue <- mkFIFO;
    PulseWire flushing <- mkPulseWire;
    Reg#(Bit#(entrySize)) regHead <- mkReg(0);
    Reg#(Bit#(entrySize)) regTail <- mkReg(0);

    // HELPERS //

    // RULES //
    rule wakeUpReg (!flushing);
        let rs = readyQueue.first;
        readyQueue.deq;
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            if(isValid(entries[i][0])) begin
                let val = fromMaybe(?, entries[i][0]);
                if(val.rs1 matches tagged Valid .rs1)
                    val.ready_rs1 = val.ready_rs1 || (rs1 == rs);

                if(val.rs2 matches tagged Valid .rs2)
                    val.ready_rs2 = val.ready_rs2 || (rs2 == rs);
                entries[i][0] <= tagged Valid(val);
            end
        end
    endrule

    rule putEntry (!flushing);
        Bit#(entrySize) idx = regHead;
        if(!isValid(entries[idx][1])) begin
            entries[idx][1] <= tagged Valid(putQueue.first);
            putQueue.deq;
            regHead <= regHead + 1;
        end
    endrule

    rule prepareIssue (!flushing);
        Bit#(entrySize) idx = regTail;
        if(isValid(entries[idx][2])) begin
            issueQueue.enq(fromMaybe(?, entries[idx][2]));
            entries[idx][2] <= tagged Invalid;
            regTail <= regTail + 1;
        end
    endrule

    rule flushEntries (flushing);
        putQueue.clear;
        readyQueue.clear;
        issueQueue.clear;
        regHead[0] <= 0;
        regTail[0] <= 0;

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

module mkReservationStationOrderedSized(RS#(32, 5, 6));
    RS#(32, 5, 6) reservation <- mkReservationStationOrdered;
    return reservation;
endmodule