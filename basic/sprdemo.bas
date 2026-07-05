10 print chr$(147);:print "sprite demo"
20 rem solid 24x21 block at $0340, pointer value 13
30 for i=0 to 62:poke 832+i,255:next i
40 rem sprite 0 pointer: c64-style $07f8 and c65 80-col $0ff8
50 poke 2040,13:poke 4088,13
60 sprite 0,1,7
70 for x=30 to 300 step 2
80 movspr 0,x,140
90 for d=1 to 300:next d
100 next x
110 print "sprite demo done"
