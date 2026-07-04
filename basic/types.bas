10 print chr$(147);:print "test types"
20 a=7:a%=3:a$="ok"
30 if a=7 and a%=3 and a$="ok" then print " scalar types ok" : else print "scalar types fail";a;a%;a$
40 dim n(1),n%(1),n$(1)
50 n(0)=10:n%(0)=20:n$(0)="str"
60 if n(0)=10 and n%(0)=20 and n$(0)="str" then print " array types ok" : else print "array types fail";n(0);n%(0);n$(0)
70 print " values:";a;a%;a$:print " arrays:";n(0);n%(0);n$(0)
80 for i%=1 to 3:next i%
90 if i%=4 then print " for int suffix ok" : else print "for int suffix fail";i%
