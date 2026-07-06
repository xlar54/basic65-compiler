10 print chr$(147);:print "collision probe"
20 c=0
30 for i=0 to 62:poke 1536+i,255:next i
40 poke 2040,24:poke 2041,24:poke 4088,24:poke 4089,24
50 sprite 0,1,3:sprite 1,1,7
60 movspr 0,160,120:movspr 1,160,120
70 collision 1,200
80 sleep 0.5
90 print "acc:";bump(1)
100 print "c:";c
110 print "pending seen:";pk
120 collision 1
130 sprite 0,0:sprite 1,0
140 print "probe done"
150 end
200 c=c+1:pk=1:return
