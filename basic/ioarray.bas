10 print chr$(147);:print "test io arrays"
20 dim ia(1),is$(1)
30 input "enter 7,hi,8,ok";ia(0),is$(0),ia(1),is$(1)
40 if ia(0)=7 and ia(1)=8 and is$(0)="hi" and is$(1)="ok" then print " input arr ok" : else print "input arr fail";ia(0);is$(0);ia(1);is$(1)
50 dim ga(0),gs$(0)
60 print "press a key"
70 do:get gs$(0):loop until gs$(0)<>""
80 print " get str arr ok";gs$(0)
90 print "press a key"
100 do:get ga(0):loop until ga(0)<>0
110 print " get int arr ok";ga(0)
120 print "io arrays done"
