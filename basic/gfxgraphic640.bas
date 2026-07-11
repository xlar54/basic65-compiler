110 graphic clr: rem initialise
120 screen def 1, 1, 1, 2 : rem 640 x 400 x 2
130 screen open 1
140 screen set 1, 1: rem open it: rem view it
150 palette 1, 0, 0, 0, 0 : rem black
160 palette 1, 1, 0, 15, 0 : rem green
170 scnclr 0
180 pen 0, 1: rem fill screen with black: rem select pen
190 line 50, 50, 590, 350 : rem draw line
200 getkey a$: rem wait for keypress
210 screen close 1: rem close screen and restore palette