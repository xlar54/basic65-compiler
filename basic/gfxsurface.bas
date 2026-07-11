10 print chr$(147);:print "surface benchmark"
20 graphic clr
30 screen 640,200,8
40 scnclr 0
50 xm=12:ym=12:zm=1.5:nh%=120:nv%=100:sc=155
60 hm%=320:vm%=116:ye%=198:pi=4*atn(1):dim hi%(640),lo%(640)
70 al=pi/4:ka=.4:ca=ka*cos(al):sa=ka*sin(al)
80 dy=2*ym/nv%:dx=2*xm/nh%:y=-ym
90 clr ti
100 for v%=0 to nv%
110 x=-xm:f1%=0:f2%=0
120 for h%=0 to nh%
130 r=sqr(x*x+y*y)
140 if r=0 then z=1:goto 160
150 z=sin(r)/r
160 xx=x/xm*sc:yy=y/ym*sc:zz=z/zm*sc
170 xs%=int(hm%+xx+yy*ca):ys%=int(vm%-zz-sa*yy)
180 if xs%<0 then 240
190 if xs%>639 then 240
200 if ye%-ys%>hi%(xs%) then gosub 500:goto 220
210 f1%=0
220 if ys%>lo%(xs%) then gosub 600:goto 240
230 f2%=0
240 x=x+dx:next h%
250 y=y+dy:next v%
260 t=ti
270 pen 7:char 4,4,1,1,2,"press key"
280 getkey k$
290 screen close
300 print "surface benchmark"
310 print "grid:";nh%;"x";nv%
320 print "seconds:";t
330 end
500 if f1%=-1 then pen 5:line x1%,y1%,xs%,ys%
510 hi%(xs%)=ye%-ys%:x1%=xs%:y1%=ys%:f1%=-1
520 return
600 if f2%=-1 then pen 2:line x2%,y2%,xs%,ys%
610 lo%(xs%)=ys%:x2%=xs%:y2%=ys%:f2%=-1
620 return
