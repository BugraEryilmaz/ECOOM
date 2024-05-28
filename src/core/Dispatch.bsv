`include "Logging.bsv"
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
import RegisterFile::*;
import RDYB::*;
import KonataHelper::*;

interface Dispatch#(numeric type physicalRegSize, numeric type robTagSize, numeric type nRSEntries);
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry);
    method ActionValue#(RSEntry#(physicalRegSize, robTagSize)) getALU(); 
    method ActionValue#(RSEntry#(physicalRegSize, robTagSize)) getLSU(); 
    method Action makeReady(WakeUpRegVal#(physicalRegSize) rs);
    method Action flush();

    method Action setFile(File file);

    `ifdef debug
    method Action dumpState();
    `endif
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
    RFIfc#(physicalRegSize, 32) rf <- mkRegisterFile;

    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
    Reg#(Bool) starting <- mkReg(True);

    // Communication FIFOs //
    FIFO#(rsEntry) putFIFO <- mkBypassFIFO;
    FIFOF#(rsEntry) aluIssue <- mkBypassFIFOF;
    FIFOF#(rsEntry) lsuIssue <- mkBypassFIFOF;

    // RULES //
    rule rlEnqueue (!starting && !flushing);
        let entry = putFIFO.first;
        putFIFO.deq;
        stageKonata(lfh, entry.k_id, "Ds");

        let ready_rs1 <- rdby.read(fromMaybe(?, entry.rs1));
        let ready_rs2 <- rdby.read(fromMaybe(?, entry.rs2));
        entry.ready_rs1 = isValid(entry.rs1) ? (ready_rs1 == 1 ? True : False) : True;
        entry.ready_rs2 = isValid(entry.rs2) ? (ready_rs2 == 1 ? True : False) : True;
        
        if (entry.rs1 matches tagged Valid .rs1) begin
            let src1 <- rf.read1(rs1);
            entry.src1 = tagged Valid src1;
        end else begin
            entry.src1 = tagged Valid 0;
        end

        if (entry.rs2 matches tagged Valid .rs2) begin
            let src2 <- rf.read2(rs2);
            entry.src2 = tagged Valid src2;
        end else begin
            entry.src2 = tagged Valid 0;
        end

        if(entry.rd matches tagged Valid .rd) begin
            rdby.rst(rd);
        end

        if(entry.pe == LSU) rsLSU.put(entry);
        else rsInteger.put(entry);

        `LOG(("[Ds] Enter to RS ", fshow(entry)));
    endrule

    rule rlIntDispatch (!starting && !flushing && aluIssue.notFull);
        let val <- rsInteger.issue;
        aluIssue.enq(val);
        `LOG(("[Ds] Sent to IALU ", fshow(val)));
    endrule

    rule rlLsuDispatch (!starting && !flushing && lsuIssue.notFull);
        let val <- rsLSU.issue;
        lsuIssue.enq(val);
        `LOG(("[Ds] Sent to LSU ", fshow(val)));
    endrule

    rule rlFlush (!starting && flushing);
        rsInteger.flush();
        rsLSU.flush();
        rdby.flush();
        putFIFO.clear();
        aluIssue.clear();
        lsuIssue.clear();
    endrule

    // METHODS //
    method Action put(rsEntry entry) if(!flushing);
        putFIFO.enq(entry);
    endmethod

    method ActionValue#(rsEntry) getALU() if(!flushing);
        let val = aluIssue.first;
        aluIssue.deq;
        return val;
    endmethod

    method ActionValue#(rsEntry) getLSU() if(!flushing);
        let val = lsuIssue.first;
        lsuIssue.deq;
        return val;
    endmethod

    method Action makeReady(WakeUpRegVal#(physicalRegSize) wake) if(!flushing);
        rsInteger.makeReady(wake);
        rsLSU.makeReady(wake);
        if (wake.rs matches tagged Valid .rs) begin
            rdby.set(rs);
            rf.write(rs, wake.src);
        end
    endmethod

    method Action flush() = flushing.send();

    method Action setFile(File file) if(starting);
        lfh <= file;
        rsInteger.setFile(file);
        rsLSU.setFile(file);
        starting <= False;
    endmethod

    `ifdef debug
    method Action dumpState();
        $display("Dispatch:");
        rsInteger.dumpState;
        rsLSU.dumpState;
        rdby.dumpState;
    endmethod
    `endif
endmodule

module mkDispatchSized(Dispatch#(6, 6, 16));
    Dispatch#(6, 6, 16) dispatch <- mkDispatch;
    return dispatch;
endmodule