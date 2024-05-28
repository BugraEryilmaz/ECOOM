`include "Logging.bsv"
import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import Ehr::*;
import RVUtil::*;
import PEUtil::*;
import ReservationStation::*;
import KonataHelper::*;

module mkReservationStationOrdered(RS#(nEntries, physicalRegSize, robTagSize))
    provisos(
        Alias#(RSEntry#(physicalRegSize, robTagSize), element),
        NumAlias#(entrySize, TLog#(nEntries))
    );
    Vector#(nEntries, Ehr#(3, Maybe#(element))) entries <- replicateM(mkEhr(Invalid));
    RWire#(Vector#(nEntries, Maybe#(element))) entriesWire <- mkRWire;
    FIFO#(element) putQueue <- mkBypassFIFO;
    FIFO#(WakeUpRegVal#(physicalRegSize)) readyQueue <- mkBypassFIFO;
    FIFO#(RSEntry#(physicalRegSize, robTagSize)) issueQueue <- mkFIFO;
    PulseWire flushing <- mkPulseWire;
    Reg#(Bit#(entrySize)) regHead <- mkReg(0);
    Reg#(Bit#(entrySize)) regTail <- mkReg(0);

    Reg#(File) lfh <- mkReg(InvalidFile);
    Reg#(Bool) starting <- mkReg(True);

    // HELPERS //

    // RULES //
    rule updateEntries (!flushing && !starting);
        Vector#(nEntries, Maybe#(element)) entriesSignal = ?;
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            entriesSignal[i] = entries[i][0];
        end
        entriesWire.wset(entriesSignal);
    endrule

    rule wakeUpReg (!flushing && isValid(entriesWire.wget) && !starting);
        let wake = readyQueue.first;
        readyQueue.deq;
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            let x = fromMaybe(?, entriesWire.wget());
            if(isValid(x[i])) begin
                let val = fromMaybe(?, x[i]);
                if(val.rs1 matches tagged Valid .rs1 &&& wake.rs matches tagged Valid .rs &&& rs1 == rs) begin
                    val.ready_rs1 = True;
                    val.src1 = tagged Valid wake.src;
                end

                if(val.rs2 matches tagged Valid .rs2 &&& wake.rs matches tagged Valid .rs &&& rs2 == rs) begin
                    val.ready_rs2 = True;
                    val.src2 = tagged Valid wake.src;
                end
                
                entries[i][0] <= tagged Valid(val);
            end
        end
    endrule

    rule putEntry (!flushing && isValid(entriesWire.wget) && !starting);
        Bit#(entrySize) idx = regHead;
        if(!isValid(fromMaybe(?, entriesWire.wget)[idx])) begin
            entries[idx][1] <= tagged Valid(putQueue.first);
            putQueue.deq;
            regHead <= regHead + 1;
        end
    endrule

    rule prepareIssue (!flushing && isValid(entriesWire.wget) && !starting);
        Bit#(entrySize) idx = regTail;
        let entry = fromMaybe(?, entriesWire.wget)[idx];
        if(entry matches tagged Valid .e &&& (e.ready_rs1 && e.ready_rs2)) begin
            let issued = fromMaybe(?, entry);
            issueQueue.enq(issued);
            entries[idx][2] <= tagged Invalid;
            stageKonata(lfh, issued.k_id, "RS");
            regTail <= regTail + 1;
        end
    endrule

    rule flushEntries (flushing && !starting);
        putQueue.clear;
        readyQueue.clear;
        issueQueue.clear;
        regHead <= 0;
        regTail <= 0;

        for(Integer i = 0; i < valueOf(nEntries); i = i + 1)
            entries[i][0] <= tagged Invalid;
    endrule

    // INTERFACE //
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry) if (!flushing && !starting);
        putQueue.enq(entry);
    endmethod

    method Action makeReady(WakeUpRegVal#(physicalRegSize) wake) if (!flushing && !starting);
        readyQueue.enq(wake);
    endmethod

    method ActionValue#(RSEntry#(physicalRegSize, robTagSize)) issue() if (!flushing && !starting);
        let elem = issueQueue.first;
        issueQueue.deq;
        return elem;
    endmethod

    method Action flush() if (!starting);
        flushing.send();
    endmethod

    method Action setFile(File file);
        lfh <= file;
        starting <= False;
    endmethod

    `ifdef debug
    method Action dumpState();
        $display("RS Ordered:");
        $display("  Head: %0d", regHead);
        $display("  Tail: %0d", regTail);
        for (Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            $display("  Entry %0d: %s", i, fshow(entries[i][0]));
        end
    endmethod
    `endif
endmodule

module mkReservationStationOrderedSized(RS#(32, 5, 6));
    RS#(32, 5, 6) reservation <- mkReservationStationOrdered;
    return reservation;
endmodule