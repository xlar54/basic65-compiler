10 print chr$(147);:print "test input"
20 input "enter 42,-3,12345";n,m,q$
30 if n=42 then print " int ok" : else print "int fail";n
40 if m=-3 then print " neg ok" : else print "neg fail";m
50 if q$="12345" then print " str ok" : else print "str fail";q$
60 input "enter 1,2";a,b
70 if a=1 and b=2 then print " multi ok" : else print "multi fail";a;b
80 dim ia(1),is$(1)
90 input "enter 7,hi,8,ok";ia(0),is$(0),ia(1),is$(1)
100 if ia(0)=7 and ia(1)=8 and is$(0)="hi" and is$(1)="ok" then print " arr ok" : else print "arr fail"
110 print "input done"
