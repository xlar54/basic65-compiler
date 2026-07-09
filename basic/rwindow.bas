10 print chr$(147);"rwindow test"
20 c=rwindow(2):r=rwindow(3)
30 w0=rwindow(0):h0=rwindow(1)
40 window 5,5,20,10
50 w=rwindow(0):h=rwindow(1)
60 print chr$(19);chr$(19);chr$(147);
70 print "cols/rows:";c;r
80 print "full w/h:";w0;h0
90 print "window w/h (want 16 6):";w;h
100 if w=16 and h=6 and w0=c and h0=r then print "rwindow ok"
