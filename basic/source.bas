10 ts=14:rem 0=all 1=expr 2=data 3=on 4=bool 5=loop 6=str 7=input 8=get 9=temp 10=gc 11=strarr 12=mem 13=func 14=types
20 if ts=0 then gosub 1000:gosub 2000:gosub 3000:gosub 4000:gosub 5000:gosub 6000:gosub 7000:gosub 8000:gosub 9000:gosub 10000:gosub 11000:gosub 12000:gosub 13000:gosub 14000:end
30 on ts gosub 1000,2000,3000,4000,5000,6000,7000,8000,9000,10000,11000,12000,13000,14000
40 end
1000 print "test 1 expr"
1010 a=1+2*3:b=a-4
1020 c=(a+b)*2:d=c/5:e=-d+10
1030 print "a=",a," b=",b," c=",c," d=",d," e=",e:poke $d020,e
1040 if a=7 then 1060
1050 print "if equality failed":return
1060 if b<>4 then 1080
1070 print "if not-equal failed":return
1080 if a<>7 then print "false if failed":print "compound false failed"
1090 if b<4 then print "lt ok":print " compound:if ok"
1100 if c>19 then print " gt ok"
1110 if d<=4 then print " le ok"
1120 if e>=6 then print " ge:ok"
1130 if a=7 then if e=6 then print " nested:ok"
1135 if abs(-5)=5 and sgn(-7)=-1 and int(-7)=-7 then print " int funcs ok" : else print "int funcs fail"
1140 return
2000 print "test 2 data"
2010 print " data:strict ok"
2020 print " for:";:for i=1 to 5:print i;:next i:print
2030 print " rev:";:for j=5 to 1 step -2:print j;:next j:print
2040 dim x(5),y(2,3)
2050 x(0)=10:x(1)=20:x(2)=x(0)+x(1):x(5)=55
2060 y(1,2)=x(2)+7:y(2,3)=99
2070 print " arr:";x(0);x(1);x(2);y(1,2);x(5);y(2,3)
2080 restore 2300:read r,s,t,u
2090 print " data:";r;s;t;u
2100 restore 2300:read r,s
2110 print " restore:";r;s
2120 restore 2310:read a$,b$,c$
2130 print " sdata:";a$;b$;c$
2140 dim ds$(1):restore 2310:read ds$(0),ds$(1)
2150 if ds$(0)="red" and ds$(1)="green" then print " sdata arr ok" : else print "sdata arr fail";ds$(0);ds$(1)
2160 return
2300 data 11,22,-3,42
2310 data "red","green","blue"
3000 print "test 3 on"
3010 a=7:e=6
3020 on a-5 goto 3040,3050
3030 print "on goto failed":return
3040 print "on goto wrong":return
3050 print " on goto ok"
3060 og=2:on og gosub 3090,3100:print " on gosub after"
3070 if a-7 then print "truth false failed"
3080 if a then print " if truth ok"
3085 if 0 then print "zero truth failed":print "zero compound failed"
3087 if e then 3110
3090 print "on gosub wrong":return
3100 print " on gosub ok":return
3110 print " if truth goto ok"
3120 return
4000 print "test 4 bool"
4010 a=7:b=3
4020 if not 0 then print " not ok"
4030 if not a then print "not a failed"
4040 if a=7 and b=3 then print " and ok"
4050 if a=7 and b=4 then print "and false failed"
4060 if a=0 or b=3 then print " or ok"
4070 if a=0 or b=4 then print "or false failed"
4080 if not (a=0) then print " not compare ok"
4090 if not (a=7 and b=3) then print "not compound failed"
4100 if a=7 then print " else true ok" : else print "else true failed"
4110 if a=0 then print "else false failed" : else print " else false ok"
4120 if a=7 and b=3 then print " else bool ok" : else print "else bool failed"
4130 if a=0 or b=4 then print "else bool false failed" : else print " else bool false ok"
4140 return
5000 print "test 5 loop"
5010 n=0:print " loop until:";:do:n=n+1:print n;:loop until n=3:print
5020 n=3:print " do while:";:do while n>0:print n;:n=n-1:loop:print
5030 n=0:do:n=n+1:if n=2 then print " loop if ok":loop until n=2
5040 n=0:do until n=2:n=n+1:loop:print " do until ok";n
5050 n=0:print " exit:";:do:n=n+1:if n=3 then exit : else print n;:loop:print " ok";n
5060 print " exit for:";:for f=1 to 5:if f=3 then exit for : else print f;:next f:print " ok";f
5070 return
6000 print chr$(147);:print "test 6 str"
6010 print " dup ok":print " dup ok"
6020 s$=" str var ok":print s$:print s$
6030 print " empty:";t$
6040 u$=s$:print u$
6050 v$=t$:print " empty copy:";v$
6060 a$="hello ":b$="world":c$=a$+b$:print c$
6070 d$="lit "+c$+" ok":print d$
6072 if c$="hello world" then print " str eq ok" : else print "str eq fail"
6074 if c$<>"hello" then print " str ne ok" : else print "str ne fail"
6076 if "a"<"b" and "b">"a" then print " str cmp ok" : else print "str cmp fail"
6078 if t$="" then print " empty cmp ok" : else print "empty cmp fail"
6079 if len(c$)=11 and len(t$)=0 and len("ab"+b$)=7 then print " len ok" : else print "len fail"
6080 if left$(c$,5)="hello" and right$(c$,5)="world" then print " left/right ok" : else print "left/right fail"
6082 if mid$(c$,7)="world" and mid$(c$,7,3)="wor" then print " mid ok" : else print "mid fail"
6084 if left$("abc",1)+right$("xyz",1)="az" then print " substr concat ok" : else print "substr concat fail"
6086 if val("123")=123 and val("-45")=-45 and val(" 7x")=7 then print " val ok" : else print "val fail"
6088 s$=str$(42):t$=str$(-3):if s$=" 42" and t$="-3" and val(str$(-12))=-12 then print " str$ ok" : else print "str$ fail";s$;t$
6090 dim q$(2),p$(1,1)
6092 q$(0)="red":q$(1)="green":q$(2)=q$(0)+q$(1)
6094 p$(1,1)=mid$(q$(2),4):if q$(0)="red" and q$(2)="redgreen" and p$(1,1)="green" then print " str arr ok" : else print "str arr fail";q$(0);q$(2);p$(1,1)
6096 print " str arr:";q$(0);q$(1);p$(1,1)
6098 return
7000 print chr$(147);:print "test 7 input"
7010 input "enter 42,-3,12345";n,m,q$
7020 if n=42 then print " input int ok" : else print "input int fail";n
7030 if m=-3 then print " input neg ok" : else print "input neg fail";m
7040 if q$="12345" then print " input str ok" : else print "input str fail";q$
7050 input "enter 1,2";a,b
7060 if a=1 and b=2 then print " input multi ok" : else print "input multi fail";a;b
7062 dim ia(1),is$(1)
7064 input "enter 7,hi,8,ok";ia(0),is$(0),ia(1),is$(1)
7066 if ia(0)=7 and ia(1)=8 and is$(0)="hi" and is$(1)="ok" then print " input arr ok" : else print "input arr fail";ia(0);is$(0);ia(1);is$(1)
7070 return
8000 print chr$(147);:print "test 8 get/scroll"
8010 for sl=1 to 28:print " scroll";sl:next sl
8020 print " scroll ok"
8030 get g$:if g$="" then 8040
8035 print " get prefill":goto 8050
8040 print " get empty ok"
8050 print "press a key"
8060 do:get g$:loop until g$<>""
8070 print " get str ok"
8080 print "press a key"
8090 do:get g:loop until g<>0
8100 print " get int ok";g
8102 dim ga(0),gs$(0)
8104 print "press a key"
8106 do:get gs$(0):loop until gs$(0)<>""
8108 print " get str arr ok";gs$(0)
8110 print "press a key"
8112 do:get ga(0):loop until ga(0)<>0
8114 print " get int arr ok";ga(0)
8120 return
9000 print chr$(147);:print "test 9 temp"
9010 for i=1 to 2600
9020 if len("abc"+str$(i))<1 then print " len temp fail":return
9030 if left$("abc",1)<>"a" then print " if temp fail":return
9040 next i
9050 print " temp heap ok";i
9060 print " print temp:";left$("hello",2)+right$("ok",1)
9070 return
10000 print chr$(147);:print "test 10 gc"
10010 for i=1 to 6000
10020 a$="gc"
10030 b$=str$(i)
10040 next i
10050 if a$="gc" and val(b$)=6000 then print " gc ok" : else print "gc fail";a$;b$
10060 return
11000 print chr$(147);:print "test 11 str array"
11010 dim sa$(4),sb$(1,2)
11020 for i=0 to 4
11030 sa$(i)="item"+str$(i)
11040 next i
11050 sb$(0,0)=sa$(1):sb$(0,1)=sa$(2)+"x"
11060 sb$(1,0)=left$(sa$(3),4):sb$(1,1)=right$(sa$(4),2)
11070 if sa$(0)="item 0" and sa$(4)="item 4" then print " one dim ok" : else print "one dim fail";sa$(0);sa$(4)
11080 if sb$(0,0)="item 1" and sb$(0,1)="item 2x" and sb$(1,0)="item" and sb$(1,1)=" 4" then print " two dim ok" : else print "two dim fail";sb$(0,0);sb$(0,1);sb$(1,0);sb$(1,1)
11090 for j=1 to 6000
11100 t$="trash"+str$(j)
11110 u$=left$(t$,3)+right$(t$,2)
11120 next j
11130 if sa$(1)="item 1" and sa$(3)="item 3" and sb$(0,1)="item 2x" and sb$(1,1)=" 4" then print " gc roots ok" : else print "gc roots fail";sa$(1);sa$(3);sb$(0,1);sb$(1,1)
11140 print " strarr:";sa$(0);sa$(2);sb$(0,1);sb$(1,1)
11150 return
12000 print chr$(147);:print "test 12 mem"
12010 poke $d020,2
12020 v=peek($d020)
12030 if v=2 then print " peek/poke ok" : else print "peek/poke fail";v
12040 wpoke $3000,$1234
12050 w=wpeek($3000)
12060 if w=$1234 then print " wpeek/wpoke ok" : else print "wpeek/wpoke fail";w
12070 poke $3002,peek($3000)
12080 if peek($3002)=$34 then print " peek expr ok" : else print "peek expr fail";peek($3002)
12090 poke $d020,6
12100 return
13000 print chr$(147);:print "test 13 funcs"
13010 if abs(-5)=5 and abs(5)=5 and abs(0)=0 then print " abs ok" : else print "abs fail"
13020 if sgn(-7)=-1 and sgn(0)=0 and sgn(9)=1 then print " sgn ok" : else print "sgn fail"
13030 if int(-7)=-7 and int(9)=9 then print " int ok" : else print "int fail"
13040 a=-12:b=abs(a):c=sgn(a):d=int(a+5)
13050 print " vals:";b;c;d
13060 if b=12 and c=-1 and d=-7 then print " int funcs ok" : else print "int funcs fail";b;c;d
13070 return
14000 print chr$(147);:print "test 14 types"
14010 a=7:a%=3:a$="ok"
14020 if a=7 and a%=3 and a$="ok" then print " scalar types ok" : else print "scalar types fail";a;a%;a$
14030 dim n(1),n%(1),n$(1)
14040 n(0)=10:n%(0)=20:n$(0)="str"
14050 if n(0)=10 and n%(0)=20 and n$(0)="str" then print " array types ok" : else print "array types fail";n(0);n%(0);n$(0)
14060 print " values:";a;a%;a$:print " arrays:";n(0);n%(0);n$(0)
14070 for i%=1 to 3:next i%
14080 if i%=4 then print " for int suffix ok" : else print "for int suffix fail";i%
14090 return
