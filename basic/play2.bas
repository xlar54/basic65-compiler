10 print chr$(147);:print "test play2"
20 vol 15
30 tempo 30
40 envelope 9,10,5,10,5,2,4000
50 play "t9o4qcdef"
60 if rplay(1)=1 then print " rplay on ok"
70 for j=1 to 8:for i=1 to 30000:next i:next j
80 if rplay(1)=0 then print " rplay off ok"
90 tempo 10
100 play "t8o3qcec"
110 for j=1 to 8:for i=1 to 30000:next i:next j
120 play
130 print "play2 done"
