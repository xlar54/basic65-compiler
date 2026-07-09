10 ts=0:rem smoke test: 0=all 1=expr 2=data 3=on 4=bool 5=loop 6=str 7=types 8=mem (depth lives in the per-area fixtures: expr data flow loops strings strarray gc temp mem types intfunc floats input get)
20 if ts=0 then gosub 1000:gosub 2000:gosub 3000:gosub 4000:gosub 5000:gosub 6000:gosub 7000:gosub 8000:print "smoke ok":end
30 on ts gosub 1000,2000,3000,4000,5000,6000,7000,8000
40 end
1000 print "test 1 expr"
1010 a=1+2*3:b=a-4:c=(a+b)*2:d=c/5:e=-d+10
1020 if a=7 and b=3 and c=20 and d=4 and e=6 then print " expr ok" : else print "expr fail";a;b;c;d;e
1030 if abs(-5)=5 and sgn(-7)=-1 and int(-7)=-7 then print " int funcs ok" : else print "int funcs fail"
1040 return
2000 print "test 2 data"
2010 dim x(5):x(0)=10:x(1)=20:x(2)=x(0)+x(1)
2020 restore 2100:read r,s,t,u
2030 if r=11 and s=22 and t=-3 and u=42 and x(2)=30 then print " data/arr ok" : else print "data/arr fail";r;s;t;u;x(2)
2040 restore 2110:read a$,b$
2050 if a$="red" and b$="green" then print " sdata ok" : else print "sdata fail";a$;b$
2060 return
2100 data 11,22,-3,42
2110 data "red","green"
3000 print "test 3 on"
3010 a=7
3020 on a-5 goto 3040,3050
3030 print "on goto failed":return
3040 print "on goto wrong":return
3050 print " on goto ok"
3060 og=2:on og gosub 3080,3090
3070 return
3080 print "on gosub wrong":return
3090 print " on gosub ok":return
4000 print "test 4 bool"
4010 a=7:b=3
4020 if a=7 and b=3 and not (a=0) then print " and/not ok" : else print "and/not fail"
4030 if a=0 or b=3 then print " or ok" : else print "or fail"
4040 if a=0 then print "else fail" : else print " else ok"
4050 if a then print " truth ok"
4060 return
5000 print "test 5 loop"
5010 n=0:do:n=n+1:loop until n=3
5020 m=3:do while m>0:m=m-1:loop
5030 p=0:do:p=p+1:if p=3 then exit
5040 loop
5050 f9=0:for f=1 to 5:f9=f9+f:next f
5060 if n=3 and m=0 and p=3 and f9=15 then print " loops ok" : else print "loops fail";n;m;p;f9
5070 return
6000 print "test 6 str"
6010 a$="hello ":b$="world":c$=a$+b$
6020 if c$="hello world" and len(c$)=11 then print " concat ok" : else print "concat fail";c$
6030 if left$(c$,5)="hello" and right$(c$,5)="world" and mid$(c$,7,3)="wor" then print " substr ok" : else print "substr fail"
6040 if val("123")=123 and str$(42)=" 42" then print " val/str$ ok" : else print "val/str$ fail"
6050 return
7000 print "test 7 types"
7010 a=7:a%=3:a$="ok":f=1.5
7020 if a=7 and a%=3 and a$="ok" then print " scalars ok" : else print "scalars fail"
7030 print " float:";f;-2.25;.75
7040 return
8000 print "test 8 mem"
8010 poke $3000,$34:wpoke $3002,$1234
8020 if peek($3000)=$34 and wpeek($3002)=$1234 then print " mem ok" : else print "mem fail"
8030 return
