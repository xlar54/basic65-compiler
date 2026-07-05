10 print chr$(147);:print "mouse demo - click a button to exit"
20 mouse on,1,0
30 do
40 rmouse x,y,b
50 loop until b>0
60 print " clicked at";x;y;" button";b
70 mouse off
80 rmouse x,y,b
90 if x=-1 and y=-1 and b=-1 then print "ok"
100 print "mouse done"
