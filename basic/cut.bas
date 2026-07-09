10 print chr$(147);"cut test"
20 screen 320,200,2
30 box 60,60,300,180,1
40 pen 2
50 cut 140,80,40,40
60 paste 10,10
70 p1 = pixel(150,90)
80 p2 = pixel(15,15)
90 p3 = pixel(5,5)
92 gcopy 70,70,10,10
94 cut 200,20,0,5
96 paste 5,100
98 p4=pixel(5,100):p5=pixel(200,20):p6=pixel(12,105)
100 screen close
110 print "cut:";p1;p2;p3;" deg:";p4;p5;p6
120 if p1=2 and p2=1 and p3=0 and p4=0 and p5=0 and p6=0 then print "cut ok"
