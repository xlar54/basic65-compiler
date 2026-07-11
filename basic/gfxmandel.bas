10 print chr$(147);:print "gfx mandelbrot"
20 graphic clr
30 screen 320,200,8
40 scnclr 0
50 mx%=32
60 clr ti
70 for py%=0 to 199
80 y0=py%*2.4/199-1.2:lc%=-1:sx%=0
90 for px%=0 to 319
100 x0=px%*3.5/319-2.5:xr=0:yi=0:it%=0
110 x2=xr*xr:y2=yi*yi
120 if x2+y2>4 then 180
130 if it%>=mx% then 170
140 yt=2*xr*yi+y0
150 xr=x2-y2+x0:yi=yt:it%=it%+1
160 goto 110
170 co%=0:goto 210
180 co%=it%+1
190 if co%>15 then co%=co%-15
200 if co%>15 then co%=co%-15
210 if lc%=-1 then lc%=co%:sx%=px%:goto 250
220 if co%=lc% then 250
230 ex%=px%-1:pen lc%:line sx%,py%,ex%,py%
240 sx%=px%:lc%=co%
250 next px%
260 pen lc%:line sx%,py%,319,py%
270 next py%
280 ji=ti
290 pen 7:char 4,4,1,1,2,"press key"
300 getkey k$
310 screen close
320 print "gfx mandelbrot"
330 print "size: 320x200"
340 print "max iter:";mx%
350 print "seconds:";ji
