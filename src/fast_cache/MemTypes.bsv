// Types used in L1 interface
typedef struct { Bit#(1) write; Bit#(26) addr; Bit#(512) data; } MainMemReq deriving (Eq, FShow, Bits, Bounded);
typedef struct { Bit#(4) word_byte; Bit#(32) addr; Bit#(32) data; } CacheReq deriving (Eq, FShow, Bits, Bounded);
typedef Bit#(512) MainMemResp;
typedef Bit#(32) Word;

// (Curiosity Question: CacheReq address doesn't actually need to be 32 bits. Why?)
// since we don't use the bottom 2 bits for anything
// word_byte field controls byte write

///////////////////
// Shared types //
/////////////////
typedef enum{LdHit, StHit, Miss} HitMissType deriving (Bits, Eq);

typedef enum {WaitCAUResp, SendReq, WaitDramResp} CacheState deriving (Eq, Bits, FShow);

// You can translate between Vector#(16, Word) and Bit#(512) using the pack/unpack builtin functions.
typedef Bit#(512) LineData;

///////////////
// L1 Types //
/////////////

typedef Bit#(19) L1LineTag;
typedef Bit#(7) L1LineIndex;
typedef Bit#(4) WordOffset;

typedef struct {
    LineData data;
    L1LineTag tag;
    Bool isDirty;
} L1TaggedLine;

typedef struct {
    L1LineTag tag;
    L1LineIndex index;
    WordOffset offset;
} L1ParsedAddress deriving (Bits, Eq);

function L1ParsedAddress parseL1Address(Bit#(32) address);
    return L1ParsedAddress{
        tag: address[31:13],
        index: address[12:6],
        offset: address[5:2]
    };
endfunction

function Bit#(64) calcBE(L1ParsedAddress pa, CacheReq c);
    Bit#(64) wb_64  = zeroExtend(c.word_byte);
    Bit#(64) wb_ofs = zeroExtend(pa.offset) << 2;
    return wb_64 << wb_ofs;
endfunction

///////////////
// L2 Types //
/////////////

typedef Bit#(18) L2LineTag;
typedef Bit#(8) L2LineIndex;

typedef struct {
    LineData data;
    L2LineTag tag;
    Bool isDirty;
} L2TaggedLine;

typedef struct {
    L2LineTag tag;
    L2LineIndex index;
} L2ParsedAddress deriving (Bits, Eq);

function L2ParsedAddress parseL2Address(Bit#(26) address);
    return L2ParsedAddress {
        tag: address[25:8],
        index: address[7:0]
    };
endfunction
