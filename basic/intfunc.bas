10 print chr$(147);:print "test int funcs"
20 if abs(-5)=5 and abs(5)=5 and abs(0)=0 then print " abs ok" : else print "abs fail"
30 if sgn(-7)=-1 and sgn(0)=0 and sgn(9)=1 then print " sgn ok" : else print "sgn fail"
40 if int(-7)=-7 and int(9)=9 then print " int ok" : else print "int fail"
50 a=-12:b=abs(a):c=sgn(a):d=int(a+5)
60 print "vals:";b;c;d
70 if b=12 and c=-1 and d=-7 then print " int funcs ok" : else print "int funcs fail";b;c;d
