10 print chr$(147);"bank probe"
20 bank 4
30 poke $9000,111
40 print "b4 rd:";peek($9000)
50 bank 5
60 print "b5 blob:";peek(0);peek(1)
70 bank 128
80 print "done"
90 end
100 graphic clr
