10 print chr$(147);:print "test boot"
20 restore 200
30 for i=0 to 23
40 read b:poke $a600+i,b
50 next i
60 bsave "btprg",p42496 to p42520
70 print " chaining..."
80 boot "btprg"
90 print "boot fail"
200 data 162,0,189,16,166,240,6,157,160,8,232,208,245,76,13,166
210 data 2,15,15,20,32,15,11,0
