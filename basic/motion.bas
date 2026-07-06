10 print chr$(147);:print "test motion"
20 for i=0 to 62:poke 1536+i,255:next i
30 poke 2040,24:poke 2041,24:poke 4088,24:poke 4089,24
40 sprite 0,1,3:sprite 1,1,7
50 movspr 0,100,100
60 movspr 0,+50,+20
70 if rsppos(0,0)=150 and rsppos(0,1)=120 then print " relative ok"
80 movspr 1,60,200
90 movspr 1,60,200 to 260,80,4
100 sleep 1.5
110 if rsppos(1,0)=260 and rsppos(1,1)=80 then print " to ok"
120 if rsppos(1,2)=4 then print " speed ok"
130 movspr 0,90#3
140 x0=rsppos(0,0)
150 sleep 0.5
160 x1=rsppos(0,0)
170 if x1>x0 then print " angle ok";x0;x1
180 movspr 0,100,100
190 sprite 0,0:sprite 1,0
200 print "motion done"
