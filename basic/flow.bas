10 print chr$(147);:print "test flow"
20 a=7:e=6
30 on a-5 goto 50,60
40 print "on goto failed":goto 200
50 print "on goto wrong":goto 200
60 print " on goto ok"
70 og=2:on og gosub 100,110:print " on gosub after"
80 if a-7 then print "truth false failed"
90 if a then print " if truth ok"
95 goto 120
100 print "on gosub wrong":return
110 print " on gosub ok":return
120 if 0 then print "zero truth failed":print "zero compound failed"
130 if e then 150
140 print "if truth goto failed":goto 200
150 print " if truth goto ok"
160 b=3
170 if not 0 then print " not ok"
172 if not a then print "not a failed"
174 if a=7 and b=3 then print " and ok"
176 if a=7 and b=4 then print "and false failed"
178 if a=0 or b=3 then print " or ok"
180 if a=0 or b=4 then print "or false failed"
182 if not (a=0) then print " not compare ok"
184 if not (a=7 and b=3) then print "not compound failed"
186 if a=7 then print " else true ok" : else print "else true failed"
188 if a=0 then print "else false failed" : else print " else false ok"
190 if a=7 and b=3 then print " else bool ok" : else print "else bool failed"
192 if a=0 or b=4 then print "else bool false failed" : else print " else bool false ok"
194 print "flow done"
200 end
