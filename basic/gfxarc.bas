10 print chr$(147);"arc test"
20 graphic clr
30 screen 320,200,8
40 pen 1
50 ellipse 160,100,80,50,0,0,90
60 pen 2
70 ellipse 160,100,60,35,2,90,180
80 pen 5
90 circle 60,60,40,1,0,120
100 pen 7
110 circle 260,60,30,0,180,270
120 p1=pixel(200,100)
130 p2=pixel(130,100)
140 p3=pixel(74,80)
150 p4=pixel(268,40)
160 for i=1 to 4000:next i
170 screen close
180 print "leg on 3 o'clock (want 1):";p1
190 print "suppressed leg (want 0):";p2
200 print "pie interior (want 5):";p3
210 print "outside arc (want 0):";p4
220 if p1=1 and p2=0 and p3=5 and p4=0 then print "arc ok"
