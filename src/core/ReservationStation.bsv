`include "Logging.bsv"
import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import Ehr::*;
import RVUtil::*;
import PEUtil::*;
import KonataHelper::*;

typedef struct {
    PEType pe;
    Bit#(robTagSize) tag;
    Bit#(32) pc;
    DecodedInst dInst;
    Bool ready_rs1;
    Bool ready_rs2;
    Maybe#(Bit#(physicalRegSize)) rs1;
    Maybe#(Bit#(physicalRegSize)) rs2;
    Maybe#(Bit#(32)) src1;
    Maybe#(Bit#(32)) src2;
    Maybe#(Bit#(physicalRegSize)) rd;
    KonataId k_id;
} RSEntry#(numeric type physicalRegSize, numeric type robTagSize) deriving (Bits, FShow);

typedef struct {
    Maybe#(Bit#(physicalRegSize)) rs;
    Bit#(32) src;
} WakeUpRegVal#(numeric type physicalRegSize) deriving (Bits, FShow);

interface RS#(numeric type nEntries, numeric type physicalRegSize, numeric type robTagSize);
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry);
    method Action makeReady(WakeUpRegVal#(physicalRegSize) wake);
    method ActionValue#(RSEntry#(physicalRegSize, robTagSize)) issue();
    method Action flush();
    method Action setFile(File file);

    `ifdef debug
    method Action dumpState();
    `endif
endinterface

module mkReservationStation(RS#(nEntries, physicalRegSize, robTagSize))
    provisos(
        Alias#(RSEntry#(physicalRegSize, robTagSize), element)
    );
    Vector#(nEntries, Ehr#(3, Maybe#(element))) entries <- replicateM(mkEhr(Invalid));
    RWire#(Vector#(nEntries, Maybe#(element))) entriesWire <- mkRWire;
    FIFO#(element) putQueue <- mkBypassFIFO;
    FIFO#(WakeUpRegVal#(physicalRegSize)) readyQueue <- mkBypassFIFO;
    FIFO#(RSEntry#(physicalRegSize, robTagSize)) issueQueue <- mkFIFO;
    PulseWire flushing <- mkPulseWire;

    Reg#(File) lfh <- mkReg(InvalidFile);
    Reg#(Bool) starting <- mkReg(True);

    // HELPERS //
    function Bool isElemFree(Maybe#(element) elem);
        return !isValid(elem);
    endfunction

    function Bool isElemReady(Maybe#(element) elem);
        let valElem = fromMaybe(?, elem);
        return isValid(elem) && valElem.ready_rs1 && valElem.ready_rs2;
    endfunction

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
        let ptr = findIndex(isElemFree, fromMaybe(?, entriesWire.wget));
        if(isValid(ptr)) begin
            let idx = fromMaybe(?, ptr);
            entries[idx][1] <= tagged Valid(putQueue.first);
            putQueue.deq;
        end
    endrule

    rule prepareIssue (!flushing && isValid(entriesWire.wget) && !starting);
        let ptr = findIndex(isElemReady, fromMaybe(?, entriesWire.wget));
        if(isValid(ptr)) begin
            let idx = fromMaybe(?, ptr);
            let issued = fromMaybe(?, fromMaybe(?, entriesWire.wget)[idx]);
            issueQueue.enq(issued);
            entries[idx][2] <= tagged Invalid;
            stageKonata(lfh, issued.k_id, "RS");
        end
    endrule

    rule flushEntries (flushing && !starting);
        putQueue.clear;
        readyQueue.clear;
        issueQueue.clear;

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
        $display("Reservation Station:");
        $display("Entries:");
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            $display("Entry %0d:", i, fshow(entries[i][0]));
        end
    endmethod
    `endif
endmodule

module mkReservationStationSized(RS#(32, 5, 6));
    RS#(32, 5, 6) reservation <- mkReservationStation;
    return reservation;
endmodule