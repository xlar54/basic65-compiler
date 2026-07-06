10 print chr$(147);:print "test collision"
20 c=0
30 for i=0 to 62:poke 1536+i,255:next i
40 poke 2040,24:poke 2041,24:poke 4088,24:poke 4089,24
50 collision 1,200
60 sprite 0,1,3:sprite 1,1,4
70 movspr 0,100,100:movspr 1,100,100
80 sleep 0.5
90 if c>0 then print " collision ok";c
100 collision 1
110 sprite 0,0:sprite 1,0
120 b=bump(1)
130 print "collision done"
140 end
200 c=c+1:return
