10 print chr$(147);:print "test data"
20 print " data:strict ok"
30 print " for:";:for i=1 to 5:print i;:next i:print
40 print " rev:";:for j=5 to 1 step -2:print j;:next j:print
50 dim x(5),y(2,3)
60 x(0)=10:x(1)=20:x(2)=x(0)+x(1):x(5)=55
70 y(1,2)=x(2)+7:y(2,3)=99
80 print " arr:";x(0);x(1);x(2);y(1,2);x(5);y(2,3)
90 restore 300:read r,s,t,u
100 print " data:";r;s;t;u
110 restore 300:read r,s
120 print " restore:";r;s
130 restore 310:read a$,b$,c$
140 print " sdata:";a$;b$;c$
150 dim ds$(1):restore 310:read ds$(0),ds$(1)
160 if ds$(0)="red" and ds$(1)="green" then print " sdata arr ok" : else print "sdata arr fail";ds$(0);ds$(1)
170 print "data done"
180 end
300 data 11,22,-3,42
310 data "red","green","blue"
