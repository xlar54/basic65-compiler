10 print chr$(147);:print "bench int loop"
20 print "running..."
30 poke $d020,2
40 s=0
50 for r=1 to 100
60 for i=1 to 200
70 s=s+i-r
80 if s>20000 then s=s-20000
90 if s<-20000 then s=s+20000
100 next i
110 next r
120 poke $d020,6
130 print "bench done";s
