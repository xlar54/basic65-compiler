10 print chr$(147);:print "circle benchmark"
20 screen 320,200,4
30 clr ti
40 pen 1
50 char 2,2,1,1,2,"500 circles"
60 for i=1 to 500
70 pen int(rnd(1)*15)+1
80 x=int(rnd(1)*320):y=int(rnd(1)*200):r=int(rnd(1)*50)+3
90 circle x,y,r
100 next i
110 screen close
120 t=ti
130 print "500 circles, 320x200"
140 print "render+return:";t;"seconds"
