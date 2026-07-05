10 print chr$(147);:print "joystick demo - port 2, fire to exit"
20 for i=0 to 62:poke 1536+i,255:next i
30 poke 2040,24:poke 4088,24
40 sprite 0,1,7
50 x=160:y=140
60 do
70 j=joy(2)
80 d=j and 15
90 if d=8 or d=1 or d=2 then y=y-2
100 if d=4 or d=5 or d=6 then y=y+2
110 if d=2 or d=3 or d=4 then x=x+2
120 if d=6 or d=7 or d=8 then x=x-2
130 if x<24 then x=24
135 if x>320 then x=320
140 if y<50 then y=50
145 if y>229 then y=229
150 movspr 0,x,y
160 loop until j>127
170 sprite 0,0
180 print "joy demo done"
