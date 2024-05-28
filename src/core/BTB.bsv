`include "Logging.bsv"
import Vector::*;
import Ehr::*;

typedef struct {
    Bit#(wTag) pc;
    Bit#(30) ppc;
} BTBEntry#(numeric type wTag) deriving(Bits, Eq, FShow);

interface BTB#(numeric type nEntries);
    method Bit#(32) predict(Bit#(32) pc);
    method Action update(Bit#(32) pc, Maybe#(Bit#(32)) target);
endinterface

module mkBTB(BTB#(nEntries))
    provisos (
        NumAlias#(wEntry, TLog#(nEntries)),
        NumAlias#(wTag, TSub#(30, wEntry))
    );

    Vector#(nEntries, Ehr#(2, Maybe#(BTBEntry#(wTag)))) entries <- replicateM(mkEhr(Invalid));

    method Bit#(32) predict(Bit#(32) pc);
        Bit#(wEntry) idx = pc[valueOf(wEntry)+1: 2];
        let val = entries[idx][0];
        Bit#(32) target = pc + 4;
        if (val matches tagged Valid .entry &&& entry.pc == pc[31:valueOf(wEntry)+2]) begin
            target = {entry.ppc, 2'b00};
        end
        return target;
    endmethod

    method Action update(Bit#(32) pc, Maybe#(Bit#(32)) target);
        Bit#(wEntry) idx = pc[valueOf(wEntry)+1: 2];
        Bit#(wTag) tag = pc[31: valueOf(wEntry)+2];
        if(target matches tagged Valid .ppc) begin
            entries[idx][1] <= tagged Valid BTBEntry {
                pc: tag,
                ppc: ppc[31:2]
            };
        end else begin
            entries[idx][1] <= tagged Invalid;
        end
    endmethod
endmodule

module mkBTBSized(BTB#(32));
    BTB#(32) btb <- mkBTB;
    return btb;
endmodule