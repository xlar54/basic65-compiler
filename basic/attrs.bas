10 print chr$(147);:print "test screen attrs"
20 border 4
30 if peek($d020)=4 then print " border ok"
40 background 6
50 if peek($d021)=6 then print " background ok"
60 foreground 3
70 print " this line is cyan"
80 color 5
90 print " this line is green"
100 foreground 1
110 chardef 62,$ff,$81,$81,$81,$81,$81,$81,$ff
120 print " boxes: >>><<<"
130 print " (greater-thans should draw as boxes)"
140 border 6:background 6
150 print "attrs done"
