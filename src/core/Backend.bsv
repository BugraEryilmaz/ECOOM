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

interface Backend#(numeric type physicalRegSize, numeric type robTagSize, numeric type nInflight);
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry);
    method ActionValue#(PEResult#(physicalRegSize, robTagSize)) get();
    method Action flush();

    method Action sendStore();
    method ActionValue#(CacheReq) sendReq();
    method Action getResp(Word resp);
endinterface

module mkBackend(Backend#(physicalRegSize, robTagSize, nInflight))
    provisos(
        Alias#(PEResult#(physicalRegSize, robTagSize), peResult),
        Alias#(PEInput#(physicalRegSize, robTagSize), peInput)
    );
    // Internal Structures //
    PulseWire flushing <- mkPulseWire;
    RegRead#(physicalRegSize, robTagSize) regRead <- mkRegRead;
    PE#(physicalRegSize, robTagSize) ialu <- mkIALU;
    PE#(physicalRegSize, robTagSize) bal <- mkBAL;
    LSU#(physicalRegSize, robTagSize, nInflight) lsu <- mkLSU;
    CDB#(3, physicalRegSize, robTagSize) cdb <- mkCommonDataBus;

    // Communication FIFOs //
    FIFO#(peInput) rrFIFO <- mkFIFO;

    // RULES //
    rule rlReadRead(!flushing);
        let val <- regRead.get();
        rrFIFO.enq(val);
    endrule

    rule rlArbit (!flushing);
        let val = rrFIFO.first;
        rrFIFO.deq();
        case(val.pe) 
            IALU: ialu.put(val);
            BAL :  bal.put(val);
            LSU :  lsu.pe.put(val);
        endcase
    endrule

    rule rlIALU (!flushing);
        let val <- ialu.get();
        cdb.ports[0].put(val);
    endrule

    rule rlBAL (!flushing);
        let val <- bal.get();
        cdb.ports[1].put(val);
    endrule

    rule rlLSU (!flushing);
        let val <- lsu.pe.get();
        cdb.ports[2].put(val);
    endrule

    // METHODS //
    method Action put(RSEntry#(physicalRegSize, robTagSize) entry) if (!flushing);
        regRead.put(entry);
    endmethod

    method ActionValue#(PEResult#(physicalRegSize, robTagSize)) get() if (!flushing);
        let res <- cdb.get();
        if (res.rd matches tagged Valid .rd)
            regRead.putToRF(rd, res.result);
        return res;
    endmethod
    
    method Action flush();
        flushing.send;
        regRead.flush();
        ialu.flush();
        bal.flush();
        lsu.pe.flush();
        cdb.flush();
    endmethod

    method Action sendStore() if (!flushing) = lsu.sendStore;
    method ActionValue#(CacheReq) sendReq() = lsu.sendReq;
    method Action getResp(Word resp) = lsu.getResp(resp);
endmodule


module mkBackendSized(Backend#(6, 6, 8));
    Backend#(6, 6, 8)  backend <- mkBackend;
    return backend;
endmodule