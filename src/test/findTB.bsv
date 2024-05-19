import find::*;
import Vector::*;

module mkfindTB(Empty);

    rule rl;
        Vector#(20, UInt#(32)) y = genWith(fromInteger);
        $display("The vector is", fshow(y));
        for (UInt#(32) i = 0; i < 32; i = i + 1) begin
            let z = find(i, y);
            let k = findElem(i, y);
            if (z != k) begin
                $display("The index of ", i, " in the vector is ", fshow(z), " but ", fshow(k), " is expected");
            end
        end
        $finish;
    endrule

endmodule