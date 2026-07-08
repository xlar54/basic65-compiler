10 print chr$(147);"clip test"
20 graphic clr
30 screen 320,200,8
40 pen 1
50 line -10,-10,600,300
60 line 10,10,310,10
70 circle 160,100,250
80 box -50,50,400,120
90 circle 500,300,20
100 ellipse 160,100,400,300
110 polygon 160,100,300,300,6
120 p=pixel(400,300)
130 line 319,199
132 pen 2
134 box 260,150,310,190
136 pen 5
138 paint 285,170
139 q=pixel(285,170)
140 screen close
150 print "clip ok, pixel(want 0):";p
155 print "right-side paint (want 5):";q
160 print "ds:";ds$
