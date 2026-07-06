10 print chr$(147);:print "test screen arrays"
20 t@&(10,5)=1
30 c@&(10,5)=2
40 if t@&(10,5)=1 then print " t read ok"
50 if c@&(10,5)=2 then print " c read ok"
60 t@&(11,5)=t@&(10,5)+1
70 if t@&(11,5)=2 then print " expr ok"
80 trap 200
90 x=t@&(200,5)
100 print "bounds fail"
110 print "scrarr done"
120 end
200 if er=18 then print " bounds ok"
210 resume 110
