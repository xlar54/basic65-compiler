10 print chr$(147);:print "test tier1e"
20 open 2,8,2,"@0:tfile,s,w"
30 print#2,"hello"
40 print#2,42;99
50 close 2
60 open 2,8,2,"tfile,s,r"
70 input#2,a$
80 input#2,b,c
90 close 2
100 print " s:";a$
110 print " n:";b;c
120 open 2,8,2,"tfile,s,r"
130 get#2,g$:get#2,h
140 close 2
150 print " g:";g$;h
160 print " st:";st>=0
170 print "tier1e done"
