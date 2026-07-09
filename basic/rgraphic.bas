10 print chr$(147);"rgraphic test"
20 dim a(10)
30 graphic clr
40 screen def 0,1,0,4
50 screen open 0
60 screen set 0,0
70 pen 0,1
80 line 0,0,639,199
90 for i = 0 to 10 : a(i) = rgraphic(0,i) : next
100 screen close 0
110 for i = 0 to 6 : print i; a(i) : next
120 if a(0)=1 and a(1)=1 and a(2)=0 and a(3)=4 then if a(4)=15 and a(5)=15 and a(6)=15 then print "rgraphic ok"
