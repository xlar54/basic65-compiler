10 print chr$(147);:print "test bits"
20 poke $a000,0
30 setbit $a000,4
40 if peek($a000)=16 then print " set ok" : else print "set fail";peek($a000)
50 setbit $a000,0
60 clrbit $a000,4
70 if peek($a000)=1 then print " clr ok" : else print "clr fail";peek($a000)
80 setbit 262145,7
90 bank 4
100 v=peek(1)
110 bank 128
120 if v>=128 then print " flat ok" : else print "flat fail";v
130 print "bits done"
