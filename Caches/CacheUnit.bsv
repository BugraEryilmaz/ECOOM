// Cache Unit

import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector :: * ;

interface CacheUnit#(numeric type dataBits, type cuStatus, numeric type addrBits, numeric type numWords, numeric type numLogLines);
    method Action req(CUCacheReq#(addrBits, dataBits) r);
    method ActionValue#(CacheUnitResp#(Bit#(dataBits), CUTag#(addrBits, numWords, numLogLines, 1), cuStatus, numWords)) res();
    method Action update(TaggedLine#(Bit#(dataBits), CUTag#(addrBits, numWords, numLogLines, 1), cuStatus, numWords) newLine, Bit#(numLogLines) lineNum);
endinterface

module mkCacheUnit(CacheUnit#(dataBits, cuStatus, addrBits, numWords, numLogLines)) 
                provisos (
                    Bits#(cuStatus, cuStatusBits), 
                    Valid#(cuStatus), Dirty#(cuStatus),
                    Mul#(TDiv#(dataBits, TDiv#(dataBits, 8)), TDiv#(dataBits, 8), dataBits)
                    // Mul#(TDiv#(dataBits, 4), 4, dataBits)
                );
    BRAM_Configure cfg = defaultValue;
    cfg.memorySize = 0; // makes it largest possible, i.e. 2^numLogLines
    String filename = "zero" + integerToString(2**valueOf(numLogLines)) + ".vmh";
    cfg.loadFormat = tagged Binary filename;  // zero out for you

    BRAM2Port#(Bit#(numLogLines), CUTag#(addrBits, numWords, numLogLines, 1)) tagCache <- mkBRAM2Server(cfg);
    BRAM2Port#(Bit#(numLogLines), cuStatus) statusCache <- mkBRAM2Server(cfg);
    Vector#(numWords, BRAM2PortBE#(Bit#(numLogLines), Bit#(dataBits), TDiv#(dataBits, 8))) dataCache <- replicateM(mkBRAM2ServerBE(cfg));

    FIFO#(CUCacheReq#(addrBits, dataBits)) reqFIFO <- mkFIFO;
    method Action req(CUCacheReq#(addrBits, dataBits) r);
        ParsedAddress#(addrBits, numWords, numLogLines, 1) parsedAddress = parseAddr(r.addr);
        let index = parsedAddress.index;
        let offset = parsedAddress.offset;

        // Send read requests to all the BRAMs
        tagCache.portA.request.put(BRAMRequest{write: False, responseOnWrite: False, address: index, datain: ?});
        statusCache.portA.request.put(BRAMRequest{write: False, responseOnWrite: False, address: index, datain: ?});
        for (Integer i = 0; i < valueOf(numWords); i = i + 1)
            dataCache[i].portA.request.put(BRAMRequestBE{writeen: 0, responseOnWrite: False, address: index, datain: ?});
        reqFIFO.enq(r);
    endmethod

    method ActionValue#(CacheUnitResp#(Bit#(dataBits), CUTag#(addrBits, numWords, numLogLines, 1), cuStatus, numWords)) res();
        CacheUnitResp#(Bit#(dataBits), CUTag#(addrBits, numWords, numLogLines, 1), cuStatus, numWords) resp = ?;
        let req = reqFIFO.first;
        reqFIFO.deq;
        ParsedAddress#(addrBits, numWords, numLogLines, 1) parsedAddress = parseAddr(req.addr);
        let index = parsedAddress.index;
        let tag = parsedAddress.tag;
        let offset = parsedAddress.offset;

        let tagResp <- tagCache.portA.response.get;
        let statusResp <- statusCache.portA.response.get;
        Vector#(numWords, Bit#(dataBits)) dataResp;
        for (Integer i = 0; i < valueOf(numWords); i = i + 1)
            dataResp[i] <- dataCache[i].portA.response.get;

        if (isValid(statusResp) && tagResp == tag && req.writeEn == 0) begin
            // Load Hit
            resp.hitMiss = LDHIT;
            resp.ldData = dataResp[offset];
            // not needed debug info
            resp.missLine.words = dataResp;
            resp.missLine.tag = tagResp;
            resp.missLine.status = statusResp;
        end else if (isValid(statusResp) && tagResp == tag && req.writeEn != 0) begin
            // Store Hit
            let newStatus = makeDirty(statusResp);
            // update status to be dirty and update the data
            statusCache.portB.request.put(BRAMRequest{write: True, responseOnWrite: False, address: index, datain: newStatus});
            resp.missLine.words = dataResp;
            dataCache[offset].portB.request.put(BRAMRequestBE{writeen: req.writeEn, responseOnWrite: False, address: index, datain: req.data});
            resp.hitMiss = STHIT;
            // not needed debug info
            resp.missLine.words = dataResp;
            resp.missLine.tag = tagResp;
            resp.missLine.status = statusResp;
        end else begin
            // Miss
            resp.hitMiss = MISS;
            resp.missLine.words = dataResp;
            resp.missLine.tag = tagResp;
            resp.missLine.status = statusResp;
        end
        return resp;
    endmethod

    method Action update(TaggedLine#(Bit#(dataBits), CUTag#(addrBits, numWords, numLogLines, 1), cuStatus, numWords) newLine, Bit#(numLogLines) lineNum);
        // Send write requests to all the BRAMs without checking
        tagCache.portB.request.put(BRAMRequest{write: True, responseOnWrite: False, address: lineNum, datain: newLine.tag});
        statusCache.portB.request.put(BRAMRequest{write: True, responseOnWrite: False, address: lineNum, datain: newLine.status});
        for (Integer i = 0; i < valueOf(numWords); i = i + 1)
            dataCache[i].portB.request.put(BRAMRequestBE{writeen: ~0, responseOnWrite: False, address: lineNum, datain: newLine.words[i]});
    endmethod
endmodule