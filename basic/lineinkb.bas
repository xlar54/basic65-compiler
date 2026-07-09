10 print chr$(147);:print "test line input (keyboard)"
20 line input "name: ",n$
30 line input "phrase: ";p$
40 line input a$,b$
50 print " name:";n$
60 print " phrase:";p$
70 print " a:";a$;" b:";b$
80 if len(n$)>=0 then print "line input kb done"
