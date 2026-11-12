FX=1510;IVA=1.21
def cd(t):
    n=t/IVA/FX; g=t/FX
    return n-(n*0.095+g*0.012/IVA+g*0.012*0.835)
capex=10399834/FX; cash=((2900000*1.25)/IVA+704000/IVA+800000+420000+180000/IVA)/FX/12
dep=capex*0.25/24
def run(N,t,occ_ss,fix=10760):
  fleet=[10]*4+[20,30,40,N]+[N]*4
  occ=[0.5,0.65,0.75,occ_ss]+[occ_ss]*8
  fixm=[6000]*4+[fix]*8
  setup=60000; debt=0; cum=-setup; low=cum; E=0; R=0; prev=0; credit=0
  for m in range(12):
    add=fleet[m]-prev; prev=fleet[m]
    if m<4: cum-=add*capex
    else:
      if m==4: credit+=10*capex*.7; cum+=10*capex*.7; debt+=10*capex*.7
      credit+=add*capex*.7; debt+=add*capex*.7; cum-=add*capex*.3
    rev=30.4*occ[m]*cd(t); it=debt*.14/12; am=debt/36; debt-=am
    e=fleet[m]*(rev-cash)-fixm[m]; E+=e; R+=e-fleet[m]*dep-it; cum+=e-it-am; low=min(low,cum)
  ss=N*(30.4*occ_ss*cd(t)-cash)-fix
  res=ss-N*dep-capex*.7*N*.6*.14/12
  be_full=(fix/N+cash+dep+capex*.7*.6*.14/12)/(30.4*cd(t))
  return credit,E,R,low,ss,res,be_full
print("N tarifa occ | credito | EBITDA a1 | res a1 | capital propio max | EBITDA/mes regimen | resultado/mes regimen | ocup. equilibrio")
for N in [50]:
  for t in [50000,55000]:
    for o in [0.70,0.80,0.85]:
      c,E,R,low,ss,res,be=run(N,t,o)
      print(f"{N} {t} {o:.0%} | {c:,.0f} | {E:,.0f} | {R:,.0f} | {-low:,.0f} | {ss:,.0f} | {res:,.0f} | {be:.0%}")
