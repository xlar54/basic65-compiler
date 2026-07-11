10 rem analog clock -- reads the rtc, any key exits
20 graphic clr
30 screen 320,200,4
40 cx=160:cy=100:pi=3.14159265
50 rem face: white double rim, grey inner ring
60 pen 1:circle cx,cy,97:circle cx,cy,96
70 pen 12:circle cx,cy,90
80 rem hour ticks (yellow) and minute dots (grey)
90 for i=0 to 59
100 a=i*pi/30:sa=sin(a):ca=cos(a)
110 x1=cx+sa*82:y1=cy-ca*82:x2=cx+sa*89:y2=cy-ca*89
120 if i-int(i/5)*5=0 then pen 7:line x1,y1,x2,y2: else pen 11:dot x2,y2
130 next i
140 gosub 500
150 rem hand state (start folded at the hub)
160 ox=cx:oy=cy:mx=cx:my=cy:sx=cx:sy=cy:os=-1
200 rem --- wait for the next second, keys exit ---
210 get k$:if k$<>"" then 400
220 t$=ti$:s=val(mid$(t$,7,2)):if s=os then 210
230 os=s:m=val(mid$(t$,4,2)):h=val(left$(t$,2))
240 rem erase old hands (numbers repaired below)
250 pen 0
260 line cx,cy,ox,oy:line cx-1,cy,ox,oy:line cx+1,cy,ox,oy
270 line cx,cy,mx,my:line cx-1,cy,mx,my:line cx+1,cy,mx,my
280 line cx,cy,sx,sy
290 rem new hand geometry
300 a=(h-int(h/12)*12+m/60)*pi/6:ox=cx+sin(a)*46:oy=cy-cos(a)*46
310 a=(m+s/60)*pi/30:mx=cx+sin(a)*66:my=cy-cos(a)*66
320 a=s*pi/30:sx=cx+sin(a)*78:sy=cy-cos(a)*78
330 rem hour and minute in white (thick), seconds in red
340 pen 1
350 line cx,cy,ox,oy:line cx-1,cy,ox,oy:line cx+1,cy,ox,oy
360 line cx,cy,mx,my:line cx-1,cy,mx,my:line cx+1,cy,mx,my
370 pen 2:line cx,cy,sx,sy
380 rem hub, then numbers back on top of the hands
390 pen 7:circle cx,cy,3:circle cx,cy,2:circle cx,cy,1:dot cx,cy
395 gosub 500
398 goto 210
400 screen close
410 end
500 rem clock numbers, centered on a 71-pixel ring
510 pen 7
520 for n=1 to 12
530 a=n*pi/6:px=cx+sin(a)*71:py=cy-cos(a)*71
540 n$=mid$(str$(n),2)
550 c=int((px-len(n$)*4)/8+.5):y=int(py-3.5)
560 char c,y,1,1,2,n$
570 next n
580 return
