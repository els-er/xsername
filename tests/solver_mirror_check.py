# Python mirror of CEvePriceRiskCalculator::SolveGroupSL, EveFormatIDR and SumFloating (same arithmetic).
# Used to cross-check the expected values hard-coded in MQL5/Scripts/EVE_Risk_UnitTests.mq5.
# Run: python3 tests/solver_mirror_check.py
import math
EPS=1e-7
K=1600000.0
def profit(t,vol,op,cl): return ((cl-op) if t=='B' else (op-cl))*vol*K
def more_prot(t,c,r):
    if c<=0: return False
    if r<=0: return True
    return c>r if t=='B' else c<r
def locks(t,sl,op):
    if sl<=0: return False
    return sl>=op if t=='B' else sl<=op
def eff(p,price,preserve):
    t,vol,op,sl=p
    if sl<=0: return price
    if not preserve and not locks(t,sl,op): return price
    return sl if more_prot(t,sl,price) else price
def gloss(g,price,preserve):
    return sum(max(0.0,-profit(p[0],p[1],p[2],eff(p,price,preserve))) for p in g)
def pfi(k,ts,d): return round(k*ts,d)
def solve(g,bid,ask,stops,budget,buf=1,preserve=True,ts=0.01,pt=0.01,d=2):
    t=g[0][0]; md=stops*pt+buf*ts
    if t=='B':
        ml=bid-md; kL=math.floor(ml/ts+1e-9)
        while kL>0 and kL*ts>ml+ts*1e-6: kL-=1
        pl=pfi(kL,ts,d); l=gloss(g,pl,preserve)
        if l>budget+EPS: return ('UNSAT',pl,l)
        lo,hi=1,kL
        if gloss(g,pfi(lo,ts,d),preserve)<=budget+EPS: kb=lo
        else:
            while hi-lo>1:
                m=lo+(hi-lo)//2
                if gloss(g,pfi(m,ts,d),preserve)<=budget+EPS: hi=m
                else: lo=m
            kb=hi
        sl=pfi(kb,ts,d); return ('OK',sl,gloss(g,sl,preserve))
    else:
        ml=ask+md; kL=math.ceil(ml/ts-1e-9)
        while kL*ts<ml-ts*1e-6: kL+=1
        pl=pfi(kL,ts,d); l=gloss(g,pl,preserve)
        if l>budget+EPS: return ('UNSAT',pl,l)
        lo=hi=kL; step=max(kL,1); bounded=False; mx=max(ask,1)*10000
        for _ in range(64):
            c=hi+step
            if c*ts>mx: break
            if gloss(g,pfi(c,ts,d),preserve)>budget+EPS: hi=c; bounded=True; break
            lo=hi=c; step*=2
        if bounded:
            while hi-lo>1:
                m=lo+(hi-lo)//2
                if gloss(g,pfi(m,ts,d),preserve)<=budget+EPS: lo=m
                else: hi=m
        sl=pfi(lo,ts,d); return ('OK',sl,gloss(g,sl,preserve))
B=500000.0
cases={
 'T11 BUY 0.10@2000':([('B',0.10,2000.00,0)],2000.00,2000.20,0),
 'T11 SELL 0.10@2000':([('S',0.10,2000.00,0)],2000.00,2000.20,0),
 'T12 basket 0.1/0.2/0.3':([('B',0.10,2000.00,0),('B',0.20,1999.00,0),('B',0.30,1998.00,0)],2000.00,2000.20,0),
 'T13 user 0.02@2006.25 + 0.05@2000.20':([('B',0.02,2006.25,0),('B',0.05,2000.20,0)],2000.00,2000.20,0),
 'T15 1 lot stops 500':([('B',1.00,2000.00,0)],2000.00,2000.20,500),
 'T15 already beyond':([('B',0.10,2004.00,0)],2000.00,2000.20,0),
 'T17 preserved tighter':([('B',0.10,2000.00,1999.00),('B',0.10,2000.00,0)],2000.00,2000.20,0),
}
for name,(g,bid,ask,st) in cases.items():
    r=solve(g,bid,ask,st,B)
    extra=''
    if r[0]=='OK':
        step=-0.01 if g[0][0]=='B' else 0.01
        extra=' | one tick further loss %.2f'%gloss(g,round(r[1]+step,2),True)
    print('%-40s %s SL=%.2f loss=%.2f%s'%(name,r[0],r[1],r[2],extra))
print('T13 consumed at bid', gloss([('B',0.02,2006.25,0),('B',0.05,2000.20,0)],2000.00,True))
# formatter mirror
def fmt(v):
    r=math.floor(abs(v)+0.5)*(1 if v>=0 else -1)
    neg=r<0; a=int(abs(r)); s=str(a); out=''
    for i,ch in enumerate(s):
        if i>0 and (len(s)-i)%3==0: out+='.'
        out+=ch
    return ('-Rp' if neg and a!=0 else 'Rp')+out
for v in [0,999,1000,500000,1000000,10500000,-500000,-0.4,499999.5,9e12]:
    print(v,fmt(v))
# T8 sums
print(round(sum([-166666.67,-166666.67,-166666.66]),2), sum([-166666.67,-166666.67,-166666.66]))
print(round(sum([-166666.67,-166666.67,-166666.65]),2))
print(math.floor(500000*(0.1/0.6)),math.floor(500000*(0.2/0.6)),math.floor(500000*(0.3/0.6)))
