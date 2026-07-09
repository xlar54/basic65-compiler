10 print chr$(147);:print "test get/scroll"
20 for sl=1 to 28:print " scroll";sl:next sl
30 print " scroll ok"
40 get g$:if g$="" then 60
50 print " get prefill":goto 70
60 print " get empty ok"
70 print "press a key"
80 do:get g$:loop until g$<>""
90 print " get str ok"
100 print "press a key"
110 do:get g:loop until g<>0
120 print " get int ok";g
130 dim ga(0),gs$(0)
140 print "press a key"
150 do:get gs$(0):loop until gs$(0)<>""
160 print " get str arr ok";gs$(0)
170 print "press a key"
180 do:get ga(0):loop until ga(0)<>0
190 print " get int arr ok";ga(0)
200 print "get done"
