10 print chr$(147);:print "test strarrgc"
20 dim x(5),y(2,3)
30 x(0)=10:x(1)=20:x(2)=x(0)+x(1):x(5)=55
40 y(1,2)=x(2)+7:y(2,3)=99
50 restore 2300:read r,s,t,u
60 restore 2310:read a$,b$,c$
70 dim ds$(1):restore 2310:read ds$(0),ds$(1)
80 input "enter 42,-3,12345";n,m,q$
82 dim ia(1),is$(1)
84 input "enter 7,hi,8,ok";ia(0),is$(0),ia(1),is$(1)
100 dim sa$(4),sb$(1,2)
110 for i=0 to 4:sa$(i)="item"+str$(i):next
120 sb$(0,0)=sa$(1):sb$(0,1)=sa$(2)+"x"
130 sb$(1,0)=left$(sa$(3),4):sb$(1,1)=right$(sa$(4),2)
140 for j=1 to 6000
150 t$="trash"+str$(j)
160 u$=left$(t$,3)+right$(t$,2)
170 next j
180 f=0
190 if sa$(0)<>"item 0" then f=1
200 if sa$(2)<>"item 2" then f=3
205 if sb$(0,0)<>"item 1" then f=6
210 if sb$(0,1)<>"item 2x" then f=7
220 if sb$(1,1)<>" 4" then f=9
230 if ds$(0)<>"red" then f=10
232 if q$<>"12345" then f=11
234 if is$(0)<>"hi" then f=12
240 if f=0 then print " roots ok":goto 260
250 print " roots fail";f;" [";sb$(0,0);"]"
260 print "strarrgc done"
2300 data 11,22,-3,42
2310 data "red","green","blue"
