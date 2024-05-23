`include "Logging.bsv"
import Vector::*;
import ConfigReg::*;
import RWire::*;

interface RDYBIfc#(numeric type idx_bits);
    method ActionValue#(Bit#(1)) read (Bit#(idx_bits) idx);
    method Action set (Bit#(idx_bits) idx);
    method Action rst (Bit#(idx_bits) idx);
    method Action flush();

    `ifdef debug
    method Action dumpState();
    `endif
endinterface

module mkRDYB(RDYBIfc#(idx_bits));
    Vector#(TExp#(idx_bits), Reg#(Bit#(1))) rf <- replicateM(mkReg(1));
    RWire#(Bit#(idx_bits)) setIdx <- (mkRWire); // coming from the common databus
    RWire#(Bit#(idx_bits)) resetIdx <- (mkRWire); // coming from rename
    PulseWire flushWire <- (mkPulseWire); // coming from commit

    rule canonicalize;
        for (Integer i = 0; i < valueOf(TExp#(idx_bits)); i = i + 1) begin
            if (flushWire) begin
                rf[i] <= 1;
            end else begin
                if (resetIdx.wget matches tagged Valid .idx &&& fromInteger(i) == idx) begin
                    rf[i] <= 0;
                end
                else if (setIdx.wget matches tagged Valid .idx &&& fromInteger(i) == idx) begin
                    rf[i] <= 1;
                end
            end
        end
    endrule

    method ActionValue#(Bit#(1)) read (Bit#(idx_bits) idx) if (!flushWire);
        Bit#(1) ret;
        let is_ing = setIdx.wget;
        if (isValid(is_ing) && idx == fromMaybe(?, is_ing)) begin
            ret = 1;
        end else begin
            ret = rf[idx];
        end
        return ret;
    endmethod

    method Action set (Bit#(idx_bits) idx) if (!flushWire);
        setIdx.wset(idx);
    endmethod

    method Action rst (Bit#(idx_bits) idx) if (!flushWire);
        resetIdx.wset(idx);
    endmethod

    method Action flush();
        flushWire.send();
    endmethod

    `ifdef debug
    method Action dumpState();
        $display("RDYB state:");
        for (Integer i = 0; i < valueOf(TExp#(idx_bits)); i = i + 1) begin
            $display("  %d: %d", i, fshow(rf[i]));
        end
    endmethod
    `endif
endmodule

module mkRDYBSized(RDYBIfc#(6));
    RDYBIfc#(6) rdyb <- mkRDYB;
    return rdyb;
endmodule