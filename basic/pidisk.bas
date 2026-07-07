10 print chr$(147);:print "test pidisk"
20 p=~
30 if p>3.14159 and p<3.1416 then print " pi ok" : else print "pi fail";p
40 if sin(~/2)>0.9999 then print " pi trig ok" : else print "pi trig fail"
50 disk "i0"
60 if ds=0 then print " disk cmd ok" : else print "disk cmd fail";ds
70 disk
80 print "pidisk done"
