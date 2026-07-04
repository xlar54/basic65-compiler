10 print chr$(147);:print "test gc"
20 for i=1 to 6000
30 a$="gc"
40 b$=str$(i)
50 next i
60 if a$="gc" and val(b$)=6000 then print " gc ok" : else print "gc fail";a$;b$
70 print "gc done"
