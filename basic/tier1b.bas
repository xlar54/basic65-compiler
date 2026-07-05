10 print chr$(147);:print "test tier1b"
20 a=12:b=10
30 c=a and b:print " and:";c
40 c=a or 3:print " or:";c
50 c=a>b:print " gt:";c
60 c=2 and 4:print " bit0:";c
70 if a and 4 then print " ifbit ok"
80 if a and 2 then print "ifbit2 fail"
90 f=1.5:c=f>1:print " fcmp:";c
100 if not(b>a) then print " not ok"
110 if not(a>b) then print "not fail"
120 if f then print " ftruth ok"
130 print " mixand:";f>1 and a>b
140 print "tier1b done"
