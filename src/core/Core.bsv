`include "Logging.bsv"
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import Frontend::*;
import Backend::*;
import MemTypes::*;
import ReorderBuffer::*;
import PEUtil::*;
import Ehr::*;
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
            `LOG(("Starting\n"));
            frontend.setFile(lfh);
            backend.setFile(lfh);
        end
		konataTic(lfh);
	endrule

    // Communication FIFOs //
    FIFO#(ROBResult#(physicalRegSize)) commitQueue <- mkFIFO;

    // Debug //
    `ifdef debug
    Ehr#(2, Bit#(64)) cnt <- mkEhr(0);

    rule rlclk;
        cnt[0] <= cnt[0] + 1;
    endrule

    rule deadlockChecker;
        if(cnt[0] == 200) begin
            $display("Deadlock detected");
            frontend.dumpState();
            $finish;
        end
    endrule
    `endif
    
    // RULES //
    rule rlConnectALU (!starting);
        let inst <- frontend.getALU();
        backend.putALU(inst);
    endrule

    rule rlConnectLSU (!starting);
        let inst <- frontend.getLSU();
        backend.putLSU(inst);
    endrule

    rule rlComplete (!starting);
        let res <- backend.get();
        frontend.complete(res);
        `LOG(("[ROB] Received from backend ", fshow(res)));
    endrule

    rule rlDrain (!starting);
        let val <- frontend.drain();
        commitQueue.enq(val);
    endrule

    rule rlCommit (!starting);
        let val = commitQueue.first;
        commitQueue.deq();

        // Handle store
        if(val.reservation.isStore) begin
            backend.sendStore();
        end else begin
            // Handle register renaming and free list
            Vector#(32, Maybe#(Bit#(TLog#(nPhysicalRegs)))) nextRegMap = ?;
            for(Integer i = 0; i < 32; i = i + 1) nextRegMap[i] = registerMap[i];
            Bit#(nPhysicalRegs) nextFreeList = freeList;
            if(val.reservation.arch_rd matches tagged Valid .rd) begin
                nextRegMap[rd] = val.completion.phys_rd;

                for(Integer i = 0; i < valueOf(nPhysicalRegs); i = i + 1) begin
                    if (val.reservation.grad_rd matches tagged Valid .grad_rd &&& grad_rd == fromInteger(i)) begin
                        nextFreeList[i] = 1;
                    end else if (val.completion.phys_rd matches tagged Valid .phys_rd &&& phys_rd == fromInteger(i)) begin
                        nextFreeList[i] = 0;
                    end
                end
            end
            for(Integer i = 0; i < 32; i = i + 1) registerMap[i] <= nextRegMap[i];
            freeList <= nextFreeList;

            // Handle register graduation
            frontend.graduate(val.reservation.grad_rd);

            // Handle jumping
            if(val.completion.jump_pc matches tagged Valid .jump_pc) begin
                frontend.jumpAndRewind(
                    jump_pc,
                    nextRegMap,
                    nextFreeList
                );
                backend.flush();
            end
        end
        
        `LOG(("[CS] Committing ", fshow(val)));
        stageKonata(lfh, val.completion.k_id, "Cm");
        retired.enq(val.completion.k_id);

        `ifdef debug
        cnt[1] <= 0;
        `endif
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