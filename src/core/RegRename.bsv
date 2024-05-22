import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

interface RegRenameIfc#(numeric type archRegCount, numeric type physicalRegCount);
    method Maybe#(Bit#(TLog#(physicalRegCount))) map (Bit#(TLog#(archRegCount)) idx);
    method ActionValue#(Maybe#(Bit#(TLog#(physicalRegCount)))) allocate (Bit#(TLog#(archRegCount)) idx);
    method Action graduate (Maybe#(Bit#(TLog#(physicalRegCount))) old_src);
    method Action rewind (Vector#(archRegCount, Maybe#(Bit#(TLog#(physicalRegCount)))) oldState, Bit#(physicalRegCount) oldFree);
    method Vector#(archRegCount, Maybe#(Bit#(TLog#(physicalRegCount)))) readState();
    method ActionValue#(Bit#(physicalRegCount)) readFree();
endinterface

module mkRegRename(RegRenameIfc#(archRegCount, physicalRegCount))
        provisos (
            Log#(archRegCount, archBits), Log#(physicalRegCount, physBits),
            Alias#(Maybe#(Bit#(physBits)), maybePhysReg),
            Alias#(Bit#(physBits), physReg),
            Alias#(Bit#(archBits), archReg)
        );

    Vector#(archRegCount, Reg#(maybePhysReg)) maps <- replicateM(mkReg(Invalid));
    Reg#(Bit#(physicalRegCount)) freeList <- mkReg(~0);

    // Canonicalize wires
    PulseWire rewinding <- mkPulseWire;
    FIFO#(archReg) allocateArch <- mkBypassFIFO;
    FIFOF#(maybePhysReg) allocatePhys <- mkBypassFIFOF;
    FIFOF#(physReg) graduatePhys <- mkBypassFIFOF;
    FIFO#(Vector#(archRegCount, maybePhysReg)) rewindMaps <- mkBypassFIFO;
    FIFO#(Bit#(physicalRegCount)) rewindFree <- mkBypassFIFO;
    
    
    rule canonicalizeRewind if (rewinding);
        allocateArch.clear();
        allocatePhys.clear();
        graduatePhys.clear();
        for ( Integer i = 0; i < valueOf(archRegCount); i = i + 1 ) begin
            maps[i] <= rewindMaps.first()[i];
        end
        freeList <= rewindFree.first();
        rewindMaps.deq();
        rewindFree.deq();
    endrule

    rule canonicalizeMaps if (!rewinding && allocatePhys.notEmpty);
        maps[allocateArch.first()] <= allocatePhys.first();
        allocateArch.deq();
    endrule

    rule canonicalizeFreeList if (!rewinding);
        Bit#(physicalRegCount) frees = freeList;
        for ( Integer i = 0; i < valueOf(physicalRegCount); i = i + 1 ) begin
            if (graduatePhys.notEmpty && graduatePhys.first() == fromInteger(i)) begin
                frees[i] = 1;
            end else if (allocatePhys.notEmpty &&& allocatePhys.first() matches tagged Valid .allocateIdx &&& allocateIdx == fromInteger(i)) begin
                frees[i] = 0;
            end
        end
        if (graduatePhys.notEmpty) graduatePhys.deq();
        if (allocatePhys.notEmpty) allocatePhys.deq();
        freeList <= frees;
    endrule

    
    method maybePhysReg map (archReg idx);
        return maps[idx];
    endmethod

    method ActionValue#(maybePhysReg) allocate (archReg idx) if (freeList != 0 && allocatePhys.notEmpty);
        Vector#(physicalRegCount, Bit#(1)) freeBits = unpack(freeList);
        maybePhysReg allocated = tagged Invalid;
        if (idx != 0) begin
            // Findelem returns a maybe, so we need to fromMaybe it
            // And returns uint, so we need to convert it to a bit using pack
            allocated = tagged Valid pack(fromMaybe(?, findElem(1, freeBits)));
        end
        allocateArch.enq(idx);
        allocatePhys.enq(allocated);
        return allocated;
    endmethod

    method Action graduate (maybePhysReg old_src) if (graduatePhys.notFull);
        if (old_src matches tagged Valid .gradIdx) begin
            graduatePhys.enq(gradIdx);
        end
    endmethod

    method Action rewind (Vector#(archRegCount, maybePhysReg) oldState, Bit#(physicalRegCount) oldFree);
        rewinding.send();
        rewindMaps.enq(oldState);
        rewindFree.enq(oldFree);
    endmethod

    method Vector#(archRegCount, maybePhysReg) readState();
        Vector#(archRegCount, maybePhysReg) ret;
        for ( Integer i = 0; i < valueOf(archRegCount); i = i + 1 ) begin
            ret[i] = maps[i];
        end
        return ret;
    endmethod

    method ActionValue#(Bit#(physicalRegCount)) readFree();
        Bit#(physicalRegCount) ret = freeList;
        return ret;
    endmethod
endmodule

module mkRegRenameSized(RegRenameIfc#(32, 64));
    RegRenameIfc#(32, 64) rr <- mkRegRename;
    return rr;
endmodule
