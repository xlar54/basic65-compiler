10 print chr$(147);:print "test line input#"
20 scratch "lidat"
30 dopen#2,"lidat",w
40 print#2,"hello, world"
50 print#2,"  spaced  and, commas"
60 print#2,""
70 print#2,"say ";chr$(34);"potato";chr$(34)
80 dclose#2
90 dopen#2,"lidat"
100 line input#2,a$,b$
110 line input#2,c$
120 line input#2,d$
130 dclose#2
140 print " a:";a$
150 print " b:";b$
160 print " c:[";c$;"]"
170 print " d:";d$
180 e$="say "+chr$(34)+"potato"+chr$(34)
190 if a$="hello, world" and b$="  spaced  and, commas" then if c$="" and d$=e$ then print "line input ok"
200 scratch "lidat"
