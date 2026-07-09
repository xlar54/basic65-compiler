10 print chr$(147);"pen/rpen test"
20 graphic clr
30 pen 5
40 a=rpen(0)
50 pen 1,9
60 b=rpen(1)
70 pen 2,3
80 c=rpen(2)
90 pen 0,7
100 d=rpen(0)
110 e=rpen(1)
120 print "pen 5 (want 5):";a
130 print "pen 1,9 (want 9):";b
140 print "pen 2,3 (want 3):";c
150 print "pen 0,7 (want 7):";d
160 print "pen 1 kept (want 9):";e
170 if a=5 and b=9 and c=3 and d=7 and e=9 then print "pen ok"
