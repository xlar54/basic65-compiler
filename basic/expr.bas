10 print chr$(147);:print "test expr"
20 a=1+2*3:b=a-4
30 c=(a+b)*2:d=c/5:e=-d+10
40 print "a=",a," b=",b," c=",c," d=",d," e=",e
50 if a=7 then 70
60 print "if equality failed":end
70 if b<>4 then 90
80 print "if not-equal failed":end
90 if a<>7 then print "false if failed":print "compound false failed"
100 if b<4 then print "lt ok":print " compound:if ok"
110 if c>19 then print " gt ok"
120 if d<=4 then print " le ok"
130 if e>=6 then print " ge:ok"
140 if a=7 then if e=6 then print " nested:ok"
145 if abs(-5)=5 and abs(5)=5 and abs(0)=0 then print " abs ok" : else print "abs fail"
146 if sgn(-7)=-1 and sgn(0)=0 and sgn(9)=1 then print " sgn ok" : else print "sgn fail"
147 if int(-7)=-7 and int(9)=9 then print " int ok" : else print "int fail"
150 print "expr done"
