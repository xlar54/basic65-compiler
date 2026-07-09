10 print chr$(147);"gcopy/paste"
20 graphic clr
30 screen 320,200,2
40 pen 1
50 box 60,60,300,180,1
60 pen 2
70 box 150,90,170,110,1
80 gcopy 140,80,40,40
90 paste 10,10
100 p1=pixel(30,30)
110 p2=pixel(15,15)
120 p3=pixel(5,5)
130 for i=1 to 4000:next i
140 screen close
150 print "pasted red (want 2):";p1
160 print "pasted white (want 1):";p2
165 gcopy 0,0,200,200
166 paste 290,5
168 p4=pixel(300,10)
170 print "outside (want 0):";p3
175 print "over-budget paste is no-op (want 0):";p4
180 if p1=2 and p2=1 and p3=0 and p4=0 then print "gcopy ok"
