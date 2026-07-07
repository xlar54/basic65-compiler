10 print chr$(147);:print "test bankrreg"
20 bank 4
30 poke $9000,77
40 if peek($9000)=77 then print " far poke ok" : else print "far fail";peek($9000)
50 bank 128
60 poke $a400,78
70 if peek($a400)=78 then print " cpu poke ok" : else print "cpu fail"
80 bank 4
90 v=peek($9000)
100 bank 128
110 if v=77 then print " bank switch ok" : else print "switch fail";v
120 poke $a500,$60
130 sys $a500
140 rreg a,x,y,z,s
150 print " rreg:";a;x;y;z;s
160 vsync 100
170 vsync 200
180 print " vsync ok"
190 print "bankrreg done"
