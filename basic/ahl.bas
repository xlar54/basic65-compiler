10 print chr$(147);:print "ahl benchmark"
20 clr ti
30 s=0:r=0
40 for n=1 to 100
50 a=n
60 for i=1 to 10:a=sqr(a):r=r+rnd(1):next i
70 for i=1 to 10:a=a^2:r=r+rnd(1):next i
80 s=s+a
90 next n
100 t1=ti
110 print "accuracy:";abs(1010-s/5)
120 print "random:";abs(1000-r)
130 print "seconds:";t1
140 print "ahl done"
