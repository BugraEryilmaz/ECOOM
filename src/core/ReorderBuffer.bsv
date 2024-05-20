import FIFO::*;
import SpecialFIFOs::*;
import CompletionBuffer::*;
import Vector::*;
import GetPut::*;
import Ehr::*;
import PEUtil::*;
import KonataHelper::*;

typedef struct {
    Bool isStore;
    Maybe#(Bit#(5)) arch_rd;
    Maybe#(Bit#(physicalRegSize)) grad_rd;
} ROBReservation#(numeric type physicalRegSize) deriving (Bits, FShow);

typedef struct {
    Maybe#(Bit#(32)) jump_pc;
    Maybe#(Bit#(physicalRegSize)) phys_rd;
    KonataId k_id;
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

    // TODO Rewrite the reorder buffer :(
    
    // Data Structures
    Vector#(nEntries, Ehr#(3, Maybe#(Maybe#(ROBEntry#(physicalRegSize))))) cb <- replicateM(mkEhr(Invalid));
    RWire#(Vector#(nEntries, Maybe#(Maybe#(ROBEntry#(physicalRegSize))))) readCb <- mkRWire;
    FIFO#(robReservation) rs <- mkSizedFIFO(valueOf(nEntries));
    Reg#(Bit#(TLog#(nEntries))) regHead <- mkReg(0);
    Reg#(Bit#(TLog#(nEntries))) regTail <- mkReg(0);
    PulseWire flushing <- mkPulseWire;

    // Communication FIFOs //
    FIFO#(PEResult#(physicalRegSize, TLog#(nEntries))) inputFIFO <- mkBypassFIFO;
    FIFO#(ROBResult#(physicalRegSize)) completion <- mkBypassFIFO;
    FIFO#(Bit#(TLog#(nEntries))) tagFIFO <- mkFIFO;

    // RULES //

    rule rlReadCB(!flushing);
        Vector#(nEntries, Maybe#(Maybe#(ROBEntry#(physicalRegSize))))  entriesSignal = ?;
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            entriesSignal[i] = cb[i][0];
        end
        readCb.wset(entriesSignal);
    endrule

    rule rlDrain (!flushing && isValid(readCb.wget));
        if(fromMaybe(?, readCb.wget)[regHead] matches tagged Valid .validEntry) begin
            let fromRS = rs.first;
            if (validEntry matches tagged Valid .fromCB) begin
                rs.deq;
                completion.enq(ROBResult{
                    reservation: fromRS,
                    completion: fromCB
                });
                cb[regHead][0] <= tagged Invalid;
                regHead <= regHead + 1;
            end
            else if(fromRS.isStore) begin
                rs.deq;
                completion.enq(ROBResult{
                    reservation: fromRS,
                    completion: ROBEntry {
                        jump_pc: Invalid,
                        phys_rd: Invalid,
                        k_id: ?
                    }
                });
                cb[regHead][0] <= tagged Invalid;
                regHead <= regHead + 1;
            end
        end
    endrule

    rule rlComplete (!flushing && isValid(readCb.wget));
        let result = inputFIFO.first;
        inputFIFO.deq;

        cb[result.tag][1] <= tagged Valid (tagged Valid ( ROBEntry {
            phys_rd: result.rd,
            jump_pc: result.jump_pc,
            k_id: result.k_id
        }));
    endrule

    rule rlReserve (!flushing && isValid(readCb.wget));
        if (fromMaybe(?, readCb.wget)[regTail] matches tagged Invalid) begin
            tagFIFO.enq(regTail);
            cb[regTail][2] <= tagged Valid (tagged Invalid);
            regTail <= regTail + 1;
        end
    endrule

    // METHODS //
    method ActionValue#(Bit#(TLog#(nEntries))) reserve(ROBReservation#(physicalRegSize) element) if(!flushing);
        let tag = tagFIFO.first;
        tagFIFO.deq;
        rs.enq(element);
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
        regHead <= 0;
        regTail <= 0;
    endmethod
endmodule

module mkReorderBufferSized(ROB#(64, 6));
    ROB#(64, 6) rob <- mkReorderBuffer;
    return rob;
endmodule