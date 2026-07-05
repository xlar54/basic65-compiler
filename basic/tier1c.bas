10 print chr$(147);:print "test tier1c"
15 a=5
20 print " pow:";2^10;3^3
30 print " pown:";10^-2
40 print " powf:";1.5^2
50 print " hex:";hex$($c000);hex$(6699)
60 print " dec:";dec("1a2b")
70 s=instr("hello world","wor"):print " instr:";s
80 s=instr("hello","zz"):print " instr0:";s
90 t=ti:u=ti
95 if u>=t then if u<t+60 then print " ti ok"
100 clr
110 print " postclr:";a
140 print "tier1c done"
