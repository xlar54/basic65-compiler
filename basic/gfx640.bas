10 print chr$(147);"640 test"
20 graphic clr
30 screen 640,200,8
40 pen 3
50 box 400,50,600,150,1
60 pen 7
70 line 0,0,639,199
80 p1=pixel(500,100)
90 p2=pixel(639,199)
100 p3=pixel(10,150)
110 pen 5
120 circle 320,100,80,1
130 p4=pixel(320,100)
140 for i=1 to 4000:next i
150 screen close
160 print "box right half (want 3):";p1
170 print "line end (want 7):";p2
180 print "empty (want 0):";p3
190 print "circle mid (want 5):";p4
200 if p1=3 and p2=7 and p3=0 and p4=5 then print "640 ok"
