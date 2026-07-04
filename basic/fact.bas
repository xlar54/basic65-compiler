10 print chr$(147);:print "bench factorials"
20 print "running..."
30 poke $d020,2
40 dim f(7)
50 for r=1 to 300
60 f(0)=1
70 for n=1 to 7
80 f(n)=f(n-1)*n
90 next n
100 next r
110 poke $d020,6
120 print "7!=";f(7)
130 if f(7)=5040 then print " factorial ok" : else print "factorial fail";f(7)
