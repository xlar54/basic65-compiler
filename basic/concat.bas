10 print chr$(147);:print "test concat"
20 scratch "ccone"
30 scratch "cctwo"
40 dopen#2,"ccone",w
50 print#2,"ab"
60 dclose#2
70 dopen#2,"cctwo",w
80 print#2,"cd"
90 dclose#2
100 concat "cctwo" to "ccone"
110 if ds=0 then print " concat ok"
120 dopen#2,"ccone"
130 input#2,a$
140 input#2,b$
150 dclose#2
160 c$=a$+b$
170 if c$="abcd" then print " combine ok":goto 190
180 print " combine fail ";c$
190 scratch "ccone"
200 scratch "cctwo"
210 print "concat done"
