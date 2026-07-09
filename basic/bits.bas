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
200 setbit $a002,6
210 h1=hasbit($a002,6)
220 clrbit $a002,6
230 h2=hasbit($a002,6)
240 setbit 262147,3
250 h3=hasbit(262147,3)
260 print "hasbit set (want-1):";h1
270 print "hasbit clr (want 0):";h2
280 print "hasbit flat (want-1):";h3
290 if h1=-1 and h2=0 and h3=-1 then print " hasbit ok"
