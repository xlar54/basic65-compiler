10 print chr$(147);:print "test str array"
20 dim a$(4),b$(1,2)
30 for i=0 to 4
40 a$(i)="item"+str$(i)
50 next i
60 b$(0,0)=a$(1)
70 b$(0,1)=a$(2)+"x"
80 b$(1,0)=left$(a$(3),4)
90 b$(1,1)=right$(a$(4),2)
100 if a$(0)="item 0" and a$(4)="item 4" then print " one dim ok" : else print "one dim fail";a$(0);a$(4)
110 if b$(0,0)="item 1" and b$(0,1)="item 2x" and b$(1,0)="item" and b$(1,1)=" 4" then print " two dim ok" : else print "two dim fail";b$(0,0);b$(0,1);b$(1,0);b$(1,1)
120 for j=1 to 6000
130 t$="trash"+str$(j)
140 u$=left$(t$,3)+right$(t$,2)
150 next j
160 if a$(1)="item 1" and a$(3)="item 3" and b$(0,1)="item 2x" and b$(1,1)=" 4" then print " gc roots ok" : else print "gc roots fail";a$(1);a$(3);b$(0,1);b$(1,1)
170 print "strarr:";a$(0);a$(2);b$(0,1);b$(1,1)
180 print "str array done"
