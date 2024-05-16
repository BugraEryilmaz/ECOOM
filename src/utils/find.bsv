import Vector::*;

function Maybe#(UInt#(TLog#(size))) find(a x, Vector#(size, a) v) provisos(
        Eq#(a), 
        Add#(4, a__, size),
        Add#(b__, 2, TLog#(size))
        );
    Maybe#(UInt#(TLog#(size))) ret = tagged Invalid;

    let size4 = valueOf(size)/4;
    Vector#(TDiv#(size, 2), Maybe#(UInt#(TLog#(size)))) v1 = replicate(tagged Invalid);
    for (Integer i = 0; i < size4; i = i + 1) begin
        Vector#(4, a) vLoop = takeAt(fromInteger(i)*4, v);
        if (findElem(x, vLoop) matches tagged Valid .idx) begin
            v1[size4+i] = tagged Valid (fromInteger(i)*4 + zeroExtend(idx));
        end
        else begin
            v1[size4+i] = tagged Invalid;
        end
    end
    for (Integer i = size4-1; i >= 1; i = i - 1) begin
        if (v1[2*i] matches tagged Valid .idx) begin
            v1[i] = tagged Valid idx;
        end else if (v1[2*i+1] matches tagged Valid .idx) begin
            v1[i] = tagged Valid idx;
        end else begin
            v1[i] = tagged Invalid;
        end
    end
    
    return v1[1];
endfunction