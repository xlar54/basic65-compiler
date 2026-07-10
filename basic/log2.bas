10 print chr$(147);:print "test log2"
20 a=log2(1):c=log2(4):d=log2(2)
30 e=log2(0.5):f=log2(0.25)
40 b=log2(5)
50 print " ints:";c;d;a;e;f
60 print " l5:";b
70 ok=1
80 if abs(a)>0.0001 then ok=0
90 if abs(c-2)>0.0001 or abs(d-1)>0.0001 then ok=0
100 if abs(e+1)>0.0001 or abs(f+2)>0.0001 then ok=0
110 if abs(b-2.3219281)>0.0001 then ok=0
120 if ok=1 then print "log2 ok" : else print "log2 fail"
