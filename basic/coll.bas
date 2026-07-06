10 print chr$(147);:print "test collision"
20 c=0
30 for i=0 to 62:poke 1536+i,255:next i
40 poke 2040,24:poke 2041,24:poke 4088,24:poke 4089,24
50 collision 1,200
60 sprite 0,1,3:sprite 1,1,7
70 movspr 0,60,120:movspr 1,260,120
80 movspr 0,90#2:movspr 1,270#2
90 clr ti
100 do:sleep 0.1:loop until c>0 or ti>5
110 if c>0 then print " collision ok";c
120 collision 1
130 sprite 0,0:sprite 1,0
140 b=bump(1)
150 print "collision done"
160 end
200 movspr 0,rsppos(0,0),rsppos(0,1):movspr 1,rsppos(1,0),rsppos(1,1)
210 c=c+1:return
