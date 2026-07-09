10 print chr$(147);"viewport test"
20 screen 320,200,2
30 viewport def 20,30,100,120
40 pen 1
50 viewport clr
55 v1=pixel(20,30):v2=pixel(119,149):v3=pixel(19,30):v4=pixel(120,30)
60 pen 2
70 line 0,100,319,100
80 box 0,60,319,80,1
90 pen 3
100 paint 60,120
110 viewport def 0,0,320,200
115 pen 2
120 line 0,10,319,10
140 l0=pixel(50,100):l1=pixel(10,100):l2=pixel(200,100)
150 b1=pixel(50,70):b2=pixel(5,70):b3=pixel(300,70)
160 p1=pixel(60,120):p2=pixel(10,145):p3=pixel(60,90)
170 r1=pixel(200,10)
180 screen close
190 print "vp:";v1;v2;v3;v4
200 print "ln:";l0;l1;l2;" bx:";b1;b2;b3
210 print "pt:";p1;p2;p3;" rs:";r1
220 if v1=1 and v2=1 and v3=0 and v4=0 then if l0=2 and l1=0 and l2=0 and b1=2 and b2=0 and b3=0 then if p1=3 and p2=0 and p3=1 and r1=2 then print "viewport ok"
