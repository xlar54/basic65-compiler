10 print chr$(147);"char test"
20 graphic clr
30 screen 320,200,8
40 pen 1
50 char 2,20,1,1,2,"hello world"
60 pen 3
70 char 2,40,2,2,2,"big text"
80 pen 5
90 char 30,80,1,1,4,"down"
100 pen 7
110 char 10,120,3,1,2,"tall"
120 s1=0:for x=16 to 103:s1=s1+sgn(pixel(x,23)):next x
130 s2=0:for x=16 to 143:s2=s2+sgn(pixel(x,46)):next x
140 s3=0:for y=80 to 111:s3=s3+sgn(pixel(244,y)):next y
150 for i=1 to 4000:next i
160 screen close
170 print "row through hello (>0):";s1
180 print "row through big (>0):";s2
190 print "col through down (>0):";s3
200 if s1>0 and s2>0 and s3>0 then print "char ok"
