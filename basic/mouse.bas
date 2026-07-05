10 print chr$(147);:print "test mouse"
20 mouse on,1,2,160,100
30 rmouse x,y,b
40 if x=160 and y=100 then print " rmouse pos ok"
50 if b>=0 then print " rmouse btn ok";b
60 mouse off
70 rmouse x,y,b
80 if x=-1 and y=-1 and b=-1 then print " off ok"
90 print "mouse done"
