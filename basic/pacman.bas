   10 print"{clr}";chr$(27);"x";
   50 dim s$(21): rem sprite builder array
   70 dim ac(5,10): rem actor data
   75 dim sp$(13) : rem sprites
   90 gosub 5970:gosub 3050:gosub 3570:nw=1:cs=0:vol 5,10:ma=5
  110 goto 570
  130 dc=dc-1:cursor 30,7:print "{lblu}"+right$("000000"+mid$(str$(cs),2),6)
  150 sound 4,8000,5,2,0,1500,1,0:return
  170 rem interrupt. sound, flash pp, anim pac
  190 ct=ti
  210 if ct-at >= 1.95 then sound 1,16000,100,2,8000,700,2,2000:at=ct
  230 if ct-ft >= 0.25 then begin
  250   fp=fp+1:if fp=2 then fp=0
  270   c@&(1,2)=fp:c@&(25,2)=fp:c@&(1,16)=fp:c@&(25,16)=fp
  290   ft=ct
  310 bend
  330 rem if ca<>0 then 330
  350 if an(0)=0 then sn=0:goto490
  370 ct=ti
  390 if ct-lt >= 0.05 then begin
  410  if ac(0,1)=90  then sn=sn+1:if sn>1 then sn=0
  430  if ac(0,1)=270 then sn=sn+2:if sn>2 then sn=0
  450  if ac(0,1)=0   then sn=sn+3:if sn>3 then sn=0
  470  if ac(0,1)=180 then sn=sn+4:if sn>4 then sn=0
  490  sprsav sp$(sn),0
  510  lt=ct
  530 bend
  550 return
  551 rem sprite to sprite collision handler
  552 co%=bump(1):if xx=0 then xx=((co% and 1)=0)+1
  569 return:rem 3031
  570 rem init screen
  590 border0: background0:color1:fort=0to4:spritet,0:next:dc=209
  595 collision 1,551: rem sprite to sprite collision interrupt
  610 print"{clr}{lblu}";
  630 print"OCCCCCCCCCCCC{CBM-R}CCCCCCCCCCCCP
  650 print"B............W............#
  670 print"BQUCCI.UCCCI.W.UCCCI.UCCIQ#
  690 print"B.JCCK.JCCCK.A.JCCCK.JCCK.#
  710 print"B.........................#
  730 print"B.ZCCX.UI.ZCC{CBM-R}CCX.UI.ZCCX.#
  750 print"B......WW....W....WW......#
  770 print"LCCCCI.WVCCX A ZCC{SHIFT-+}W.UCCCC{SHIFT-@}
  790 print"     W.WW         WW.W
  810 print"CCCCCK.JK UCC{CBM-@}CCI JK.JCCCCC
  830 print"      .   W     W   .
  850 print"CCCCCI.UI JCCCCCK UI.UCCCCC
  870 print"     W.WW         WW.W
  890 print"OCCCCK.JK ZCC{CBM-R}CCX JK.JCCCCP
  910 print"B............W............#
  930 print"B.ZCCI.ZCCCX.A.ZCCCX.UCCX.#
  950 print"BQ...W...............W...Q#
  970 print"{CBM-Q}CCX.A.UI.ZCC{CBM-R}CCX.UI.A.ZCC{CBM-W}
  990 print"B......WW....W....WW......#
 1010 print"B.ZCCCC{CBM-E}{CBM-E}CCX.A.ZCC{CBM-E}{CBM-E}CCCCX.#
 1030 print"B.........................#
 1050 print"LCCCCCCCCCCCCCCCCCCCCCCCCC{SHIFT-@}
 1070 cursor 28,1:print"{rvon}{yel}pacman 65{lblu}{rvof}"
 1090 cursor 28,3:print"high score"
 1110 cursor 30,4:print"000000"
 1130 cursor 28,6:print"score"
 1150 cursor 30,7:print"000000"
 1170 print"{home}";
 1190 rem color
 1210 fory=0to22:forx=0to26
 1230  ift@&(x,y)=46 or t@&(x,y)=81 or t@&(x,y)=32 then c@&(x,y)=10:else c@&(x,y)=6
 1250 nextx:nexty
 1270 rem c@&(13,9)=3:c@&(14,9)=3
 1290 rem sprite starting positions
 1310 sn=0:sprsav sp$(sn),0
 1330 sprsav sp$(6),1:sprsav sp$(7),2:sprsav sp$(8),3:sprsav sp$(9),4
 1350 sprite 0,1,ac(0,0):movspr 0,ac(0,1)#ac(0,2):movspr 0,ac(0,3),ac(0,4)
 1370 sprite 1,1,ac(1,0):movspr 1,ac(1,1)#ac(1,2):movspr 1,ac(1,3),ac(1,4)
 1390 sprite 2,1,ac(2,0):movspr 2,ac(2,1)#ac(2,2):movspr 2,ac(2,3),ac(2,4)
 1410 sprite 3,1,ac(3,0):movspr 3,ac(3,1)#ac(3,2):movspr 3,ac(3,3),ac(3,4)
 1430 sprite 4,1,ac(4,0):movspr 4,ac(4,1)#ac(4,2):movspr 4,ac(4,3),ac(4,4)
 1450 rem ready!
 1470 t=bump(1):cursor 11,12:print"{yel}ready!"
 1490 rem if new game, play music, else wait briefly
 1510 if nw=1 then gosub 5910:nw=0:sleep4.0:goto1550
 1530 sleep 2
 1550 cursor 11,12:print"      "
 1570 rem movement loop
 1590 rem current speed and original speed
 1610 fort=0to4
 1630  ac(t,2)=0.9:ac(t,9)=ac(t,2)
 1650  ac(t,7)=rsppos(t,0):ac(t,8)=rsppos(t,1)
 1670 nextt
 1690 b$="{left}"
 1710 for ca=0 to ma
 1730  if ca=0 then get a$:if a$<>"" then b$=a$
 1750  ac(ca,7)=rsppos(ca,0):ac(ca,8)=rsppos(ca,1)
 1770  px=ac(ca,7)-22:py=ac(ca,8)-50
 1790  rem check for tunnel
 1810  if px>219 and py=79 then px=8 :movspr ca,px,py+50:goto1850
 1830  if px=0   and py=79 then px=216:movspr ca,px,py+50
 1850  tx=int(px/8):ty=int((py+8)/8)
 1870  ai=mod(px,8)=0 and mod(py-7,8)=0
 1890  rem ifca=0then cursor 0,23:print"                           "
 1910  rem ifca=0then cursor 0,23:print"ai=";ai;" tx=";tx;" ty=";ty;" px=";px
 1930  gosub 170
 1950  if ai=-1 then begin
 1951   if xx=1 then xx=0:goto 3031:rem player died
 1970    c=t@&(tx,ty)
 1990    ml=c@&(tx-1,ty):mr=c@&(tx+1,ty):mu=c@&(tx,ty-1):md=c@&(tx,ty+1)
 2010    ac(ca,5)=tx:ac(ca,6)=ty
 2030    if ca=0 then begin
 2050     if c=46 then t@&(tx,ty)=32:cs=cs+10:gosub 130:goto2090
 2070     if c=81 then t@&(tx,ty)=32:cs=cs+100:gosub 130:goto2090
 2090     if dc=0 then 2870
 2110    if b$="{left}" and ml<>6 then ac(0,1)=270
 2130    if b$="{rght}" and mr<>6 then ac(0,1)=90
 2150    if b$="{up}" and mu<>6 then ac(0,1)=0
 2170    if b$="{down}" and md<>6 then ac(0,1)=180
 2190   bend
 2210   no=0
 2230   if ac(ca,1)=270 and ml=6 then no=1
 2250   if ac(ca,1)=90  and mr=6 then no=1
 2270   if ac(ca,1)=0   and mu=6 then no=1
 2290   if ac(ca,1)=180 and md=6 then no=1
 2310   if ca=0 then begin
 2330    ac(ca,2)=ac(ca,9):an(ca)=1:if no=1 then ac(ca,2)=0:an(ca)=0
 2350   bend
 2370   if ca>0 and no=1 then begin
 2390    nd=15
 2410    if mu=6 then nd=nd and 7
 2430    if md=6 then nd=nd and 11
 2450    if mr=6 then nd=nd and 13
 2470    if ml=6 then nd=nd and 14
 2490    if tx<=ac(0,5) and (nd and 2)=2 then ac(ca,1)=90:goto1770
 2510    if ty>ac(0,6) and (nd and 8)=8 then ac(ca,1)=0:goto1770
 2530    if tx>ac(0,5) and (nd and 1)=1 then ac(ca,1)=270:goto1770
 2550    if ty<=ac(0,6) and (nd and 4)=4 then ac(ca,1)=180:goto1770
 2570    if ac(ca,1)=0   then ac(ca,1)=90 :goto 1770
 2590    if ac(ca,1)=0   then ac(ca,1)=90 :goto 1770
 2610    if ac(ca,1)=90  then ac(ca,1)=180:goto 1770
 2630    if ac(ca,1)=180 then ac(ca,1)=270:goto 1770
 2650    if ac(ca,1)=270 then ac(ca,1)=0  :goto 1770
 2670   bend
 2690  dx=0:dy=0
 2710  if ac(ca,1)=90  then dx=8
 2730  if ac(ca,1)=270 then dx=-8
 2750  if ac(ca,1)=0   then dy=-8
 2770  if ac(ca,1)=180 then dy= 8
 2790  if ac(ca,2)>0 then movspr ca,px+22,py+50 to px+22+dx,py+50+dy,ac(ca,2)
 2810 bend
 2830 next ca
 2850 goto 1710
 2870 rem cleared screen
 2890 sprite 0,0:sound clr
 2910 forx=1to4
 2930  edma 3,80*25,0,$1f800
 2950  sleep 0.25
 2970  edma 3,80*25,1,$1f800
 2990  sleep 0.25
 3010 nextx
 3030 gosub 5970:goto 570
 3031 rem player dies
 3032 fort=1to4:spritet,0:next:sleep 0.2
 3034 fort=10to12:sprsav sp$(t),0:sleep 0.4:nextt:sprite 0,0:sleep 0.4
 3049 gosub 5970:goto 1290
 3050 rem character defs
 3070 chardef 46,0,0,0,24,24,0,0,0                : rem dots
 3090 chardef 66,144,144,144,144,144,144,144,144 : rem l vert bar
 3110 chardef 67,0,0,255,0,0,255,0,0 : rem horiz double bar
 3130 chardef 85,0,0,31,32,32,35,36,36: rem joy - shft-o
 3150 chardef 75,36,36,196,4,4,248,0,0: rem curve - up to left
 3170 chardef 74,36,36,35,32,32,31,0,0: rem curve - up to right
 3190 chardef 73,36,36,39,32,32,31,0,0: rem rpen - shft-p
 3210 chardef 115,9,9,241,1,1,241,9,9:rem v bar, left connection
 3230 chardef 107,144,144,143,128,128,143,144,144:rem - - alt-q
 3250 chardef 114,0,0,255,0,0,231,36,36
 3270 chardef 113,36,36,231,0,0,255,0,0
 3290 chardef 90,0,0,3,4,4,3,0,0: rem sound  shft-z
 3310 chardef 88,0,0,192,32,32,192,0,0: rem tron - shft-x
 3330 chardef 65,24,0 ,0 ,0 ,0 ,0 ,0,0: rem atn : shft-a
 3350 chardef 91,36,36,196,4,4,196,36,36:rem resume - alt-dbl quote
 3370 chardef 81,0,24,60,126,126,60,24,0:rem dec - shft-o
 3390 chardef 35,9,9,9,9,9,9,9,9: rem righ border
 3410 chardef 87,36,36,36,36,36,36,36,36: rem trap - shft-w
 3430 chardef 76,144,144,143,128,128,127,0,0: rem rgraphic - shft l
 3450 chardef 79,0,0,127,128,128,143,144,144: rem joy - shft-o
 3470 chardef 122,9,9,241,1,1,254,0,0 : rem sqr - shft-@
 3490 chardef 80,0,0,254,1,1,241,9,9: rem rpen - shft-p
 3510 chardef 73,0,0,248,4,4,196,36,36: rem rpen - shft-p
 3530 chardef 86,36,36,35,32,32,35,36,36:rem resume - shft-v
 3550 return
 3570 rem sprites
 3590 rem pacman sprite
 3610 s$(0)="     ##                 "
 3630 s$(1)="  ########              "
 3650 s$(2)=" ##########             "
 3670 s$(3)="############            "
 3690 s$(4)="############            "
 3710 s$(5)="############            "
 3730 s$(6)="############            "
 3750 s$(7)=" ##########             "
 3770 s$(8)="  ########              "
 3790 s$(9)="     ##                 "
 3810 sn=0:gosub 5650
 3830 s$(0)="     ##                 "
 3850 s$(1)="  ########              "
 3870 s$(2)=" ###########            "
 3890 s$(3)="##########              "
 3910 s$(4)="#######                 "
 3930 s$(5)="#######                 "
 3950 s$(6)="##########              "
 3970 s$(7)=" ###########            "
 3990 s$(8)="  ########              "
 4010 s$(9)="     ##                 "
 4030 sn=1:gosub 5650
 4050 s$(0)="     ##                 "
 4070 s$(1)="  ########              "
 4090 s$(2)="###########             "
 4110 s$(3)="  ##########            "
 4130 s$(4)="      ######            "
 4150 s$(5)="      ######            "
 4170 s$(6)="  ##########            "
 4190 s$(7)="###########             "
 4210 s$(8)="  ########              "
 4230 s$(9)="     ##                 "
 4250 sn=2:gosub 5650
 4270 s$(0)="                        "
 4290 s$(1)="                        "
 4310 s$(2)=" #        #             "
 4330 s$(3)="###      ###            "
 4350 s$(4)="####    ####            "
 4370 s$(5)="#####  #####            "
 4390 s$(6)="############            "
 4410 s$(7)=" ##########             "
 4430 s$(8)="   #######              "
 4450 s$(9)="     ##                 "
 4470 sn=3:gosub 5650
 4490 s$(0)="     ###                "
 4510 s$(1)="   #######              "
 4530 s$(2)=" ##########             "
 4550 s$(3)="############            "
 4570 s$(4)="#####  #####            "
 4590 s$(5)="####    ####            "
 4610 s$(6)="###      ###            "
 4630 s$(7)=" #        #             "
 4650 s$(8)="                        "
 4670 s$(9)="                        "
 4690 sn=4:gosub 5650
 4710 s$(0)="      ##                "
 4730 s$(1)="   ########             "
 4750 s$(2)=" ############           "
 4770 s$(3)="##############          "
 4790 s$(4)="######  ######          "
 4810 s$(5)="#####    #####          "
 4830 s$(6)="####      ####          "
 4850 s$(7)=" ##        ##           "
 4870 s$(8)="                        "
 4890 s$(9)="                        "
 4910 sn=5:gosub 5650
 4930 s$(0)="      ##                "
 4950 s$(1)="   ########             "
 4970 s$(2)=" ##   ##   ##           "
 4990 s$(3)="### # ## # ###          "
 5010 s$(4)="###   ##   ###          "
 5030 s$(5)="##############          "
 5050 s$(6)="##############          "
 5070 s$(7)="##############          "
 5090 s$(8)="##############          "
 5110 s$(9)="##  ##  ##  ##          "
 5130 sn=6:gosub 5650
 5150 sn=7:gosub 5650
 5170 sn=8:gosub 5650
 5190 sn=9:gosub 5650
 5210 s$(0)="                        "
 5230 s$(1)="                        "
 5250 s$(2)=" #        #             "
 5270 s$(3)="###      ###            "
 5290 s$(4)="####    ####            "
 5310 s$(5)="#####  #####            "
 5330 s$(6)="############            "
 5350 s$(7)=" ##########             "
 5370 s$(8)="   #######              "
 5390 s$(9)="     ##                 "
 5410 sn=10:gosub 5650
 5430 s$(1)="                        "
 5450 s$(2)="                        "
 5470 s$(3)="                        "
 5490 s$(4)="##        ##            "
 5510 s$(5)="###      ###            "
 5530 s$(6)="############            "
 5550 s$(7)=" ##########             "
 5570 s$(8)="   #######              "
 5590 s$(9)="     ##                 "
 5610 sn=11:gosub 5650
 5611 s$(1)="                        "
 5612 s$(2)="                        "
 5613 s$(3)="                        "
 5614 s$(4)="                        "
 5615 s$(5)="                        "
 5616 s$(6)="   ######               "
 5617 s$(7)=" ####  ####             "
 5618 s$(8)="                        "
 5619 s$(9)="                        "
 5620 sn=12:gosub 5650
 5630 return
 5650 rem build sprite
 5670 fort=10to20:s$(t)="                        ":nextt
 5690 fort=0to20
 5710  forb=1to24 step 8
 5730   x$=mid$(s$(t),b,8):v=0
 5750   forz=1to8
 5770    if mid$(x$,z,1)="#" then v=v+2^(8-z)
 5790   nextz
 5810  sp$(sn)=sp$(sn)+chr$(v)
 5830  nextb
 5850 nextt
 5870 sp$(sn)=sp$(sn)+chr$(0)
 5890 return
 5910 rem new game music
 5930 play"o4 sc o5 c o4 g e o5 c o4 g e r o4 d$ o5 d$ o4 a$ f o5 d$ o4 a$ f r             o4 sc o5 c o4 g e o5 c o4 g e o4 se f# f g a b o5 c"
 5950 return
 5970 rem starting actor values
 5990 rem ac(x,y) - x = actor number (0=pacman,1=blinky,2=pinky,3=inky,4=clyde)
 6010 rem           y = data (0=color,1=direction,2=speed,3=x,4=y)
 6030 ac(0,0)=7  :ac(1,0)=2  :ac(2,0)=4  :ac(3,0)=3  :ac(4,0)=18
 6050 ac(0,1)=270:ac(1,1)=90 :ac(2,1)=90 :ac(3,1)=90 :ac(4,1)=270
 6070 ac(0,2)=0  :ac(1,2)=0  :ac(2,2)=0  :ac(3,2)=0  :ac(4,2)=0
 6090 ac(0,3)=126:ac(1,3)=126:ac(2,3)=110:ac(3,3)=126:ac(4,3)=142
 6110 ac(0,4)=177:ac(1,4)=113:ac(2,4)=129:ac(3,4)=129:ac(4,4)=129
 6130 return:rem 129
 6150 mt=ti
 6170 et=ti-mt
 6190 if et>0.25 then poke53280,x::mt=ti:x=x+1
 6210 print et
 6230 goto 6170
