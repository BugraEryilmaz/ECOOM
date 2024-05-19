import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import Frontend::*;
import Backend::*;
import MemTypes::*;
import ReorderBuffer::*;

interface Core#(numeric type nPhysicalRegs, numeric type nRobElements, numeric type nRSEntries, numeric type nInflightDmem);
    method ActionValue#(CacheReq) imemSendReq();
    method Action imemGetResp(Word resp);

    method ActionValue#(CacheReq) dmemSendReq();
    method Action dmemGetResp(Word resp);
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
    
    // Communication FIFOs //
    FIFOF#(ROBResult#(TLog#(nPhysicalRegs))) jumpFIFO <- mkFIFOF;
    
    // RULES //
    rule rlConnect (!jumpFIFO.notEmpty);
        let inst <- frontend.get();
        backend.put(inst);
    endrule

    rule rlComplete (!jumpFIFO.notEmpty);
        let res <- backend.get();
        frontend.complete(res);
    endrule

    rule rlCommit (!jumpFIFO.notEmpty);
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

    rule rlRewind (jumpFIFO.notEmpty);
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


    // METHODS //
    method ActionValue#(CacheReq) imemSendReq();
        let val <- frontend.sendReq;
        return val;
    endmethod

    method Action imemGetResp(Word resp) = frontend.getResp(resp);

    method ActionValue#(CacheReq) dmemSendReq();
        let val <- backend.sendReq;
        return val;
    endmethod

    method Action dmemGetResp(Word resp) = backend.getResp(resp);

endmodule

module mkCoreSized(Core#(64, 64, 32, 7));
    Core#(64, 64, 32, 7) core <- mkCore;
    return core;
endmodule