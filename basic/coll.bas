10 print chr$(147);:print "test collision"
20 c=0
30 for i=0 to 62:poke 1536+i,255:next i
40 poke 2040,24:poke 2041,24:poke 4088,24:poke 4089,24
50 collision 1,200
60 sprite 0,1,3:sprite 1,1,7
70 movspr 1,180,120
80 for x=60 to 300 step 2
90 movspr 0,x,120
100 sleep 0.02
105 if c>0 then goto 120
110 next x
120 if c>0 then print " collision ok";c
130 collision 1
140 sprite 0,0:sprite 1,0
150 b=bump(1)
160 print "collision done"
170 end
200 c=c+1:return
