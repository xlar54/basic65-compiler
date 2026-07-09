10 print chr$(147);"cut test"
20 screen 320,200,2
30 box 60,60,300,180,1
40 pen 2
50 cut 140,80,40,40
60 paste 10,10
70 p1 = pixel(150,90)
80 p2 = pixel(15,15)
90 p3 = pixel(5,5)
100 screen close
110 print "cut:";p1;p2;p3
120 if p1=2 and p2=1 and p3=0 then print "cut ok"
