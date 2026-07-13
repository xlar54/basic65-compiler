10 print chr$(147);:print "test sprsav"
20 poke 4089,80
30 poke 4090,81
40 a$=""
50 for i=1 to 64:a$=a$+chr$(i):next
60 sprsav a$,1
70 sprsav 1,2
80 sprsav 2,b$
90 f=0
100 if len(b$)<>64 then f=1
110 if asc(mid$(b$,1,1))<>1 then f=2
120 if asc(mid$(b$,64,1))<>64 then f=3
130 if peek(5120)<>1 then f=4
140 if peek(5184+63)<>64 then f=5
150 if f=0 then print " sprsav ok" : else print " sprsav fail";f
160 poke 4088,128
170 sprsav a$,0
180 p=peek(4088):ad=p*64
190 if p<128 and peek(ad)=1 and peek(ad+63)=64 then print " sprsafe ok" : else print " sprsafe fail";p
200 print "sprsav done"
