import RVUtil::*;
import BRAM::*;
import FIFO::*;
import SpecialFIFOs::*;
import DelayLine::*;
import MemTypes::*;

interface MainMem;
    method Action put(MainMemReq req);
    method ActionValue#(MainMemResp) get();
endinterface

interface MainMemFast;
    method Action put(CacheReq req);
    method ActionValue#(Word) get();
endinterface

module mkMainMemFast(MainMemFast);
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "mem.vmh";
    BRAM1PortBE#(Bit#(30), Word, 4) bram <- mkBRAM1ServerBE(cfg);
    DelayLine#(10, Word) dl <- mkDL(); // Delay by 20 cycles

    rule deq;
        let r <- bram.portA.response.get();
        dl.put(r);
        // $display("REF RESP", fshow(r));
    endrule    

    method Action put(CacheReq req);
        // $display("REF REQ", fshow(req));
        bram.portA.request.put(BRAMRequestBE{
                    writeen: req.word_byte,
                    responseOnWrite: False,
                    address: req.addr[31:2],
                    datain: req.data});
    endmethod

    method ActionValue#(Word) get();
        let r <- dl.get();
        return r;
    endmethod
endmodule

module mkMainMem(MainMem);
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "memlines.vmh";
    BRAM1Port#(LineAddr, MainMemResp) bram <- mkBRAM1Server(cfg);

    DelayLine#(20, MainMemResp) dl <- mkDL(); // Delay by 20 cycles

    rule deq;
        let r <- bram.portA.response.get();
        dl.put(r);
        // $display("GOT FROM MM TO DL1 ",fshow(r));
    endrule    


    method Action put(MainMemReq req);
        bram.portA.request.put(BRAMRequest{
                    write: unpack(req.write),
                    responseOnWrite: True,
                    address: req.addr,
                    datain: req.data});
        // $display("SENT TO MM1 WITH ",fshow(req));
    endmethod

    method ActionValue#(MainMemResp) get();
        let r <- dl.get();
        //$display("GOT FROM DL1 TO CACHE ",fshow(r));
        return r;
    endmethod

endmodule

