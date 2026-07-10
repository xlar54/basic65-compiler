10 print chr$(147);:print "line benchmark"
20 screen 320,200,4
30 clr ti
40 for i=1 to 300
50 pen int(rnd(1)*15)+1
60 line int(rnd(1)*320),int(rnd(1)*200),int(rnd(1)*320),int(rnd(1)*200)
70 next i
80 screen close
90 t=ti
100 print "300 random lines, 320x200"
110 print "render+return:";t;"seconds"
