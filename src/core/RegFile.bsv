import Vector::*;
import ConfigReg::*;
import RWire::*;

interface RFIfc#(numeric type idx_bits, numeric type data_bits);
    method ActionValue#(Bit#(data_bits)) read (Bit#(idx_bits) idx);
    method Action write (Bit#(idx_bits) idx, Bit#(data_bits) data);
endinterface

module mkRegFile(RFIfc#(idx_bits, data_bits));
    Vector#(TExp#(idx_bits), ConfigReg#(Bit#(data_bits))) rf <- replicateM(mkConfigReg(0));
    Wire#(Bit#(data_bits)) data_forward <- (mkWire);
    RWire#(Bit#(idx_bits)) idx_forward <- (mkRWire);

    method ActionValue#(Bit#(data_bits)) read (Bit#(idx_bits) idx);
        Bit#(data_bits) ret = ?;
        if (idx_forward.wget matches tagged Valid .is_forwarding) begin
            if (idx == is_forwarding) begin
                ret = data_forward;
            end
        end else begin
            ret = rf[idx];
        end
        return ret;
    endmethod

    method Action write (Bit#(idx_bits) idx, Bit#(data_bits) data);
        data_forward <= data;
        idx_forward.wset(idx);
        rf[idx] <= data;
    endmethod
endmodule

module mkRegFileSized(RFIfc#(6, 32));
    RFIfc#(6, 32) rf <- mkRegFile;
    method ActionValue#(Bit#(32)) read (Bit#(6) idx) = rf.read(idx);
    method Action write (Bit#(6) idx, Bit#(32) data) = rf.write(idx, data);
endmodule