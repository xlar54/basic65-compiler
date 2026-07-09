10 print chr$(147);"rpt$ test"
20 a$=rpt$("=",30)
30 print a$
40 print rpt$("hello ",3);"there"
50 b$=rpt$("ab",4)
60 c$=rpt$("x",0)
70 d$=rpt$("",5)
80 print "len30 (want 30):";len(a$)
90 print "abx4 (want abababab):";b$
100 print "zero count len (want 0):";len(c$)
110 print "empty src len (want 0):";len(d$)
120 if len(a$)=30 and b$="abababab" and len(c$)=0 and len(d$)=0 then print "rpt ok"
