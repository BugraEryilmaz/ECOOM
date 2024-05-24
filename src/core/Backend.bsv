import FIFO::*;
import SpecialFIFOs::*;
import RVUtil::*;
import PEUtil::*;
import RegRead::*;
import IALU::*;
import BAL::*;
import LSU::*;
import CommonDataBus::*;
import ReservationStation::*;
import MemTypes::*;
import KonataHelper::*;

interface Backend#(numeric type physicalRegSize, numeric type robTagSize, numeric type nInflight);
    method Action putALU(RSEntry#(physicalRegSize, robTagSize) entry);
    method Action putLSU(RSEntry#(physicalRegSize, robTagSize) entry);
    method ActionValue#(PEResult#(physicalRegSize, robTagSize)) get();
    method Action flush();

    method Action sendStore();
    method ActionValue#(CacheReq) sendReq();
    method Action getResp(Word resp);

    method Action setFile(File file);
endinterface

module mkBackend(Backend#(physicalRegSize, robTagSize, nInflight))
    provisos(
        Alias#(PEResult#(physicalRegSize, robTagSize), peResult),
        Alias#(PEInput#(physicalRegSize, robTagSize), peInput)
    );

    // Internal Structures //
    PulseWire flushing <- mkPulseWire;
    PE#(physicalRegSize, robTagSize) ialu <- mkIALU;
    PE#(physicalRegSize, robTagSize) bal <- mkBAL;
    LSU#(physicalRegSize, robTagSize, nInflight) lsu <- mkLSU;
    CDB#(3, physicalRegSize, robTagSize) cdb <- mkCommonDataBus;

    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
    Reg#(Bool) starting <- mkReg(True);

    // Communication FIFOs //
    FIFO#(peInput) rrFIFO <- mkFIFO;

    // RULES //

    rule rlIALU (!starting && !flushing);
        let val <- ialu.get();
        cdb.ports[0].put(val);
        stageKonata(lfh, val.k_id, "Rw");
    endrule

    rule rlBAL (!starting && !flushing);
        let val <- bal.get();
        cdb.ports[1].put(val);
        stageKonata(lfh, val.k_id, "Rw");
    endrule

    rule rlLSU (!starting && !flushing);
        let val <- lsu.pe.get();
        cdb.ports[2].put(val);
        stageKonata(lfh, val.k_id, "Rw");
    endrule

    // METHODS //
    method Action putALU(RSEntry#(physicalRegSize, robTagSize) entry) if (!flushing);
        PEInput#(physicalRegSize, robTagSize) peInput = PEInput {
            pe: entry.pe,
            tag: entry.tag,
            pc: entry.pc,
            dInst: entry.dInst,
            imm: getImmediate(entry.dInst),
            src1: fromMaybe(?, entry.src1),
            src2: fromMaybe(?, entry.src2),
            rd: entry.rd,
            k_id: entry.k_id
        };        
        case(peInput.pe) 
            IALU: ialu.put(peInput);
            BAL :  bal.put(peInput);
        endcase
    endmethod

    method Action putLSU(RSEntry#(physicalRegSize, robTagSize) entry) if (!flushing);
        PEInput#(physicalRegSize, robTagSize) peInput = PEInput {
            pe: entry.pe,
            tag: entry.tag,
            pc: entry.pc,
            dInst: entry.dInst,
            imm: getImmediate(entry.dInst),
            src1: fromMaybe(?, entry.src1),
            src2: fromMaybe(?, entry.src2),
            rd: entry.rd,
            k_id: entry.k_id
        };
        lsu.pe.put(peInput);
    endmethod

    method ActionValue#(PEResult#(physicalRegSize, robTagSize)) get() if (!flushing);
        let res <- cdb.get();
        return res;
    endmethod
    
    method Action flush();
        flushing.send;
        ialu.flush();
        bal.flush();
        lsu.pe.flush();
        cdb.flush();
        rrFIFO.clear();
    endmethod

    method Action sendStore() = lsu.sendStore;
    method ActionValue#(CacheReq) sendReq() = lsu.sendReq;
    method Action getResp(Word resp) = lsu.getResp(resp);

    method Action setFile(File file) if(starting);
        lfh <= file;
        starting <= False;
    endmethod
endmodule


module mkBackendSized(Backend#(6, 6, 8));
    Backend#(6, 6, 8)  backend <- mkBackend;
    return backend;
endmodule