10 print chr$(147);:print "test filter"
20 vol 15
30 filter 1,1000,1,0,0,12
40 play "t7o3x1qcl"
50 print " sweeping";
60 for f=100 to 1900 step 100
70 filter 1,f
80 for i=1 to 8000:next i
90 next f
100 play "x0"
110 for i=1 to 20000:next i
120 play
130 print " done"
140 print "filter done"
