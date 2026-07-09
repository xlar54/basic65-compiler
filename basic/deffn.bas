10 print chr$(147);"def fn test"
20 def fn db(x) = x*2
30 def fn sq(x) = x*x+1
40 a = fn db(21)
50 b = fn sq(5)
60 x = 99
70 c = fn db(x)
80 print "db 21 (want 42):";a
90 print "sq 5 (want 26):";b
100 print "db of x=99 (want 198):";c
110 print "x preserved (want 99):";x
120 d = fn sq(fn db(2))
130 print "nested (want 17):";d
140 if a=42 and b=26 and c=198 and x=99 and d=17 then print "deffn ok"
