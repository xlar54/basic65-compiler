10 a=1+2*3:b=a-4
15 c=(a+b)*2:d=c/5:e=-d+10
20 print "a=",a," b=",b," c=",c," d=",d," e=",e:poke $d020,e
30 if a=7 then 60
40 print "if equality failed"
50 end
60 if b<>4 then 90
70 print "if not-equal failed"
80 end
90 if a<>7 then print "false if failed":print "compound false failed"
100 if b<4 then print "lt ok":print " compound:if ok"
110 if c>19 then print " gt ok"
120 if d<=4 then print " le ok"
130 if e>=6 then print " ge:ok"
140 if a=7 then if e=6 then print " nested:ok"
145 data "skip:this":print " data:colon ok"
150 print " for:";:for i=1 to 5:print i;:next i:print
160 print " rev:";:for j=5 to 1 step -2:print j;:next j:print
170 dim x(5),y(2,3)
180 x(0)=10:x(1)=20:x(2)=x(0)+x(1):x(5)=55
190 y(1,2)=x(2)+7:y(2,3)=99
200 print " arr:";x(0);x(1);x(2);y(1,2);x(5);y(2,3)
205 data 11,22,-3,$2a
210 read r,s,t,u
215 print " data:";r;s;t;u
220 restore:read r,s
225 print " restore:";r;s
230 end
