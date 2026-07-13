10 print chr$(147);"movtest2: glide vs pacman ingredients"
20 vol 5,5
30 sprite 0,1,7
40 dim sp$(1):for t=1 to 64:sp$(0)=sp$(0)+chr$(255):next t
50 movspr 0,90#0
60 rem -- a: plain reissue (baseline)
70 movspr 0,126,177
80 for i=1 to 500:x=rsppos(0,0):y=rsppos(0,1):movspr 0,x,y to x+8,y,0.9:next
90 xa=rsppos(0,0)
100 print " a plain :";xa-126;:if xa>126 then print " ok" : else print " fail"
110 rem -- b: sprsav every pass (pacman line 490)
120 movspr 0,126,177
130 for i=1 to 500:x=rsppos(0,0):y=rsppos(0,1):movspr 0,x,y to x+8,y,0.9:sprsav sp$(0),0:next
140 xb=rsppos(0,0)
150 print " b sprsav:";xb-126;:if xb>126 then print " ok" : else print " fail"
160 rem -- c: collision handler armed (pacman line 595)
170 collision 1,900
180 movspr 0,126,177
190 for i=1 to 500:x=rsppos(0,0):y=rsppos(0,1):movspr 0,x,y to x+8,y,0.9:next
200 xc=rsppos(0,0):collision 1
210 print " c coll  :";xc-126;:if xc>126 then print " ok" : else print " fail"
220 rem -- d: sound effects in the loop (pacman line 150)
230 movspr 0,126,177
240 for i=1 to 500:x=rsppos(0,0):y=rsppos(0,1):movspr 0,x,y to x+8,y,0.9:if mod(i,100)=0 then sound 4,8000,5,2,0,1500,1,0
250 next
260 xd=rsppos(0,0)
270 print " d sound :";xd-126;:if xd>126 then print " ok" : else print " fail"
280 rem -- e: new start, same target/speed must reprogram
290 movspr 0,126,177 to 180,177,1
300 movspr 0,140,177 to 180,177,1
310 xe=rsppos(0,0)
320 print " e start :";xe;:if xe>=140 and xe<150 then print " ok" : else print " fail"
330 print "movtest2 done"
340 end
900 co%=bump(1):return
