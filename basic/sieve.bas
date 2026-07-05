10 print chr$(147);:print "byte sieve benchmark"
20 dim f(8190)
30 clr ti
40 for it=1 to 3
50 c=0
60 for i=0 to 8190:f(i)=1:next i
70 for i=0 to 8190
80 if f(i)=0 then 130
90 p=i+i+3:k=i+p
100 if k>8190 then 120
110 f(k)=0:k=k+p:goto 100
120 c=c+1
130 next i
140 next it
150 t1=ti
160 print "primes:";c;" (expect 1899)"
170 print "seconds:";t1
180 print "sieve done"
