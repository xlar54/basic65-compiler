10 print chr$(147);"gfx test"
20 graphic clr
30 screen 320,200,8
35 scnclr 6
40 pen 1
50 line 10,10,309,189
55 line 5,195,50,150,100,190,150,150
60 box 20,20,120,80
70 pen 5
80 box 140,20,240,80,1
90 pen 7
100 circle 160,130,40
110 pen 2
120 circle 260,130,30,1
130 ellipse 60,130,40,25
140 pen 4
150 paint 160,131
160 palette color 3,15,8,0
170 pen 3
180 box 250,150,300,190,1
182 pen 1
183 polygon 40,105,22,22,6
184 polygon 285,105,18,18,5,5,0,0,1
185 p1=pixel(160,131):p2=pixel(2,2):r=rpen(0)
190 for i=1 to 5000:next i
200 screen close
210 print "gfx done"
220 print "pixel in paint (want 4):";p1
230 print "pixel bg (want 6):";p2
240 print "rpen (want 1):";r
