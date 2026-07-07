10 print chr$(147);:print "test window"
20 window 10,5,70,20
30 print "a";
40 v=t@&(10,5)
50 print chr$(19);chr$(19);
60 cursor 0,22
70 if v=1 then print "window ok" : goto 90
80 print "window fail";v
90 print "window done"
