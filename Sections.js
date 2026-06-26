.pragma library

// John Deere section labelling for a bar read left -> right from the driver's
// forward perspective: a centre section "C" for odd counts, then R1,R2,...
// increasing to the RIGHT and L1,L2,... increasing to the LEFT. Even counts have
// no centre (L(n/2)..L1 R1..R(n/2)). Index 0 is the left-most section.
function label(index, count) {
    if (count <= 1)
        return "C";
    if (count % 2 === 1) {
        var c = (count - 1) / 2;          // centre index
        if (index === c) return "C";
        if (index > c)   return "R" + (index - c);
        return "L" + (c - index);
    }
    var half = count / 2;                 // left half = indices 0 .. half-1
    if (index >= half) return "R" + (index - half + 1);
    return "L" + (half - index);
}
