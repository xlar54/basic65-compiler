10 print chr$(147);:print "boxfill benchmark"
20 screen 320,200,4
30 clr ti
40 for i=1 to 200
50 pen int(rnd(1)*15)+1
60 x=int(rnd(1)*280):y=int(rnd(1)*160)
70 box x,y,x+39,y+39,1
80 next i
90 t=ti
100 screen close
110 print "200 filled 40x40 boxes:";t;"seconds"
