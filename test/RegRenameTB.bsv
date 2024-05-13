import ../src/core/RegRename::*;
import FIFO::*;

module mkRegRenameTB(Empty);
    RegRenameIfc#(32, 64) regrename <- mkRegRename;

    Reg#(Bit#(64)) i <- mkReg(0);
    Reg#(Bit#(64)) j <- mkReg(16);

    FIFO#(Maybe#(Bit#(6))) allocated <- mkFIFO;

    rule doRename if (i < 64);
        let mapped = regrename.map(i[4:0]);
        i <= i + 1;
        $display("Mapped ", i, " to ", fshow(mapped));
    endrule

    rule doAlloc;
        if (i == 64 && j > 0) begin
            let all <- regrename.allocate(j[4:0]);
            if (j % 2 == 0)
                allocated.enq(all);
            $display("Allocated ", j, " to ", fshow(all));
            i <= 0;
            j <= j - 1;
        end else if (i == 64 && j == 0) begin
            j <= 24;
        end
    endrule

    rule doFree;
        if (j != 16 && i == 64 && j % 4 == 0) begin
            if (isValid(allocated.first)) begin
                let grad = fromMaybe(?, allocated.first);
                regrename.graduate(grad);
                $display("Freed %d", grad);
            end
            allocated.deq;
        end
    endrule
endmodule