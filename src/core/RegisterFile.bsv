import Vector::*;
import ConfigReg::*;
import RWire::*;
import RegFile::*;

interface RFIfc#(numeric type idx_bits, numeric type data_bits);
    method ActionValue#(Bit#(data_bits)) read1 (Bit#(idx_bits) idx);
    method ActionValue#(Bit#(data_bits)) read2 (Bit#(idx_bits) idx);
    method Action write (Bit#(idx_bits) idx, Bit#(data_bits) data);
endinterface

module mkRegisterFile(RFIfc#(idx_bits, data_bits));
    RegFile#(Bit#(idx_bits), Bit#(data_bits)) rf <- mkRegFileWCF(0, fromInteger(2**valueOf(idx_bits)-1));
    Wire#(Bit#(data_bits)) data_forward <- (mkWire);
    RWire#(Bit#(idx_bits)) idx_forward <- (mkRWire);

    method ActionValue#(Bit#(data_bits)) read1 (Bit#(idx_bits) idx);
        Bit#(data_bits) ret = rf.sub(idx);
        if (idx_forward.wget matches tagged Valid .is_forwarding &&& idx == is_forwarding) begin
            ret = data_forward;
        end
        return ret;
    endmethod

    method ActionValue#(Bit#(data_bits)) read2 (Bit#(idx_bits) idx);
        Bit#(data_bits) ret = rf.sub(idx);
        if (idx_forward.wget matches tagged Valid .is_forwarding &&& idx == is_forwarding) begin
            ret = data_forward;
        end
        return ret;
    endmethod

    method Action write (Bit#(idx_bits) idx, Bit#(data_bits) data);
        data_forward <= data;
        idx_forward.wset(idx);
        rf.upd(idx, data);
    endmethod
endmodule

module mkRegisterFileSized(RFIfc#(6, 32));
    RFIfc#(6, 32) rf <- mkRegisterFile;
    return rf;
endmodule