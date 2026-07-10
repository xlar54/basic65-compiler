10 print chr$(147);:print "prime benchmark"
20 lm%=5000:ct%=1:ck%=2
30 clr ti:poke $d020,2
40 for n%=3 to lm% step 2
50 ok%=1
60 for d%=3 to n% step 2
70 if d%*d%>n% then 100
80 if mod(n%,d%)=0 then ok%=0:goto 100
90 next d%
100 if ok% then ct%=ct%+1:ck%=ck%+n%
110 if ck%>25000 then ck%=ck%-25000
120 next n%
130 t=ti:poke $d020,6
140 print "limit:";lm%
150 print "primes:";ct%;" expect 669"
160 print "check:";ck%;" expect 23136"
170 print "seconds:";t
180 if ct%=669 and ck%=23136 then print "prime ok" : else print "prime fail"
