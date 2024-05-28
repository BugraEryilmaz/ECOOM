`include "Logging.bsv"

typedef Bit#(48) KonataId; 
typedef Bit#(8) ThreadId;

// function Action konataInit();
//     action 
//         $display("[KONATA]Kanata\t0004");
//         $display("[KONATA]C=\t1");
//     endaction
// endfunction


function Action konataTic(File f);
    action 
        $fdisplay(f, "C\t1");
    endaction
endfunction

function ActionValue#(KonataId) declareKonataInst(File f, Reg#(KonataId) konataCtr,ThreadId tid);
    `ifdef KONATA_LOG
    actionvalue
        konataCtr <= konataCtr + 1;
        $fdisplay(f,"I\t%d\t%d\t%d",konataCtr,konataCtr,tid);
        return konataCtr;
        endactionvalue
    `else 
        return ?;
    `endif
endfunction

function ActionValue#(KonataId) fetch1Konata(File f, Reg#(KonataId) konataCtr,ThreadId tid);
    // Include the declaration of the instr
    `ifdef KONATA_LOG
    actionvalue
        konataCtr <= konataCtr + 1;
        $fdisplay(f,"I\t%d\t%d\t%d",konataCtr,konataCtr,tid);
        $fdisplay(f,"S\t%d\t%d\t%s",konataCtr,0,"F");
        return konataCtr;
    endactionvalue
    `else 
        return ?;
    `endif
endfunction

function Action stageKonata(File f, KonataId konataCtr, String stage);
    `ifdef KONATA_LOG
    action
        // $display("E\t%d\t%d\t%s",konataCtr,0,"F");
        $fdisplay(f,"S\t%d\t%d\t%s",konataCtr,0,stage);
    endaction
    `else 
        return ?;
    `endif
endfunction

function ActionValue#(KonataId) nfetchKonata(File f, Reg#(KonataId) konataCtr,ThreadId tid, Integer k);
    // Return the first id of the consecutive k id allocated
    `ifdef KONATA_LOG
    actionvalue
        konataCtr <= konataCtr + fromInteger(k);
        for (Integer j = 0; j < k; j = j + 1) begin 
            $fdisplay(f,"S\t%d\t%d\t%s",konataCtr + fromInteger(j),0,"F");
        end
        return konataCtr;
    endactionvalue
    `else 
        return ?;
    `endif
endfunction

function Action decodeKonata(File f, KonataId konataCtr);
    `ifdef KONATA_LOG
    action
        // $display("E\t%d\t%d\t%s",konataCtr,0,"F");
        $fdisplay(f,"S\t%d\t%d\t%s",konataCtr,0,"D");
    endaction
    `else 
    action
    endaction
    `endif
endfunction

function Action executeKonata(File f, KonataId konataCtr);
    `ifdef KONATA_LOG
    action
        // $display("E\t%d\t%d\t%s",konataCtr,0,"D");
        $fdisplay(f,"S\t%d\t%d\t%s",konataCtr,0,"E");
    endaction
    `else 
    action
    endaction
    `endif
endfunction

function Action writebackKonata(File f, KonataId konataCtr);
    `ifdef KONATA_LOG
    action
        $fdisplay(f,"S\t%d\t%d\t%s",konataCtr,0,"W");
    endaction
    `else 
    action
    endaction
    `endif
endfunction

function Action squashKonata(File f, KonataId konataCtr);
    `ifdef KONATA_LOG
    action
        // Squash have id 0
        $fdisplay(f,"R\t%d\t%d\t%d", konataCtr, 0, 1);
    endaction
    `else 
    action
    endaction
    `endif
endfunction

function Action commitKonata(File f, KonataId konataCtr, Reg#(KonataId) konataCmt, Reg#(KonataId) oldCommit);
    `ifdef KONATA_LOG
    action
        konataCmt <= konataCmt + 1;
        oldCommit <= konataCtr;
        if (oldCommit - konataCtr > 2) begin
            $fdisplay(f, "$$ %d %d", oldCommit, konataCtr);
        end
//        $display("[KONATA]E\t%d\t%d\t%s",konataCtr,0,"W");
        $fdisplay(f,"R\t%d\t%d\t%d", konataCtr, konataCmt,0);
    endaction
    `else 
        action
        endaction
    `endif
endfunction

function Action labelKonataLeft(File f, KonataId konataCtr, Fmt s);
    `ifdef KONATA_LOG
    action
        // Squash have id 0
        $fdisplay(f, "L\t%d\t%d\t", konataCtr, 0, s);
    endaction
    `else 
        action
        endaction
    `endif
endfunction

function Action labelKonataMouse(File f, KonataId konataCtr, Fmt s);
    `ifdef KONATA_LOG
    action
        // Squash have id 0
        $fdisplay(f, "L\t%d\t%d\t", konataCtr, 1, s);
    endaction
    `else 
        action
        endaction
    `endif
endfunction



