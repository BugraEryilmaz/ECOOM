`include "Logging.bsv"
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import RVUtil::*;
import PEUtil::*;
import Fetch::*;
import ReservationStation::*;
import ReorderBuffer::*;
import RegRename::*;
import KonataHelper::*;

interface Issue#(numeric type physicalRegCount, numeric type nRobElements);
    method Action put(FetchToDecode f2d);
    method ActionValue#(RSEntry#(TLog#(physicalRegCount), TLog#(nRobElements))) get();
    method Action complete(PEResult#(TLog#(physicalRegCount), TLog#(nRobElements)) result);
    method ActionValue#(ROBResult#(TLog#(physicalRegCount))) drain();
    method Action graduate (Maybe#(Bit#(TLog#(physicalRegCount))) old_src);
    method Action flush(Vector#(32, Maybe#(Bit#(TLog#(physicalRegCount)))) oldState, Bit#(physicalRegCount) oldFree);

    method Action setFile(File file);

    `ifdef debug
    method Action dumpState();
    `endif
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

    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
    Reg#(Bool) starting <- mkReg(True);

    // Communication FIFOs //
    FIFO#(FetchToDecode) inputFIFO <- mkBypassFIFO;
    FIFO#(RSEntry#(physicalRegSize, robTagSize)) outputFIFO <- mkBypassFIFO;

    // RULES //
    rule rlIssue (!starting && !flushing);
        let f2d = inputFIFO.first;
        inputFIFO.deq();

        stageKonata(lfh, f2d.k_id, "Is");

        let dInst = decodeInst(f2d.inst);
        let isStore = getInstFields(f2d.inst).opcode == op_STORE;
        
        if(dInst.legal) begin
            // Read the current values of the registers
            let rs1 = getInstFields(f2d.inst).rs1;
            let rs2 = getInstFields(f2d.inst).rs2;
            let rd = dInst.valid_rd ? getInstFields(f2d.inst).rd : 0;

            let prs1 = dInst.valid_rs1 ? regRename.map(rs1) : tagged Invalid;
            let prs2 = dInst.valid_rs2 ? regRename.map(rs2) : tagged Invalid;
            let old_prd = dInst.valid_rd ? regRename.map(rd) : tagged Invalid;

            // Allocate a register for the rd
            let prd <- regRename.allocate(rd);

            let reservation = ROBReservation{
                isStore: isStore,
                arch_rd: dInst.valid_rd ? tagged Valid rd : tagged Invalid,
                grad_rd: old_prd,
                pc: f2d.pc,
                k_id: f2d.k_id
            };

            let tag <- rob.reserve(reservation);

            `LOG(("[Is] From IF ", fshow(f2d), " reserving ", fshow(reservation)));

            PEType pe = IALU;
            if(isControlInst(dInst)) pe = BAL;
            else if(isMemoryInst(dInst)) pe = LSU;

            let entry = RSEntry{
                pe: pe,
                tag: tag,
                pc: f2d.pc,
                dInst: dInst,
                ready_rs1: ?,
                ready_rs2: ?,
                rs1: prs1,
                rs2: prs2,
                src1: ?,
                src2: ?,
                rd: prd,
                k_id: f2d.k_id
            };
            outputFIFO.enq(entry);
            `LOG(("[Is] RS entry ", fshow(entry)));
        end
    endrule

    rule rlFlush (!starting && flushing);
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
    method Action graduate (Maybe#(Bit#(TLog#(physicalRegCount))) old_src) = regRename.graduate(old_src);

    method Action flush(Vector#(32, Maybe#(Bit#(TLog#(physicalRegCount)))) oldState, Bit#(physicalRegCount) oldFree);
        flushing.send();
        regRename.rewind(oldState, oldFree);
    endmethod

    method Action setFile(File file) if(starting);
        lfh <= file;
        rob.setFile(file);
        starting <= False;
    endmethod

    `ifdef debug
    method Action dumpState();
        $display("Issue:");
        rob.dumpState();
        regRename.dumpState();
    endmethod
    `endif
endmodule

module mkIssueSized(Issue#(64, 64));
    Issue#(64, 64) issue <- mkIssue;
    return issue;
endmodule