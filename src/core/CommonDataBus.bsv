import FIFO::*;
import FIFOF::*;
import Vector::*;
import SpecialFIFOs::*;
import PEUtil::*;

interface CDBPort#(numeric type physicalRegSize, numeric type robTagSize);
    method Action put(PEResult#(physicalRegSize, robTagSize) res);
endinterface

interface CDB#(numeric type nPEs, numeric type physicalRegSize, numeric type robTagSize);
    interface Vector#(nPEs, CDBPort#(physicalRegSize, robTagSize)) ports;
    method ActionValue#(PEResult#(physicalRegSize, robTagSize)) get();
    method Action flush();
endinterface

module mkCommonDataBus(CDB#(nPEs, physicalRegSize, robTagSize));
    Vector#(nPEs, FIFOF#(PEResult#(physicalRegSize, robTagSize))) inputFIFOs <- replicateM(mkBypassFIFOF);
    FIFO#(PEResult#(physicalRegSize, robTagSize)) outputFIFO <- mkBypassFIFO; // mkFIFO;
    PulseWire flushing <- mkPulseWire;

    rule arbit (!flushing);
        Vector#(nPEs, Bool) valids;
        for(Integer i = 0; i < valueOf(nPEs); i = i + 1) begin
            valids[i] = inputFIFOs[i].notEmpty;
        end
        if(findElem(True, valids) matches tagged Valid .idx) begin
            let res = inputFIFOs[idx].first();
            outputFIFO.enq(res);
            inputFIFOs[idx].deq();
        end
    endrule

    rule clear (flushing);
        for(Integer i = 0; i < valueOf(nPEs); i = i + 1)
            inputFIFOs[i].clear();
        outputFIFO.clear();
    endrule

    Vector#(nPEs, CDBPort#(physicalRegSize, robTagSize)) construct_ports;
    for(Integer i = 0; i < valueOf(nPEs); i = i + 1) begin
        construct_ports[i] = interface CDBPort#(physicalRegSize, robTagSize);
            method Action put(PEResult#(physicalRegSize, robTagSize) res) if (!flushing && inputFIFOs[i].notFull) = inputFIFOs[i].enq(res);
        endinterface;
    end
    interface ports = construct_ports;
    
    method ActionValue#(PEResult#(physicalRegSize, robTagSize)) get() if (!flushing);
        let val = outputFIFO.first();
        outputFIFO.deq();
        return val;
    endmethod

    method Action flush() = flushing.send();
endmodule

module mkCommonDataBusSized(CDB#(3, 6, 6));
    CDB#(3, 6, 6) cdb <- mkCommonDataBus;
    return cdb;
endmodule