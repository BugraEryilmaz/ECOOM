import Vector :: * ;
// Types used in L1 interface
typedef Bit#(26) LineAddr;

typedef Bit#(32) CacheLineAddr;

typedef struct { Bit#(1) write; Bit#(26) addr; Bit#(512) data; } MainMemReq deriving (Eq, FShow, Bits, Bounded);
typedef struct { Bit#(4) word_byte; Bit#(32) addr; Bit#(32) data; } CacheReq deriving (Eq, FShow, Bits, Bounded);
typedef struct { Bit#(TDiv#(dataBits, 8)) word_byte; Bit#(addrBits) addr; Bit#(dataBits) data; } GenericCacheReq#(numeric type addrBits, numeric type dataBits) deriving (Eq, FShow, Bits, Bounded);
typedef Bit#(512) MainMemResp;
typedef Bit#(32) Word;

// (Curiosity Question: CacheReq address doesn't actually need to be 32 bits. Why?)

// Helper types for implementation (L1 cache):
typedef enum {LDHIT,STHIT,MISS} CacheUnitHitMiss deriving(Eq, Bits, FShow);

typedef Bit#(TSub#(addrBits, TAdd#(TAdd#(TLog#(numWords), numLogLines),TLog#(numBanks)))) CUTag#(numeric type addrBits, numeric type numWords, numeric type numLogLines, numeric type numBanks);

typedef struct {
    Vector#(numWords, cuWord) words;
    cuTagT tag;
    cuStatus status;
} TaggedLine#(type cuWord, type cuTagT, type cuStatus, numeric type numWords) deriving(Eq, Bits, FShow);

typedef struct {
    CacheUnitHitMiss hitMiss;
    cuWord ldData;
    TaggedLine#(cuWord, cuTagT, cuStatus, numWords) missLine;
} CacheUnitResp#(type cuWord, type cuTagT, type cuStatus, numeric type numWords) deriving(Eq, Bits, FShow);

typedef struct {
    Bit#(addrBits) addr;
    Bit#(dataBits) data;
    Bit#(TDiv#(dataBits, 8)) writeEn;
} CUCacheReq#(numeric type addrBits, numeric type dataBits) deriving(Eq, Bits, FShow);

typedef enum {
    Invalid,
    Clean,
    Dirty
} LineState deriving (Eq, Bits, FShow);

typeclass Valid#(type a);
    function Bool isValid(a x);
endtypeclass

instance Valid#(LineState);
    function Bool isValid(LineState x);
        return x != Invalid;
    endfunction
endinstance

typeclass Dirty#(type a);
    function a makeDirty(a x);
endtypeclass

instance Dirty#(LineState);
    function LineState makeDirty(LineState x);
        return Dirty;
    endfunction
endinstance

// You should also define a type for LineTag, LineIndex. Calculate the appropriate number of bits for your design.
// typedef ??????? LineTag
// typedef ??????? LineIndex
// You may also want to define a type for WordOffset, since multiple Words can live in a line.

// You can translate between Vector#(16, Word) and Bit#(512) using the pack/unpack builtin functions.
// typedef Vector#(16, Word) LineData  (optional)

// Optional: You may find it helpful to make a function to parse an address into its parts.
// e.g.,
// typedef struct {
    //     LineTag tag;
    //     LineIndex index;
    //     WordOffset offset;
    // } ParsedAddress deriving (Bits, Eq);
    //
// typedef Bit#(1) ParsedAddress;  // placeholder

typedef struct {
    Bit#(TSub#(addrBits, TAdd#(TAdd#(TLog#(numWords), numLogLines),TLog#(numBanks)))) tag;
    Bit#(numLogLines) index;
    Bit#(TLog#(numWords)) offset;
    Bit#(TLog#(numBanks)) bank;
} ParsedAddress#(numeric type addrBits, numeric type numWords, numeric type numLogLines, numeric type numBanks) deriving(Eq, Bits, FShow);

function ParsedAddress#(addrBits, numWords, numLogLines, numBanks) parseAddr(Bit#(addrBits) addr);
    let ret = ParsedAddress {
        offset: ?,
        bank: ?,
        index: addr[log2(valueOf(numWords))+valueOf(numLogLines)+log2(valueOf(numBanks))-1 : log2(valueOf(numWords))+log2(valueOf(numBanks))],
        tag: addr[valueOf(addrBits)-1 : log2(valueOf(numWords))+valueOf(numLogLines)+log2(valueOf(numBanks))]
    };
    if (valueOf(numWords) > 1) begin
        ret.offset = addr[log2(valueOf(numWords))-1 : 0];
    end
    if (valueOf(numBanks) > 1) begin
        ret.bank = addr[log2(valueOf(numWords))+log2(valueOf(numBanks))-1 : log2(valueOf(numWords))];
    end
    return ret;
endfunction

// and define whatever other types you may find helpful.


// Helper types for implementation (L2 cache):