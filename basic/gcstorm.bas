10 print chr$(147);"gc storm"
20 dim a$(40):dim b$(40)
30 for i=0 to 40:a$(i)="ref"+str$(i):next i
40 t$="":u$=""
50 for r=1 to 1000
60 for i=0 to 40
70 t$=a$(i)+"x":u$=left$(t$,3):b$(i)=u$+str$(i)
80 next i
90 next r
100 f=0
110 for i=0 to 40
120 if a$(i)<>"ref"+str$(i) then f=f+1
130 if b$(i)<>left$(a$(i)+"x",3)+str$(i) then f=f+1
140 next i
150 print "fails:";f
160 if f=0 then print "gc storm ok"
