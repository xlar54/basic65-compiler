10 print chr$(147);:print "test mem"
20 poke $d020,2
30 v=peek($d020)
40 if v=2 then print " peek/poke ok" : else print "peek/poke fail";v
50 wpoke $3000,$1234
60 w=wpeek($3000)
70 if w=$1234 then print " wpeek/wpoke ok" : else print "wpeek/wpoke fail";w
80 poke $3002,peek($3000)
90 if peek($3002)=$34 then print " peek expr ok" : else print "peek expr fail";peek($3002)
100 poke $d020,6
110 print "mem done"
