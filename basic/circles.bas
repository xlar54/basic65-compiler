10 print chr$(147);:print "circle benchmark"
20 screen 640,200,4
30 clr ti
40 for i=1 to 100
50 pen int(rnd(1)*15)+1
60 x=int(rnd(1)*640):y=int(rnd(1)*200):r=int(rnd(1)*50)+3
70 circle x,y,r
80 next i
90 t=ti
100 screen close
110 print "100 circles, 640x200"
120 print "seconds:";t
