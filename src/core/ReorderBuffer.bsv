import FIFO::*;
import SpecialFIFOs::*;
import CompletionBuffer::*;
import Vector::*;
import GetPut::*;
import Ehr::*;
import PEUtil::*;

typedef struct {
    Bool isStore;
    Maybe#(Bit#(5)) arch_rd;
    Maybe#(Bit#(physicalRegSize)) grad_rd;
} ROBReservation#(numeric type physicalRegSize) deriving (Bits, FShow);

typedef struct {
    Maybe#(Bit#(32)) jump_pc;
    Maybe#(Bit#(physicalRegSize)) phys_rd;
} ROBEntry#(numeric type physicalRegSize) deriving (Bits, FShow);

typedef struct {
    ROBReservation#(physicalRegSize) reservation;
    ROBEntry#(physicalRegSize) completion; 
} ROBResult#(numeric type physicalRegSize) deriving (Bits, FShow);

interface ROB#(numeric type nEntries, numeric type physicalRegSize);
    method ActionValue#(Bit#(TLog#(nEntries))) reserve(ROBReservation#(physicalRegSize) element);
    method Action complete(PEResult#(physicalRegSize, TLog#(nEntries)) result);
    method ActionValue#(ROBResult#(physicalRegSize)) drain();
    method Action flush();
endinterface

module mkReorderBuffer(ROB#(nEntries, physicalRegSize))
    provisos(
        Alias#(ROBReservation#(physicalRegSize), robReservation)
    );

    // Data Structures
    CompletionBuffer#(nEntries, ROBEntry#(physicalRegSize)) cb <- mkCompletionBuffer;
    FIFO#(robReservation) rs <- mkSizedFIFO(valueOf(nEntries));
    Ehr#(2, Bit#(TLog#(TAdd#(nEntries, 1)))) inflightCounter <- mkEhr(0);
    Reg#(Bit#(TLog#(TAdd#(nEntries, 1)))) posionCounter <- mkReg(0);
    PulseWire flushing <- mkPulseWire;

    // Communication FIFOs //
    FIFO#(PEResult#(physicalRegSize, TLog#(nEntries))) inputFIFO <- mkBypassFIFO;
    FIFO#(ROBResult#(physicalRegSize)) completion <- mkBypassFIFO;
    FIFO#(Bit#(TLog#(nEntries))) tagFIFO <- mkFIFO;

    // RULES //

    rule rlDrain (!flushing);
        let fromCB <- cb.drain.get;
        let fromRS = rs.first;
        rs.deq;
        inflightCounter[1] <= inflightCounter[1] - 1;
        if(posionCounter == 0) begin
            completion.enq(ROBResult{
                reservation: fromRS,
                completion: fromCB
            });
        end
        else begin
            posionCounter <= posionCounter - 1;
        end
    endrule

    rule rlComplete (!flushing);
        let result = inputFIFO.first;
        inputFIFO.deq;

        cb.complete.put(tuple2(result.tag, ROBEntry{
            phys_rd: result.rd,
            jump_pc: result.jump_pc
        }));
    endrule

    // METHODS //
    method ActionValue#(Bit#(TLog#(nEntries))) reserve(ROBReservation#(physicalRegSize) element) if(!flushing);
        let tag <- cb.reserve.get();
        rs.enq(element);
        inflightCounter[0] <= inflightCounter[0] + 1;
        return tag;
    endmethod

    method Action complete(PEResult#(physicalRegSize, TLog#(nEntries)) result) if (!flushing);
        inputFIFO.enq(result);
    endmethod

    method ActionValue#(ROBResult#(physicalRegSize)) drain() if (!flushing);
        let val = completion.first;
        completion.deq;
        return val;
    endmethod
    
    method Action flush();
        flushing.send();    
        posionCounter <= inflightCounter[0];
    endmethod
endmodule

module mkReorderBufferSized(ROB#(64, 6));
    ROB#(64, 6) rob <- mkReorderBuffer;
    return rob;
endmodule