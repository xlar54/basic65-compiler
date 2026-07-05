10 print chr$(147);:print "test disk"
20 dopen#2,"dvtest",w
30 print#2,"hello disk"
40 dclose#2
50 if ds=0 then print " write ok"
60 dopen#2,"dvtest"
70 input#2,a$
80 dclose#2
90 if a$="hello disk" then print " read ok"
100 rename "dvtest" to "dvtest2"
110 if ds=0 then print " rename ok"
120 copy "dvtest2" to "dvtest3"
130 if ds=0 then print " copy ok"
140 scratch "dvtest2"
150 scratch "dvtest3"
160 print " status: ";ds$
165 poke 4096,7
170 bsave "dvbin",p4096 to p4100
180 if ds=0 then print " bsave ok"
190 poke 4096,123
200 bload "dvbin",p4096
210 if peek(4096)=7 then print " bload ok"
220 scratch "dvbin"
230 print "disk done"
