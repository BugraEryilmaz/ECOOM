// SINGLE CORE ASSOIATED CACHE -- stores words

import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector::*;

Bool debug = False;

interface L1CAU;
    method ActionValue#(HitMissType) req(CacheReq c);
    method ActionValue#(L1TaggedLine) resp;
    method Action update(L1LineIndex index, LineData data, L1LineTag tag, Bool dirty);
endinterface

module mkL1CAU(L1CAU);
    Vector#(TExp#(7), Reg#(L1LineTag)) tagStore <- replicateM(mkReg(0));
    Vector#(TExp#(7), Reg#(Bool)) validStore <- replicateM(mkReg(False));
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Binary "zero.vmh";
    BRAM1PortBE#(Bit#(7), LineData, 64) dataStore <- mkBRAM1ServerBE(cfg);
    BRAM1Port#(Bit#(7), Bool) dirtyStore <- mkBRAM1Server(cfg);
    FIFO#(L1LineTag) tagFifo <- mkFIFO;
    
    method ActionValue#(HitMissType) req(CacheReq c);
        let pa = parseL1Address(c.addr);
        let tag = tagStore[pa.index];
        let valid = validStore[pa.index];
        if (debug) $display("ind: %d, wb: %d valid: ", pa.index, c.word_byte, fshow(valid));
        let hit = tag == pa.tag && valid;
        if (hit) begin
            if (c.word_byte == 0) begin // load hit
                tagFifo.enq(tag);
                dataStore.portA.request.put(BRAMRequestBE{
                    writeen: 64'h0,
                    responseOnWrite: False,
                    address: pa.index,
                    datain: ?
                });
                // we don't care if it's dirty or not, but we do this
                // just so we can dequeue from both in resp
                dirtyStore.portA.request.put(BRAMRequest{
                    write: False,
                    responseOnWrite: False,
                    address: pa.index,
                    datain: ?
                });
                return LdHit;
            end else begin // store hit
                dirtyStore.portA.request.put(BRAMRequest{
                    write: True,
                    responseOnWrite: False,
                    address: pa.index,
                    datain: True
                });
                Bit#(512) cd_64  = zeroExtend(c.data);
                Bit#(64) we = calcBE(pa, c);
                Bit#(64) data_ofs = zeroExtend(pa.offset) << 5;
                dataStore.portA.request.put(BRAMRequestBE{
                    writeen: we,
                    responseOnWrite: False,
                    address: pa.index,
                    datain: cd_64 << data_ofs
                });
                return StHit;
            end
        end else begin
            tagFifo.enq(tag);
            dirtyStore.portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: pa.index,
                datain: ?
            });
            dataStore.portA.request.put(BRAMRequestBE{
                writeen: 64'h0,
                responseOnWrite: False,
                address: pa.index,
                datain: ?
            });
            return Miss;
        end
    endmethod

    method ActionValue#(L1TaggedLine) resp;
        let isDirty <- dirtyStore.portA.response.get();
        let data <- dataStore.portA.response.get();
        tagFifo.deq(); 
        let tag = tagFifo.first();
        return L1TaggedLine { data: data, isDirty: isDirty, tag: tag };
    endmethod

    // TODO: do update() and req() need to be called in the same cycle?
    // if so, how will we manage the read-after write behavior?
    // does a 1-port BRAM even have a separate port for reading and writing?
    method Action update(L1LineIndex index, LineData data, L1LineTag tag, Bool dirty);
        tagStore[index] <= tag;
        validStore[index] <= True;
        if (debug) $display("Updating line @ %d", index, fshow(data));
        dirtyStore.portA.request.put(BRAMRequest{
            write: True,
            responseOnWrite: False,
            address: index,
            datain: dirty
        });
        dataStore.portA.request.put(BRAMRequestBE{
            writeen: 64'hFFFFFFFFFFFFFFFF,
            responseOnWrite: False,
            address: index,
            datain: data
        });
    endmethod

endmodule

typedef struct {
    CacheReq req;
    Bool hit;
} HitMissCacheReq deriving (Eq, FShow, Bits, Bounded);

// Notice the asymmetry in this interface, as mentioned in lecture.
// The processor thinks in 32 bits, but the other side thinks in 512 bits.
interface Cache32;
    method Action putFromProc(CacheReq e);
    method ActionValue#(Word) getToProc();
    method ActionValue#(MainMemReq) getToMem();
    method Action putFromMem(MainMemResp e);
endinterface

(* synthesize *)
module mkCache32(Cache32);

    L1CAU cau <- mkL1CAU();

    FIFO#(Word) hitQ <- mkBypassFIFO;
    FIFO#(HitMissCacheReq) currReqQ <- mkPipelineFIFO;
    FIFO#(MainMemReq) lineReqQ <- mkFIFO;
    FIFO#(MainMemResp) lineRespQ <- mkFIFO;

    Reg#(CacheState) state <- mkReg(WaitCAUResp);
    Reg#(Bit#(32)) cyc <- mkReg(0);

    rule cyc_count_debug if (debug);
        cyc <= cyc + 1;
    endrule

    rule handleCAUResponse if (state == WaitCAUResp);
        let currReq = currReqQ.first();
        let pa = parseL1Address(currReq.req.addr);
        if (currReq.hit) begin 
            Word word = unpack(0);
            if (currReq.req.word_byte == 0) begin
                let x <- cau.resp();
                Vector#(16, Word) line = unpack(x.data);
                word = line[pa.offset];
                if (debug) begin 
                    $display("(cyc=%d) [Load Hit 2] Tag=%d Index=%d Offset=%d Data=%d", cyc, pa.tag, pa.index, pa.offset, word);
                end
            end 
            // If it's not a load, word value is a dont care, we just do this so CPU gets result
            currReqQ.deq();
            hitQ.enq(word);
        end else begin
            let x <- cau.resp();
            if (x.isDirty) begin
                // dirty line, need to evict and write to LLC
                lineReqQ.enq(MainMemReq {
                    write: 1'b1,
                    addr: {x.tag, pa.index},
                    data: x.data
                });
                state <= SendReq;
                if (debug) begin 
                    $display("(cyc=%d) [Dirty Miss] Tag=%d Index=%d Offset=%d (Replace Tag)=%d", cyc, pa.tag, pa.index, pa.offset, x.tag);
                end
            end else begin
                lineReqQ.enq(MainMemReq {
                    write: 1'b0,
                    addr: currReq.req.addr[31:6],
                    data: ?
                });
                if (debug) begin 
                    $display("(cyc=%d) [Clean Miss] Tag=%d Index=%d Offset=%d", cyc, pa.tag, pa.index, pa.offset);
                end
                state <= WaitDramResp;
            end
        end
    endrule

    rule handleWriteback if (state == SendReq);
        let currReq = currReqQ.first();
        let pa = parseL1Address(currReq.req.addr);
        if (currReq.hit) begin
            $display("Sanity check failed, handling writeback for a hit request?");
        end
        lineReqQ.enq(MainMemReq {
            write: 1'b0,
            addr: currReq.req.addr[31:6],
            data: ?
        });
        state <= WaitDramResp;
    endrule

    rule handleDramResponse (state == WaitDramResp);
        // Grab response from memory and the request we have been handling.
        let line = lineRespQ.first(); lineRespQ.deq();
        let currReq = currReqQ.first(); currReqQ.deq();
        let pa = parseL1Address(currReq.req.addr);

        Vector#(16, Word) line_vec = unpack(line);
        let word = line_vec[pa.offset];
        let wb = currReq.req.word_byte;
        let dirty = False;
        // Always enqueue the word. If it's a store, we don't
        // actually care about the result, just that we got one.
        hitQ.enq(word);
        if (currReq.req.word_byte != 0) begin
            // If it's a store we have to update the line with the 
            // appropriate mask before we write it back.

            // Repeat each bit of wb 8 times to form the mask
            // this is easy to do in verilog so it is probably easy to do
            // here as well, but this is what I came up with
            Vector#(8, Bit#(1)) wb0 = replicate(wb[0]);
            Vector#(8, Bit#(1)) wb1 = replicate(wb[1]);
            Vector#(8, Bit#(1)) wb2 = replicate(wb[2]);
            Vector#(8, Bit#(1)) wb3 = replicate(wb[3]);
            let mask = {pack(wb3), pack(wb2), pack(wb1), pack(wb0)};
            line_vec[pa.offset] = (word & ~mask) | (currReq.req.data & mask);
            dirty = True;
        end
        // Update line in CAU
        cau.update(pa.index, pack(line_vec), pa.tag, dirty);
        state <= WaitCAUResp;
    endrule

    method Action putFromProc(CacheReq e);
        let hitMissResult <- cau.req(e);
        let pa = parseL1Address(e.addr);
        case (hitMissResult)
            LdHit: begin
                if (debug) $display("(cyc=%d) [Load Hit  ] Tag=%d Index=%d Offset=%d", cyc, pa.tag, pa.index, pa.offset);
                currReqQ.enq(HitMissCacheReq{req: e, hit: True});
            end
            // StHit don't need to do anything
            StHit: begin
                if (debug) $display("(cyc=%d) [St Hit    ] Tag=%d Index=%d Offset=%d WB=%d Data=%d", cyc, pa.tag, pa.index, pa.offset, e.word_byte, e.data);
                currReqQ.enq(HitMissCacheReq{req: e, hit: True});
            end
            Miss: begin
                if (debug) begin 
                    if (e.word_byte == 0) $display("(cyc=%d) [Load Miss ] Tag=%d Index=%d Offset=%d", cyc, pa.tag, pa.index, pa.offset);
                    else $display("(cyc=%d) [St Miss   ] Tag=%d Index=%d Offset=%d WB=%d Data=%d", cyc, pa.tag, pa.index, pa.offset, e.word_byte, e.data);
                end
                currReqQ.enq(HitMissCacheReq{req: e, hit: False});
            end
        endcase
    endmethod
        
    method ActionValue#(Word) getToProc();
        hitQ.deq(); return hitQ.first();
    endmethod
        
    method ActionValue#(MainMemReq) getToMem();
        lineReqQ.deq(); return lineReqQ.first();
    endmethod
        
    method Action putFromMem(MainMemResp e);
        lineRespQ.enq(e);
    endmethod
endmodule
