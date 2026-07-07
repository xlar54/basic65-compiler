10 print chr$(147);:print "test dma"
20 edma 3,256,65,$a000
30 if peek($a000)=65 and peek($a0ff)=65 then print " fill ok" : else print "fill fail";peek($a000)
40 edma 0,128,$a000,$a100
50 if peek($a100)=65 and peek($a17f)=65 then print " copy ok" : else print "copy fail"
60 edma 3,16,66,262144
70 edma 0,16,262144,$a200
80 if peek($a200)=66 then print " far ok" : else print "far fail";peek($a200)
90 dma 3,32,67,0,$a300,0
100 if peek($a300)=67 then print " dma ok" : else print "dma fail";peek($a300)
110 print "dma done"
