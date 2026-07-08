10 print chr$(147);"rcolor test"
20 poke $d020,5:poke $d021,11
30 print chr$(5);
40 b=rcolor(3):g=rcolor(0):t=rcolor(1):h=rcolor(2)
50 print "border (want 5):";b
60 print "bg (want 11):";g
70 print "text (want 1):";t
80 print "highlight:";h
90 poke $d020,14:poke $d021,6
100 if b=5 and g=11 and t=1 then print "rcolor ok"
