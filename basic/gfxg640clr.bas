10 print chr$(147);:print "test 640 graphic clr background"
20 graphic clr
30 screen def 1,1,1,2
40 screen open 1
50 screen set 1,1
60 palette 1,0,0,0,0
70 palette 1,1,0,15,0
80 scnclr 0
90 pen 0,1
100 line 50,100,590,100
110 b=peek($d021)
120 p1=pixel(320,100):p0=pixel(10,10)
125 getkey a$
130 screen close 1
140 print " d021:";b;" line:";p1;" bg:";p0
150 if b=0 and p1=1 and p0=0 then print "g640clr ok"
