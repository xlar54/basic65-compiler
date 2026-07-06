10 print chr$(147);"test cursor"
20 cursor 10,5
30 rcursor x,y
40 cursor ,8
50 rcursor a,b
60 cursor 0,12
70 f=0
80 if x<>10 or y<>5 then f=1
90 if a<>10 or b<>8 then f=2
100 if f=0 then print "cursor ok":goto 120
110 print "cursor fail";f;x;y;a;b
120 print "cursor done"
