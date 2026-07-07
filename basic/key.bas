10 print chr$(147);:print "test key"
20 key 3,"hello"
30 if peek(4098)=5 then print " len ok" : else print "len fail";peek(4098)
40 s=4112+peek(4096)+peek(4097)
50 if peek(s)=asc("h") and peek(s+4)=asc("o") then print " str ok" : else print "str fail"
60 key 3,"long test string"
70 if peek(4098)=16 then print " grow ok" : else print "grow fail";peek(4098)
80 key 3,"dir"+chr$(13)
90 if peek(4098)=4 then print " shrink ok" : else print "shrink fail";peek(4098)
100 print "key done"
