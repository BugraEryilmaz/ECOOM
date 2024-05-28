// PIPELINED SINGLE CORE PROCESSOR WITH 2 LEVEL CACHE
import RVUtil::*;
import BRAM::*;
import FIFO::*;
import MemTypes::*;
import CacheInterface::*;
import Core::*;

function Bool isMMIO(Bit#(32) addr);
    Bool x = case (addr) 
        32'hf000fff0: True;
        32'hf000fff4: True;
        32'hf000fff8: True;
        default: False;
    endcase;
    return x;
endfunction

module mktop_pipelined(Empty);
    // Instantiate the dual ported memory
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "mem.vmh";
    BRAM2PortBE#(Bit#(30), Word, 4) bram <- mkBRAM2ServerBE(cfg);

    CacheInterface cache <- mkCacheInterface();

    Core#(64, 32, 32, 2) rv_core <- mkCore;
    FIFO#(Mem) ireq <- mkFIFO;
    FIFO#(Mem) dreq <- mkFIFO;
    FIFO#(Mem) mmioreq <- mkFIFO;
    FIFO#(Bool) fifoMMIO <- mkFIFO;
    let debug = False;
    Reg#(Bit#(32)) cycle_count <- mkReg(0);

    rule tic;
	    cycle_count <= cycle_count + 1;
    endrule

    rule requestI;
        let req <- rv_core.imemSendReq;
        // if (debug) $display("Get IReq", fshow(req));
        ireq.enq(req);
        cache.sendReqInstr(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
    endrule

    rule responseI;
        let x <- cache.getRespInstr();
        let req = ireq.first();
        ireq.deq();
        // if (debug) $display("Get IResp ", fshow(req), fshow(x));
        req.data = x;
        rv_core.imemGetResp(req);
    endrule

    rule requestD;
        let req <- rv_core.dmemSendReq;
        if (!isMMIO(req.addr)) begin
            dreq.enq(req);
            if (debug) $display("Get DReq", fshow(req));
            // $display("DATA ",fshow(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data}));
            cache.sendReqData(CacheReq{word_byte: req.byte_en, addr: req.addr, data: req.data});
            fifoMMIO.enq(False);
        end else begin
            if (debug) $display("Get MMIOReq", fshow(req));
            if (req.byte_en == 'hf) begin
                if (req.addr == 'hf000_fff4) begin
                    // Write integer to STDERR
                    $fwrite(stderr, "%0d", req.data);
                    $fflush(stderr);
                end
            end
            if (req.addr ==  'hf000_fff0) begin
                // Writing to STDERR
                $fwrite(stderr, "%c", req.data[7:0]);
                $fflush(stderr);
            end else if (req.addr == 'hf000_fff8) begin
                $display("RAN CYCLES", cycle_count);
    
                // Exiting Simulation
                if (req.data == 0) begin
                    $fdisplay(stderr, "  [0;32mPASS[0m");
                end else begin
                    $fdisplay(stderr, "  [0;31mFAIL[0m (%0d)", req.data);
                end
                $fflush(stderr);
                $finish;
            end
    
            mmioreq.enq(req);
            fifoMMIO.enq(True);
        end
    endrule

    rule responseD;
        let val = fifoMMIO.first;
        fifoMMIO.deq;
        if (!val) begin
            let x <- cache.getRespData();

            let req = dreq.first();
            dreq.deq();
            if (debug) $display("Get DResp ", fshow(req), fshow(x));
            req.data = x;
            rv_core.dmemGetResp(req);
        end else begin
            let req = mmioreq.first();
            mmioreq.deq();
            if (debug) $display("Put MMIOResp", fshow(req));
            rv_core.dmemGetResp(req);
        end
    endrule
    
endmodule
