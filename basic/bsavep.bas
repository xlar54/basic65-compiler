10 print chr$(147);:print "test bsave p(expr)"
20 scratch "bspdat"
30 poke 4096,7:poke 4100,9
40 a=4096:b=4101
50 bsave "bspdat",p(a) to p(b)
60 print " saved, ds:";ds
70 poke 4096,0
80 bload "bspdat",p(a)
90 print " loaded, ds:";ds
100 if peek(4096)=7 and peek(4100)=9 then print "bsave pexpr ok" : else print "bsave pexpr fail";peek(4096);peek(4100)
110 scratch "bspdat"
