10 print chr$(147);:print "mandelbrot benchmark"
20 clr ti
30 for py=0 to 20
40 for px=0 to 39
50 x0=px/40*3.5-2.5:y0=py/21*2-1
60 x=0:y=0:i=0
70 do while i<15
80 x2=x*x:y2=y*y
90 if x2+y2>4 then exit
100 y=2*x*y+y0:x=x2-y2+x0:i=i+1
110 loop
120 print mid$(" .,'~=+:;*%&$@#",i+1,1);
130 next px
140 print
150 next py
160 t1=ti
170 print "seconds:";t1
180 print "mandel done"
