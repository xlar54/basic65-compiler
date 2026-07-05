10 print chr$(147);:print "test floats"
20 f=1.5:g=-2.25:h=.75
30 print " floats:";f;g;h
40 print " literal:";3.75
50 f=7:print " int reuse:";f
60 f=1.25:print " float reuse:";f
100 a=1.5:b=-2.25
110 d=a+b:print " add:";d
120 d=a*4:print " muli:";d
130 d=b/1.5:print " div:";d
140 d=1.0/3:print " third:";d
150 e%=7:d=e%+.5:print " mix:";d
160 if a>b then print " cmp ok"
170 if a+b<0 then print " neg ok"
180 d=int(2.7):print " int:";d
190 d=abs(b):print " abs:";d
200 d=sgn(b):print " sgn:";d
210 d=(a+h)*2:print " paren:";d
220 print "floats done"
