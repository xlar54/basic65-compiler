10 print chr$(147);:print "test tier1a"
20 a=rnd(1):b=rnd(1)
30 if a>=0 then if a<1 then if b>=0 then if b<1 then print " rnd range ok"
40 if a=b then print "rnd repeat fail"
50 print " sqr9:";sqr(9)
60 print " sqr2:";sqr(2)
70 print " asc:";asc("a");asc("hi")
80 print tab(12);"t12"
90 print " pos:";:p=pos(0):print p
100 print spc(3);"s3"
110 print "tier1a done"
