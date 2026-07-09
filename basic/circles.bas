10 print chr$(147);:print "circle benchmark"
20 screen 320,200,4
30 clr ti
40 for i=1 to 500
50 pen int(rnd(1)*15)+1
60 x=int(rnd(1)*320):y=int(rnd(1)*200):r=int(rnd(1)*50)+3
70 circle x,y,r
80 next i
90 t=ti
100 pen 1
110 char 2,2,1,1,2,"500 circles"
120 for i=1 to 12000:next i
130 screen close
140 print "500 circles, 320x200"
150 print "seconds:";t
