10 print chr$(147);"dbl buffer test"
20 graphic clr
30 screen 320,200,8
40 pen 2
50 box 10,10,60,60,1
60 screen def 1,0,0,8
70 screen open 1
80 screen set 1,0
90 pen 5
100 box 20,20,80,80,1
110 p1=pixel(30,30)
120 screen set 1,1
130 p2=pixel(30,30)
140 for i=1 to 3000:next i
150 screen set 0,0
160 p3=pixel(30,30)
170 for i=1 to 3000:next i
180 screen clr 6
190 p4=pixel(30,30)
200 screen close
210 print "draw on 1 (want 5):";p1
220 print "view 1 (want 5):";p2
230 print "back to 0 (want 2):";p3
240 print "after clr (want 6):";p4
250 if p1=5 and p2=5 and p3=2 and p4=6 then print "dbl ok"
