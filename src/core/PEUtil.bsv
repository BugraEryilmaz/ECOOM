import RVUtil::*;

typedef struct {
    Bit#(robTagSize) tag;
    Bit#(32) pc;
    DecodedInst dInst;
    Bit#(32) src1;
    Bit#(32) src2;
    Maybe#(Bit#(physicalRegSize)) rd;
} PEInput#(numeric type physicalRegSize, numeric type robTagSize) deriving (Bits, FShow);

typedef struct {
    Bit#(robTagSize) tag;
    Bit#(32) pc;
    Maybe#(Bit#(physicalRegSize)) rd;
    Bit#(32) result;
} PEResult#(numeric type physicalRegSize, numeric type robTagSize) deriving (Bits, FShow);