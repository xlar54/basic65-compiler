10 print chr$(147);"box4 test"
20 graphic clr
30 screen 320,200,8
40 pen 3
50 box 160,20,240,60,160,100,80,60,1
60 pen 5
70 box 20,120,100,120,120,180,40,180
80 p1=pixel(160,60)
90 p2=pixel(60,120)
100 p3=pixel(300,150)
110 for i=1 to 4000:next i
120 screen close
130 print "diamond centre (want 3):";p1
140 print "path top edge (want 5):";p2
150 print "empty (want 0):";p3
160 if p1=3 and p2=5 and p3=0 then print "box4 ok"
