10 print chr$(147);:print "test temp"
20 for i=1 to 2600
30 if len("abc"+str$(i))<1 then print " len temp fail":end
40 if left$("abc",1)<>"a" then print " if temp fail":end
50 next i
60 print " temp heap ok";i
70 print " print temp:";left$("hello",2)+right$("ok",1)
80 print "temp done"
