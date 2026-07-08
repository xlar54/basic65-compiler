10 print chr$(147);"bench2"
20 t0=ti
30 s=0
40 for r=1 to 2000
50 for i=1 to 200
60 s=s+i-r
70 if s>20000 then s=s-20000
80 if s<-20000 then s=s+20000
90 next i
100 next r
110 print "jiffies:";ti-t0;" s:";s
