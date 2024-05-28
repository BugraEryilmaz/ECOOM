`include "Logging.bsv"
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
    Bit#(32) pc;
    Bit#(32) ppc;
    KonataId k_id;
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
    method Action setFile(File file);
    `ifdef debug
    method Action dumpState();
    `endif
endinterface

module mkReorderBuffer(ROB#(nEntries, physicalRegSize))
    provisos(
        Alias#(ROBReservation#(physicalRegSize), robReservation)
    );

    // TODO Rewrite the reorder buffer :(

    Reg#(File) lfh <- mkReg(InvalidFile);
    Reg#(Bool) starting <- mkReg(True);
    
    // Data Structures
    Vector#(nEntries, Ehr#(4, Maybe#(Maybe#(ROBEntry#(physicalRegSize))))) cb <- replicateM(mkEhr(Invalid));
    RWire#(Vector#(nEntries, Maybe#(Maybe#(ROBEntry#(physicalRegSize))))) readCb <- mkRWire;
    FIFO#(robReservation) rs <- mkSizedFIFO(valueOf(nEntries));
    Ehr#(2, Bit#(TLog#(nEntries))) regHead <- mkEhr(0);
    Ehr#(2, Bit#(TLog#(nEntries))) regTail <- mkEhr(0);

    // Communication FIFOs //
    FIFO#(PEResult#(physicalRegSize, TLog#(nEntries))) inputFIFO <- mkBypassFIFO;
    FIFO#(ROBResult#(physicalRegSize)) completion <- mkBypassFIFO;
    FIFO#(Bit#(TLog#(nEntries))) tagFIFO <- mkBypassFIFO;

    // RULES //

    rule rlReadCB (!starting);
        Vector#(nEntries, Maybe#(Maybe#(ROBEntry#(physicalRegSize))))  entriesSignal = ?;
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            entriesSignal[i] = cb[i][0];
        end
        readCb.wset(entriesSignal);
    endrule

    rule rlDrain (isValid(readCb.wget) && !starting);
        if(fromMaybe(?, readCb.wget)[regHead[0]] matches tagged Valid .validEntry) begin
            let fromRS = rs.first;
            `LOG(("[ROB] Waiting on ", fshow(fromRS)));
            if (validEntry matches tagged Valid .fromCB) begin
                rs.deq;
                completion.enq(ROBResult{
                    reservation: fromRS,
                    completion: fromCB
                });
                stageKonata(lfh, fromRS.k_id, "Dr");
                cb[regHead[0]][0] <= tagged Invalid;
                regHead[0] <= regHead[0] + 1;
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
                stageKonata(lfh, fromRS.k_id, "Dr");
                cb[regHead[0]][0] <= tagged Invalid;
                regHead[0] <= regHead[0] + 1;
            end
        end
    endrule

    rule rlComplete (isValid(readCb.wget) && !starting);
        let result = inputFIFO.first;
        inputFIFO.deq;

        cb[result.tag][1] <= tagged Valid (tagged Valid ( ROBEntry {
            phys_rd: result.rd,
            jump_pc: result.jump_pc,
            k_id: result.k_id
        }));
    endrule

    rule rlReserve (isValid(readCb.wget) && !starting);
        if (fromMaybe(?, readCb.wget)[regTail[0]] matches tagged Invalid) begin
            tagFIFO.enq(regTail[0]);
            cb[regTail[0]][2] <= tagged Valid (tagged Invalid);
            regTail[0] <= regTail[0] + 1;
        end
    endrule

    // METHODS //
    method ActionValue#(Bit#(TLog#(nEntries))) reserve(ROBReservation#(physicalRegSize) element) if (!starting);
        let tag = tagFIFO.first;
        tagFIFO.deq;
        rs.enq(element);
        return tag;
    endmethod

    method Action complete(PEResult#(physicalRegSize, TLog#(nEntries)) result) if (!starting);
        inputFIFO.enq(result);
    endmethod

    method ActionValue#(ROBResult#(physicalRegSize)) drain() if (!starting);
        let val = completion.first;
        completion.deq;
        return val;
    endmethod
    
    method Action flush() if (!starting);
        inputFIFO.clear();
        completion.clear();
        tagFIFO.clear();
        rs.clear();
        regHead[1] <= 0;
        regTail[1] <= 0;
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            cb[i][3] <= tagged Invalid;
        end
    endmethod

    method Action setFile(File file);
        starting <= False;
        lfh <= file;
    endmethod

    `ifdef debug
    method Action dumpState();
        $display("Reorder Buffer State:");
        $display("  Head: %0d", regHead[0]);
        $display("  Tail: %0d", regTail[0]);
        for(Integer i = 0; i < valueOf(nEntries); i = i + 1) begin
            $display("  Entry %0d: ", i, fshow(cb[i][0]));
        end
    endmethod
    `endif
endmodule

module mkReorderBufferSized(ROB#(64, 6));
    ROB#(64, 6) rob <- mkReorderBuffer;
    return rob;
endmodule