10 print chr$(147);chr$(27);"x";
15 vol 0,0
20 print "###"
30 print "#.#"
40 print "###"
50 for y=0 to 2:for x=0 to 2
60 if t@&(x,y)=46 or t@&(x,y)=81 or t@&(x,y)=32 then c@&(x,y)=10:else c@&(x,y)=6
70 next x:next y
80 tx=1:ty=1
90 ml=c@&(tx-1,ty):mr=c@&(tx+1,ty):mu=c@&(tx,ty-1):md=c@&(tx,ty+1)
100 no=0
110 if 270=270 and ml=6 then no=1
120 ai=mod(104,8)=0 and mod(127-7,8)=0
130 print "ml";ml;" mr";mr;" mu";mu;" md";md
140 if no=1 then print "wall ok":else print "wall fail";no;ml
150 if ai=-1 then print "ai ok":else print "ai fail";ai
160 end
