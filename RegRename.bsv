import Vector::*;
import FIFO::*;
// import Ehr::*;

interface RegRenameIfc#(numeric type archRegCount, numeric type physicalRegCount);

    method Maybe#(Bit#(TLog#(physicalRegCount))) map (Bit#(TLog#(archRegCount)) idx);
    method ActionValue#(Maybe#(Bit#(TLog#(physicalRegCount)))) allocate (Bit#(TLog#(archRegCount)) idx);
    method Action graduate (Bit#(TLog#(physicalRegCount)) old_src);
    method Action rewind (Vector#(archRegCount, Maybe#(Bit#(TLog#(physicalRegCount)))) oldState);
    method Vector#(archRegCount, Maybe#(Bit#(TLog#(physicalRegCount)))) readState();
endinterface

module mkRegRename(RegRenameIfc#(archRegCount, physicalRegCount))
        provisos (
            Log#(archRegCount, archBits), Log#(physicalRegCount, physBits),
            Alias#(Maybe#(Bit#(physBits)), maybePhysReg),
            Alias#(Bit#(physBits), physReg),
            Alias#(Bit#(archBits), archReg)
        );

    Reg#(maybePhysReg) allocCounter <- mkReg(tagged Valid 0); // Counter for initial allocation
    Vector#(archRegCount, Reg#(maybePhysReg)) maps <- replicateM(mkReg(Invalid));
    FIFO#(physReg) freeList <- mkSizedFIFO(valueOf(physicalRegCount));

    method maybePhysReg map (archReg idx);
        return maps[idx];
    endmethod

    method ActionValue#(maybePhysReg) allocate (archReg idx);
        maybePhysReg allocated = tagged Invalid;
        if (idx != 0) begin
            let counter = fromMaybe(0, allocCounter);
            if (isValid(allocCounter)) begin
                allocated = tagged Valid (counter);
                if (counter == (fromInteger(valueOf(TSub#(physicalRegCount, 1))))) begin
                    allocCounter <= tagged Invalid;
                end else begin
                    allocCounter <= tagged Valid (counter + 1);
                end
            end else begin
                allocated = tagged Valid freeList.first;
                freeList.deq;
            end
        end
        maps[idx] <= allocated;
        return allocated;
    endmethod

    method Action graduate (physReg old_src);
        freeList.enq(old_src);
    endmethod

    method Action rewind (Vector#(archRegCount, maybePhysReg) oldState);
        for ( Integer i = 0; i < valueOf(archRegCount); i = i + 1 ) begin
            maps[i] <= oldState[i];
        end
    endmethod

    method Vector#(archRegCount, maybePhysReg) readState();
        Vector#(archRegCount, maybePhysReg) ret;
        for ( Integer i = 0; i < valueOf(archRegCount); i = i + 1 ) begin
            ret[i] = maps[i];
        end
        return ret;
    endmethod
endmodule
