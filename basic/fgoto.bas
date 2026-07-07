10 print chr$(147);:print "test fgoto"
20 fgosub 100+10
30 x=250
40 fgoto x*2-300
50 print "fgoto fail"
60 print "fgoto done":end
110 print " fgosub ok":return
200 print " fgoto ok"
210 goto 60
