10 print chr$(147);:print "test tier1f"
20 dim b(2)
30 trap 100
40 b(5)=1
50 print "no trap fail"
60 goto 130
100 print " er:";er;" el:";el
110 if er=18 then print " trap ok"
120 resume 130
130 trap 160
140 f=1/0
150 print "divtrap fail"
160 if er=20 then print " divtrap ok"
170 trap
180 print "tier1f done"
