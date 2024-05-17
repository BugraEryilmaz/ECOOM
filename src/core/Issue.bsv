import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import RVUtil::*;
import PEUtil::*;
import Fetch::*;
import ReservationStation::*;
import ReorderBuffer::*;
import RegRename::*;

interface Issue#(numeric type physicalRegCount, numeric type nRobElements);
    method Action put(FetchToDecode f2d);
    method ActionValue#(RSEntry#(TLog#(physicalRegCount), TLog#(nRobElements))) get();
    method Action complete(PEResult#(TLog#(physicalRegCount), TLog#(nRobElements)) result);
    method ActionValue#(ROBResult#(TLog#(physicalRegCount))) drain();
    method Action graduate (Maybe#(Bit#(TLog#(physicalRegCount))) old_src);
    method Action flush(Vector#(32, Maybe#(Bit#(TLog#(physicalRegCount)))) oldState, Bit#(physicalRegCount) oldFree);
endinterface

module mkIssue(Issue#(physicalRegCount, nRobElements))
    provisos(
        NumAlias#(physicalRegSize, TLog#(physicalRegCount)),
        NumAlias#(robTagSize, TLog#(nRobElements))
    );
    // Internal Modules //
    PulseWire flushing <- mkPulseWire;
    RegRenameIfc#(32, physicalRegCount) regRename <- mkRegRename;
    ROB#(nRobElements, physicalRegSize) rob <- mkReorderBuffer;

    // Communication FIFOs //
    FIFO#(FetchToDecode) inputFIFO <- mkBypassFIFO;
    FIFO#(RSEntry#(physicalRegSize, robTagSize)) outputFIFO <- mkBypassFIFO;

    // RULES //
    rule rlIssue (!flushing);
        let f2d = inputFIFO.first;
        inputFIFO.deq();

        let dInst = decodeInst(f2d.inst);
        let isStore = getInstFields(f2d.inst).opcode == op_STORE;
        
        // Read the current values of the registers
        let rs1 = getInstFields(f2d.inst).rs1;
        let rs2 = getInstFields(f2d.inst).rs2;
        let rd = getInstFields(f2d.inst).rd;

        let prs1 = dInst.valid_rs1 ? regRename.map(rs1) : tagged Invalid;
        let prs2 = dInst.valid_rs2 ? regRename.map(rs2) : tagged Invalid;
        let old_prd = dInst.valid_rd ? regRename.map(rd) : tagged Invalid;

        // Allocate a register for the rd
        let prd <- regRename.allocate(rd);

        let tag <- rob.reserve(ROBReservation{
            isStore: isStore,
            arch_rd: dInst.valid_rd ? tagged Valid rd : tagged Invalid,
            phys_rd: prd,
            grad_rd: old_prd
        });

        PEType pe = IALU;
        if(isControlInst(dInst)) pe = BAL;
        else if(isMemoryInst(dInst)) pe = LSU;

        outputFIFO.enq(RSEntry{
            pe: pe,
            tag: tag,
            pc: f2d.pc,
            dInst: dInst,
            ready_rs1: ?,
            ready_rs2: ?,
            rs1: prs1,
            rs2: prs2,
            rd: prd
        });
    endrule

    rule rlFlush (flushing);
        inputFIFO.clear();
        outputFIFO.clear();
        rob.flush();
    endrule

    // METHODS //
    method Action put(FetchToDecode f2d) if (!flushing) = inputFIFO.enq(f2d);

    method ActionValue#(RSEntry#(physicalRegSize, robTagSize)) get() if (!flushing);
        let val = outputFIFO.first;
        outputFIFO.deq();
        return val;
    endmethod

    method Action complete(PEResult#(physicalRegSize, robTagSize) result) if (!flushing) = rob.complete(result);
    method ActionValue#(ROBResult#(physicalRegSize)) drain() if (!flushing) = rob.drain();
    method Action graduate (Maybe#(Bit#(TLog#(physicalRegCount))) old_src) if (!flushing) = regRename.graduate(old_src);

    method Action flush(Vector#(32, Maybe#(Bit#(TLog#(physicalRegCount)))) oldState, Bit#(physicalRegCount) oldFree);
        flushing.send();
        regRename.rewind(oldState, oldFree);
    endmethod
endmodule

module mkIssueSized(Issue#(64, 64));
    Issue#(64, 64) issue <- mkIssue;
    return issue;
endmodule