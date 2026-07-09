10 print chr$(147);:print "test loops"
20 n=0:print " loop until:";:do:n=n+1:print n;:loop until n=3:print
30 n=3:print " do while:";:do while n>0:print n;:n=n-1:loop:print
40 n=0:do:n=n+1:if n=2 then print " loop if ok":loop until n=2
50 n=0:do until n=2:n=n+1:loop:print " do until ok";n
60 n=0:print " exit:";:do:n=n+1:if n=3 then exit : else print n;:loop:print " ok";n
70 print " exit for:";:for f=1 to 5:if f=3 then goto 90
80 print f;:next f
90 print " ok";f
100 f9=0:for f=1 to 5:f9=f9+f:next f
110 g9=0:for g=5 to 1 step -2:g9=g9+g:next g
120 if f9=15 and g9=9 then print " for sums ok" : else print "for sums fail";f9;g9
130 print "loops done"
