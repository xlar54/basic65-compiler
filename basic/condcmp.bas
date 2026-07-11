10 print "bisect2"
20 gosub 2000
30 gosub 4000
40 print "done":end
2000 rem v3: full combo minus the numeric if
2010 dim x(5):x(0)=10:x(1)=20:x(2)=x(0)+x(1)
2020 restore 2100:read r,s,t,u
2040 restore 2110:read a$,b$
2050 if a$="red" and b$="green" then print " v3 ok" : else print "v3 fail";a$;b$
2060 return
2100 data 11,22,-3,42
2110 data "red","green"
4000 rem v4: full combo with the numeric if
4010 dim y(5):y(0)=10:y(1)=20:y(2)=y(0)+y(1)
4020 restore 4100:read r,s,t,u
4030 if r=11 and s=22 and t=-3 and u=42 and y(2)=30 then print " num ok" : else print "num fail";r;s;t;u;y(2)
4040 restore 4110:read c$,d$
4050 if c$="red" and d$="green" then print " v4 ok" : else print "v4 fail";c$;d$
4060 return
4100 data 11,22,-3,42
4110 data "red","green"
