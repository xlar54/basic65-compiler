10 print chr$(147);:print "test cheap wins"
20 if (5 xor 3)=6 and (1 xor 1)=0 and (0 xor 9)=9 then print " xor ok"
30 if mod(7,4)=3 and mod(8,4)=0 and mod(3,7)=3 then print " mod ok"
40 if abs(log10(100)-2)<.0001 and abs(log10(.1)+1)<.0001 then print " log10 ok"
50 if fre(1)>0 then print " fre ok";fre(1)
60 if err$(20)="division by zero" then print " err$ ok"
70 sleep 0.5
80 print " sleep ok"
90 wait $d012,255
100 print " wait ok"
110 sprite 2,1,5,1,1,0,1:movspr 2,300,99
120 if rsprite(2,0)=1 and rsprite(2,1)=5 and rsprite(2,2)=1 then print " rsprite a ok"
130 if rsprite(2,3)=1 and rsprite(2,4)=0 and rsprite(2,5)=1 then print " rsprite b ok"
140 if rsppos(2,0)=300 and rsppos(2,1)=99 then print " rsppos ok"
150 sprcolor 9,11
160 if rspcolor(1)=9 and rspcolor(2)=11 then print " rspcolor ok"
170 print " pot:";pot(1);" lpen:";lpen(0)
180 sprite 2,0
172 t$=ti$:print " ti$:";t$
174 if len(t$)=8 and mid$(t$,3,1)=":" and mid$(t$,6,1)=":" then print " ti$ ok"
176 clr ti:sleep 0.2
178 if ti>0.1 and ti<2 then print " ti ok";ti
190 print "cheap done"
