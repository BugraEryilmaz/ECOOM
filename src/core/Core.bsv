import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import Frontend::*;
import Backend::*;
import MemTypes::*;
import ReorderBuffer::*;
import PEUtil::*;
import KonataHelper::*;

typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(32) data; } Mem deriving (Eq, FShow, Bits);

interface Core#(numeric type nPhysicalRegs, numeric type nRobElements, numeric type nRSEntries, numeric type nInflightDmem);
    method ActionValue#(Mem) imemSendReq();
    method Action imemGetResp(Mem resp);

    method ActionValue#(Mem) dmemSendReq();
    method Action dmemGetResp(Mem resp);
endinterface

module mkCore(Core#(nPhysicalRegs, nRobElements, nRSEntries, nInflightDmem))
    provisos(
        Alias#(Maybe#(Bit#(TLog#(nPhysicalRegs))), tPhysicalReg),
        NumAlias#(physicalRegSize, TLog#(nPhysicalRegs)),
        NumAlias#(robTagSize, TLog#(nRobElements))
    );

    // Internal Structures //
    Frontend#(nPhysicalRegs, nRobElements, nRSEntries) frontend <- mkFrontend;
    Backend#(physicalRegSize, robTagSize, nInflightDmem) backend <- mkBackend;

    Vector#(32, Reg#(tPhysicalReg)) registerMap <- replicateM(mkReg(Invalid));
    Reg#(Bit#(nPhysicalRegs)) freeList <- mkReg(~0);
    
    // Konata
	// Code to support Konata visualization
    String dumpFile = "output.log" ;
    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
	Reg#(KonataId) commit_id <- mkReg(0);
    
	FIFO#(KonataId) retired <- mkFIFO;
	FIFO#(KonataId) squashed <- mkFIFO;
    Reg#(Bool) starting <- mkReg(True);
	rule do_tic_logging;
        if (starting) begin
            let f <- $fopen(dumpFile, "w") ;
            lfh <= f;
            $fwrite(f, "Kanata\t0004\nC=\t1\n");
            starting <= False;
            frontend.setFile(lfh);
            backend.setFile(lfh);
        end
		konataTic(lfh);
	endrule

    // Communication FIFOs //
    FIFOF#(ROBResult#(TLog#(nPhysicalRegs))) jumpFIFO <- mkFIFOF;
    
    // RULES //
    rule rlConnect (!starting && !jumpFIFO.notEmpty);
        let inst <- frontend.get();
        backend.put(inst);
    endrule

    rule rlComplete (!starting && !jumpFIFO.notEmpty);
        let res <- backend.get();
        frontend.complete(res);
        stageKonata(lfh, res.k_id, "Cm");
        retired.enq(res.k_id);
    endrule

    rule rlCommit (!starting && !jumpFIFO.notEmpty);
        let val <- frontend.drain();

        // Handle store
        if(val.reservation.isStore) begin
            backend.sendStore();
        end

        // Handle register renaming
        if(val.reservation.arch_rd matches tagged Valid .rd) begin
            registerMap[rd] <= val.completion.phys_rd;
        end

        // Handle register graduation
        frontend.graduate(val.reservation.grad_rd);

        // Handle jumping
        jumpFIFO.enq(val);
    endrule

    rule rlRewind (!starting && jumpFIFO.notEmpty);
        let val = jumpFIFO.first;
        jumpFIFO.deq;

        Vector::Vector#(32, Maybe#(Bit#(TLog#(nPhysicalRegs)))) readRegMap = ?;
        for(Integer i = 0; i < 32; i = i + 1) readRegMap[i] = registerMap[i];

        if(val.completion.jump_pc matches tagged Valid .jump_pc) begin
            frontend.jumpAndRewind(
                jump_pc,
                readRegMap,
                freeList
            );
        end
    endrule

    // Administration //
    rule administrative_konata_commit;
        retired.deq();
        let f = retired.first();
        commitKonata(lfh, f, commit_id);
    endrule
    
    rule administrative_konata_flush;
        squashed.deq();
        let f = squashed.first();
        squashKonata(lfh, f);
    endrule

    // METHODS //
    method ActionValue#(Mem) imemSendReq();
        let val <- frontend.sendReq;
        return Mem{
            byte_en: val.word_byte,
            addr: val.addr,
            data: val.data
        };
    endmethod

    method Action imemGetResp(Mem resp);
        frontend.getResp(resp.data);
    endmethod

    method ActionValue#(Mem) dmemSendReq();
        let val <- backend.sendReq;
        return Mem{
            byte_en: val.word_byte,
            addr: val.addr,
            data: val.data
        };
    endmethod

    method Action dmemGetResp(Mem resp);
        backend.getResp(resp.data);
    endmethod

endmodule

module mkCoreSized(Core#(64, 64, 32, 7));
    Core#(64, 64, 32, 7) core <- mkCore;
    return core;
endmodule