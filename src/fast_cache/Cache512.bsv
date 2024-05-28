import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector::*;

Bool debug = False;

interface L2CAU;
    method ActionValue#(HitMissType) req(MainMemReq m);
    method ActionValue#(L2TaggedLine) resp;
    method Action update(L2LineIndex index, LineData data, L2LineTag tag, Bool dirty);
endinterface

module mkL2CAU(L2CAU);
    Vector#(TExp#(8), Reg#(L2LineTag)) tagStore <- replicateM(mkReg(0));
    Vector#(TExp#(8), Reg#(Bool)) validStore <- replicateM(mkReg(False));
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Binary "zero512.vmh";
    BRAM1Port#(Bit#(8), LineData) dataStore <- mkBRAM1Server(cfg);
    BRAM1Port#(Bit#(8), Bool) dirtyStore <- mkBRAM1Server(cfg);
    FIFO#(L2LineTag) tagFifo <- mkFIFO;
    
    method ActionValue#(HitMissType) req(MainMemReq m);
        let pa = parseL2Address(m.addr);
        let tag = tagStore[pa.index];
        let valid = validStore[pa.index];
        if (debug) $display("ind: %d, w: %d valid: ", pa.index, m.write, fshow(valid));
        let hit = tag == pa.tag && valid;
        if (hit) begin
            if (!unpack(m.write)) begin // load hit
                tagFifo.enq(tag);
                dataStore.portA.request.put(BRAMRequest{
                    write: False,
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
                dataStore.portA.request.put(BRAMRequest{
                    write: True,
                    responseOnWrite: False,
                    address: pa.index,
                    datain: m.data
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
            dataStore.portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: pa.index,
                datain: ?
            });
            return Miss;
        end
    endmethod

    method ActionValue#(L2TaggedLine) resp;
        let isDirty <- dirtyStore.portA.response.get();
        let data <- dataStore.portA.response.get();
        tagFifo.deq(); 
        let tag = tagFifo.first();
        return L2TaggedLine { data: data, isDirty: isDirty, tag: tag };
    endmethod

    // TODO: do update() and req() need to be called in the same cycle?
    // if so, how will we manage the read-after write behavior?
    // does a 1-port BRAM even have a separate port for reading and writing?
    method Action update(L2LineIndex index, LineData data, L2LineTag tag, Bool dirty);
        tagStore[index] <= tag;
        validStore[index] <= True;
        if (debug) $display("Updating line @ %d", index, fshow(data));
        dirtyStore.portA.request.put(BRAMRequest{
            write: True,
            responseOnWrite: False,
            address: index,
            datain: dirty
        });
        dataStore.portA.request.put(BRAMRequest{
            write: True,
            responseOnWrite: False,
            address: index,
            datain: data
        });
    endmethod

endmodule

typedef struct {
    MainMemReq req;
    Bool hit;
} HitMissMainMemReq deriving (Eq, FShow, Bits, Bounded);

// Note that this interface *is* symmetric. 
interface Cache512;
    method Action putFromProc(MainMemReq e);
    method ActionValue#(MainMemResp) getToProc();
    method ActionValue#(MainMemReq) getToMem();
    method Action putFromMem(MainMemResp e);
endinterface

(* synthesize *)
module mkCache(Cache512);

    L2CAU cau <- mkL2CAU();

    FIFO#(LineData) hitQ <- mkBypassFIFO;
    FIFO#(HitMissMainMemReq) currReqQ <- mkPipelineFIFO;
    FIFO#(MainMemReq) lineReqQ <- mkFIFO;
    FIFO#(MainMemResp) lineRespQ <- mkFIFO;

    Reg#(CacheState) state <- mkReg(WaitCAUResp);
    Reg#(Bit#(32)) cyc <- mkReg(0);

    rule cyc_count_debug if (debug);
        cyc <= cyc + 1;
    endrule

    rule handleCAUResponse if (state == WaitCAUResp);
        let currReq = currReqQ.first();
        let pa = parseL2Address(currReq.req.addr);
        if (currReq.hit) begin 
            if (!unpack(currReq.req.write)) begin
                let x <- cau.resp();
                currReqQ.deq();
                hitQ.enq(x.data);
                if (debug) begin 
                    $display("(cyc=%d) [Load Hit 2] Tag=%d Index=%d", cyc, pa.tag, pa.index);
                end
            end
            // if its not a load, its done, we dont care about it
        end else begin
            let x <- cau.resp();
            if (x.isDirty) begin
                // dirty line, need to evict and write to LLC
                lineReqQ.enq(MainMemReq {
                    write: 1'b1,
                    addr: {x.tag, pa.index},
                    data: x.data
                });
                // Technically not necessary if we are doing a store,
                // as we will just overwrite the whole line that comes back.
                // But the extra logic is more complicated.
                state <= SendReq;
                if (debug) begin 
                    $display("(cyc=%d) [Dirty Miss] Tag=%d Index=%d (Replace Tag)=%d", cyc, pa.tag, pa.index, x.tag);
                end
            end else begin
                lineReqQ.enq(MainMemReq {
                    write: 1'b0,
                    addr: currReq.req.addr,
                    data: ?
                });
                if (debug) begin 
                    $display("(cyc=%d) [Clean Miss] Tag=%d Index=%d", cyc, pa.tag, pa.index);
                end
                state <= WaitDramResp;
            end
        end
    endrule

    rule handleWriteback if (state == SendReq);
        let currReq = currReqQ.first();
        let pa = parseL2Address(currReq.req.addr);
        if (currReq.hit) begin
            $display("Sanity check failed, handling writeback for a hit request?");
        end
        lineReqQ.enq(MainMemReq {
            write: 1'b0,
            addr: currReq.req.addr,
            data: ?
        });
        state <= WaitDramResp;
    endrule

    rule handleDramResponse (state == WaitDramResp);
        // Grab response from memory and the request we have been handling.
        let line = lineRespQ.first(); lineRespQ.deq();
        let currReq = currReqQ.first(); currReqQ.deq();
        let pa = parseL2Address(currReq.req.addr);

        // If it is a store, we are overwriting the entire line, so we use
        // the line from the request instead.
        if (unpack(currReq.req.write)) begin
            cau.update(pa.index, currReq.req.data, pa.tag, True);
        end else begin
            hitQ.enq(line);
            cau.update(pa.index, line, pa.tag, False);
        end
        
        state <= WaitCAUResp;
    endrule

    method Action putFromProc(MainMemReq e);
        let hitMissResult <- cau.req(e);
        let pa = parseL2Address(e.addr);
        case (hitMissResult)
            LdHit: begin
                if (debug) $display("(cyc=%d) [Load Hit  ] Tag=%d Index=%d", cyc, pa.tag, pa.index);
                currReqQ.enq(HitMissMainMemReq{req: e, hit: True});
            end
            // StHit don't need to do anything
            StHit: begin
                if (debug) $display("(cyc=%d) [St Hit    ] Tag=%d Index=%d W=%d Data=%d", cyc, pa.tag, pa.index, e.write, e.data);
            end
            Miss: begin
                if (debug) begin 
                    if (!unpack(e.write)) $display("(cyc=%d) [Load Miss ] Tag=%d Index=%d", cyc, pa.tag, pa.index);
                    else $display("(cyc=%d) [St Miss   ] Tag=%d Index=%d W=%d Data=%d", cyc, pa.tag, pa.index, e.write, e.data);
                end
                currReqQ.enq(HitMissMainMemReq{req: e, hit: False});
            end
        endcase
    endmethod

    method ActionValue#(MainMemResp) getToProc();
        hitQ.deq(); return hitQ.first();
    endmethod

    method ActionValue#(MainMemReq) getToMem();
        lineReqQ.deq(); return lineReqQ.first();
    endmethod

    method Action putFromMem(MainMemResp e);
        lineRespQ.enq(e);
    endmethod
endmodule
