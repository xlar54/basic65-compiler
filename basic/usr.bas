10 print chr$(147);:print "test usr"
20 rem ml at $1600: clc / adc #1 / rts (add 1 to the argument)
30 poke 5632,24:poke 5633,105:poke 5634,1:poke 5635,96
40 poke 760,0:poke 761,22
50 if usr(41)=42 then print " usr ok"
60 print "usr done"
