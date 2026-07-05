10 print chr$(147);:print "test sprite"
20 sprite 0,1,3
30 movspr 0,100,80
40 if peek(53248)=100 and peek(53249)=80 then print " pos ok"
50 sprite 1,1,4,1,1,1,1
60 movspr 1,300,60
70 m=peek(53264) and 2:if m=2 then print " msb ok"
80 if peek(53287)=3 and peek(53288)=4 then print " color ok"
90 m=peek(53269) and 3:if m=3 then print " enable ok"
100 m=peek(53277) and 2:n=peek(53271) and 2:if m=2 and n=2 then print " exp ok"
110 m=peek(53276) and 2:if m=2 then print " mode ok"
120 sprcolor 5,6
130 if peek(53285)=5 and peek(53286)=6 then print " mc ok"
140 sprite 1,,7
150 m=peek(53269) and 2:if peek(53288)=7 and m=2 then print " slot ok"
160 j=joy(1)
170 print " joy";j
180 b=bump(1)
190 print " bump";b
200 sprite 0,0:sprite 1,0
210 m=peek(53269) and 3:if m=0 then print " off ok"
220 print "sprite done"
