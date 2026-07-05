10 print chr$(147);:print "test sound"
20 vol 15
30 print " c major up:"
40 sound 1,4291,25
50 for j=1 to 2:for i=1 to 30000:next i:next j
60 sound 1,5407,25
70 for j=1 to 2:for i=1 to 30000:next i:next j
80 sound 1,6430,25
90 for j=1 to 2:for i=1 to 30000:next i:next j
100 sound 2,8583,40,0,0,0,1
110 sound 4,4291,40,0,0,0,2,2048
120 for j=1 to 2:for i=1 to 30000:next i:next j
130 sound 3,4000,120,2,2000,400,1
140 for j=1 to 4:for i=1 to 30000:next i:next j
150 print " played ok"
160 vol 0
170 print "sound done"
