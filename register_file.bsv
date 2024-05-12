import Vector::*;
import ConfigReg::*;
import RWire::*;

interface RFIfc#(numeric type idx_bits, numeric type data_bits);
    method ActionValue#(Bit#(data_bits)) read (Bit#(idx_bits) idx);
    method Action write (Bit#(idx_bits) idx, Bit#(data_bits) data);
endinterface

module mkForwardingRF(RFIfc#(idx_bits, data_bits));
    Vector#(TExp#(idx_bits), ConfigReg#(Bit#(data_bits))) rf <- replicateM(mkConfigReg(0));
    Vector#(1, Wire#(Bit#(data_bits))) data_forward <- replicateM(mkWire);
    Vector#(1, RWire#(Bit#(idx_bits))) idx_forward <- replicateM(mkRWire);

    method ActionValue#(Bit#(data_bits)) read (Bit#(idx_bits) idx);
        Bit#(data_bits) ret;
        let is_forwarding = idx_forward[0].wget;
        if (isValid(is_forwarding) && idx == fromMaybe(?, is_forwarding)) begin
            ret = data_forward[0];
        end else begin
            ret = rf[idx];
        end
        return ret;
    endmethod

    method Action write (Bit#(idx_bits) idx, Bit#(data_bits) data);
        if (idx != 0) begin
            data_forward[0] <= data;
            idx_forward[0].wset(idx);
            rf[idx] <= data;
        end
    endmethod
endmodule