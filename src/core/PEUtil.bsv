import RVUtil::*;

typedef struct {
    Bit#(robTagSize) tag;
    Bit#(32) pc;
    DecodedInst dInst;
    Bit#(32) imm;
    Bit#(32) src1;
    Bit#(32) src2;
    Maybe#(Bit#(physicalRegSize)) rd;
} PEInput#(numeric type physicalRegSize, numeric type robTagSize) deriving (Bits, FShow);

typedef struct {
    Bit#(robTagSize) tag;
    Maybe#(Bit#(physicalRegSize)) rd;
    Bit#(32) result;
    Maybe#(Bit#(32)) jump_pc;
} PEResult#(numeric type physicalRegSize, numeric type robTagSize) deriving (Bits, FShow);

interface PE#(numeric type physicalRegSize, numeric type robTagSize);
    method Action put(PEInput#(physicalRegSize, robTagSize) entry);
    method ActionValue#(PEResult#(physicalRegSize, robTagSize)) get();
    method Action flush();
endinterface
