10 print chr$(147);:print "test strings"
20 print " dup ok":print " dup ok"
30 s$=" str var ok":print s$:print s$
40 print " empty:";t$
50 u$=s$:print u$
60 v$=t$:print " empty copy:";v$
70 a$="hello ":b$="world":c$=a$+b$:print c$
80 d$="lit "+c$+" ok":print d$
90 if c$="hello world" then print " str eq ok" : else print "str eq fail"
100 if c$<>"hello" then print " str ne ok" : else print "str ne fail"
110 if "a"<"b" and "b">"a" then print " str cmp ok" : else print "str cmp fail"
120 if t$="" then print " empty cmp ok" : else print "empty cmp fail"
130 if len(c$)=11 and len(t$)=0 and len("ab"+b$)=7 then print " len ok" : else print "len fail"
140 if left$(c$,5)="hello" and right$(c$,5)="world" then print " left/right ok" : else print "left/right fail"
150 if mid$(c$,7)="world" and mid$(c$,7,3)="wor" then print " mid ok" : else print "mid fail"
160 if left$("abc",1)+right$("xyz",1)="az" then print " substr concat ok" : else print "substr concat fail"
170 if val("123")=123 and val("-45")=-45 and val(" 7x")=7 then print " val ok" : else print "val fail"
180 s$=str$(42):t$=str$(-3):if s$=" 42" and t$="-3" and val(str$(-12))=-12 then print " str$ ok" : else print "str$ fail";s$;t$
190 dim q$(2),p$(1,1)
200 q$(0)="red":q$(1)="green":q$(2)=q$(0)+q$(1)
210 p$(1,1)=mid$(q$(2),4):if q$(0)="red" and q$(2)="redgreen" and p$(1,1)="green" then print " str arr ok" : else print "str arr fail";q$(0);q$(2);p$(1,1)
220 print " str arr:";q$(0);q$(1);p$(1,1)
230 print "strings done"
