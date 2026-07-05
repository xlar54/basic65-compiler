10 print chr$(147);:print "test tier1d"
20 a=5
30 if a>3 then begin
40 print " blk1"
50 print " blk2"
60 bend
70 if a>9 then begin
80 print "blkskip fail"
90 bend
100 print " after ok"
110 if a>3 then begin:print " inline";
120 print " tail"
130 bend
140 if a>3 then begin
150 if a>4 then print " nested ok"
160 bend
170 print "tier1d done"
