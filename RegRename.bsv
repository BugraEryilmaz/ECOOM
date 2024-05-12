import Vector::*;
import FIFO::*;
// import Ehr::*;

interface RegRenameIfc#(numeric type archRegCount, numeric type physicalRegCount);

    method Maybe#(Bit#(TLog#(physicalRegCount))) map (Bit#(TLog#(archRegCount)) idx);
    method ActionValue#(Maybe#(Bit#(TLog#(physicalRegCount)))) allocate (Bit#(TLog#(archRegCount)) idx);
    method Action graduate (Bit#(TLog#(physicalRegCount)) old_src);
    method Action rewind (Vector#(archRegCount, Reg#(Maybe#(Bit#(TLog#(physicalRegCount))))) oldState);
    method Vector#(archRegCount, Reg#(Maybe#(Bit#(TLog#(physicalRegCount))))) readState();
endinterface

module mkRegRename(RegRenameIfc#(archRegCount, physicalRegCount))
        provisos (Log#(archRegCount, archBits), Log#(physicalRegCount, physBits));

    Reg#(Maybe#(Bit#(physBits))) allocCounter <- mkReg(tagged Valid 0); // Counter for initial allocation
    Vector#(archRegCount, Reg#(Maybe#(Bit#(physBits)))) maps <- replicateM(mkReg(Invalid));
    FIFO#(Bit#(physBits)) freeList <- mkSizedFIFO(valueOf(physicalRegCount));

    method Maybe#(Bit#(physBits)) map (Bit#(archBits) idx);
        return maps[idx];
    endmethod

    method ActionValue#(Maybe#(Bit#(physBits))) allocate (Bit#(archBits) idx);
        Maybe#(Bit#(physBits)) allocated = tagged Invalid;
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

    method Action graduate (Bit#(physBits) old_src);
        freeList.enq(old_src);
    endmethod

    method Action rewind (Vector#(archRegCount, Reg#(Maybe#(Bit#(physBits)))) oldState);
        for ( Integer i = 0; i < valueOf(archRegCount); i = i + 1 ) begin
            maps[i] <= oldState[i];
        end
    endmethod

    method Vector#(archRegCount, Reg#(Maybe#(Bit#(physBits)))) readState();
        return maps;
    endmethod
endmodule
