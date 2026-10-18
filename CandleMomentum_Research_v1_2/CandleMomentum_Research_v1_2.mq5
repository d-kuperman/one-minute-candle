#property strict
#property version "1.20"
#property description "Closed-candle momentum and independent tick-path research. No external libraries."

enum ENUM_RANGE_FILTER { RANGE_PIPS, RANGE_ATR, RANGE_PIPS_AND_ATR, RANGE_DISABLED };
enum ENUM_RUN_MODE { MODE_TRADING, MODE_RESEARCH };
// Contiguous optimization values: avoid thousands of invalid ENUM_TIMEFRAMES gaps.
enum ENUM_SIGNAL_TF { SIGNAL_M1,SIGNAL_M3,SIGNAL_M5,SIGNAL_M15,SIGNAL_M30,SIGNAL_H1,SIGNAL_H2,SIGNAL_H4 };
enum ENUM_ATR_TF { SAME_AS_SIGNAL };
input ENUM_RUN_MODE InpMode=MODE_TRADING;
input ENUM_SIGNAL_TF InpSignalTimeframe=SIGNAL_M1;
input double InpMinBodyPercent=80.0;
input ENUM_RANGE_FILTER InpRangeFilter=RANGE_PIPS;
input double InpMinRangePips=2.0;
input double InpMinRangeATR=0.8;
input double InpMaxRangePips=0.0;
input double InpMaxRangeATR=0.0;
input int InpATRPeriod=14;
input ENUM_ATR_TF InpATRTimeframe=SAME_AS_SIGNAL;
input double InpRR=1.0;
input double InpRiskPercent=1.0;
input bool InpUseSpreadFilter=true;
input double InpMaxSpreadPips=1.0;
input bool InpAllowSameDirectionPositions=true;
input int InpMaxConcurrentPositions=0;
input double InpMaxAggregateRiskPercent=0.0;
input ulong InpMagic=120017;
input int InpDeviationPoints=10;
input int InpResearchMaxBars=50;
input double InpResearchMinBodyPercent=0.0;
input int InpMinTradesForScore=50;
input bool InpEnableTelemetry=true;
input string InpRunLabel="CMR";
input string InpServerTimezone="UNKNOWN";
input double InpSummaryPipBinWidth=2.0;

const double PIP=0.0001;
double levels[7]={0.5,1.0,1.5,2.0,3.0,4.0,5.0};
ENUM_TIMEFRAMES tf;
int atr_handle=INVALID_HANDLE;
double tick_size,point_size,initial_balance;
int digits;
bool hedging,ready=false,finished=false,io_failed=false;
datetime last_bar=0;
long first_tick=0,last_tick=0,ticks_seen=0,bad_ticks=0,missed_bars=0,data_failures=0;
long candidates=0,signals=0,observations=0,trades_count=0,censored_count=0;
long count_body=0,count_pips=0,count_atr=0,count_combined=0;
ulong signature=14695981039346656037;
string run_id,folder;
int fsignal=INVALID_HANDLE,ftrade=INVALID_HANDLE,fevent=INVALID_HANDLE;
int fresearch=INVALID_HANDLE,flevel=INVALID_HANDLE,fsummary=INVALID_HANDLE,fmeta=INVALID_HANDLE;

struct Signal {
 string id; datetime time,entry_bar; int side; double o,h,l,c,range_pips,body_pips,body_pct,upper,lower;
 double atr,range_atr,spread,entry,sl,tp,r,risk_money,lots; long entry_msc;
 bool atr_valid,body_ok,pips_ok,atr_ok,combined,executable,path_valid; string reject;
};
struct Excursion { double mfe,mae; long mfe_time,mae_time; };
struct Observation { Signal s; Excursion e; int state[7]; long arrival[7]; };
Observation active[];
struct TradeTrack {
 Signal s; ulong order,position_id,position_ticket; double entry,volume,risk_effective;
 long entry_msc; Excursion e; bool dirty; double close_min,close_max; long min_time,max_time;
 string risk_deals; bool risk_anomaly;
};
TradeTrack tracked[];
struct Group {
 string dimension,key; long total,valid,censored;
 long hits[7],stops[7],unresolved[7];
 double sum_mfe,sum_mae,sum_mfe_pips,sum_mae_pips,sum_sl;
 double mfes[],maes[],mfe_pips[],mae_pips[];
};
Group groups[];

string N(double x,int precision=10) { return DoubleToString(x,precision); }
string I(long x) { return IntegerToString(x); }
string U(ulong x) { return StringFormat("%I64u",x); }
string B(bool x) { return x?"1":"0"; }
string D(int side) { return side>0?"BUY":"SELL"; }
string Q(string x) { StringReplace(x,"\"","\"\""); return "\""+x+"\""; }
string T(datetime t) { return TimeToString(t,TIME_DATE|TIME_SECONDS); }
bool GoodQuote(const MqlTick &q) { return q.time_msc>0 && q.bid>0 && q.ask>=q.bid && MathIsValidNumber(q.ask) && MathIsValidNumber(q.bid); }
void Write(int file,string row) {
 if(file==INVALID_HANDLE) return;
 if(FileWriteString(file,row+"\r\n")==0) { io_failed=true; Print("CSV WRITE ERROR ",GetLastError()); }
}
int OpenCSV(string name,string header) {
 int f=FileOpen(folder+"\\"+name,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
 if(f==INVALID_HANDLE) { Print("Cannot open ",name,": ",GetLastError()); return f; }
 Write(f,header); return f;
}
void Event(string kind,string id,string detail,ulong order=0,ulong deal=0,ulong pos=0,uint retcode=0) {
 Write(fevent,Q(run_id)+","+I(last_tick)+","+Q(kind)+","+Q(id)+","+U(order)+","+U(deal)+","+U(pos)+","+I(retcode)+","+Q(detail));
}
void Reason(string &r,string x) { if(r!="") r+="|"; r+=x; }
void HashSignal(string id) {
 for(int j=0;j<StringLen(id);j++) { signature^=(ulong)StringGetCharacter(id,j); signature*=1099511628211; }
 signature^=10; signature*=1099511628211;
}
bool PipsMode() { return InpRangeFilter==RANGE_PIPS || InpRangeFilter==RANGE_PIPS_AND_ATR; }
bool ATRMode() { return InpRangeFilter==RANGE_ATR || InpRangeFilter==RANGE_PIPS_AND_ATR; }
bool AtLeast(double value,double threshold) { return value+1e-8>=threshold; }
bool AtMost(double value,double threshold) { return threshold==0 || value<=threshold+1e-8; }
double RoundTick(double p) { return NormalizeDouble(MathRound(p/tick_size)*tick_size,digits); }
bool OnGrid(double p) { return MathAbs(p-RoundTick(p))<=tick_size*1e-6; }
ENUM_ORDER_TYPE OrderSide(int side) { return side>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL; }
ENUM_TIMEFRAMES SignalPeriod(ENUM_SIGNAL_TF selected) {
 ENUM_TIMEFRAMES periods[8]={PERIOD_M1,PERIOD_M3,PERIOD_M5,PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H2,PERIOD_H4};
 if((int)selected<0 || (int)selected>7) return PERIOD_CURRENT;
 return periods[(int)selected];
}

// Pure candle/quote transform, also used by the executable unit-test script.
bool MakeSignal(const MqlRates &v,const MqlTick &q,datetime bar,double atr_value,bool atr_available,Signal &s) {
 if(v.time>=bar || v.high<=v.low || v.close==v.open || v.low<=0 || v.high<MathMax(v.open,v.close) || v.low>MathMin(v.open,v.close)) return false;
 ZeroMemory(s); s.time=v.time; s.entry_bar=bar; s.side=v.close>v.open?1:-1;
 s.id=_Symbol+"_"+I((int)tf)+"_"+I(v.time)+"_"+D(s.side);
 s.o=v.open; s.h=v.high; s.l=v.low; s.c=v.close;
 s.range_pips=(v.high-v.low)/PIP; s.body_pips=MathAbs(v.close-v.open)/PIP;
 s.body_pct=100*s.body_pips/s.range_pips;
 s.upper=(v.high-MathMax(v.open,v.close))/PIP; s.lower=(MathMin(v.open,v.close)-v.low)/PIP;
 s.atr_valid=atr_available && MathIsValidNumber(atr_value) && atr_value>0 && atr_value!=EMPTY_VALUE;
 if(s.atr_valid) { s.atr=atr_value; s.range_atr=(v.high-v.low)/s.atr; }
 s.body_ok=AtLeast(s.body_pct,InpMinBodyPercent);
 s.pips_ok=AtLeast(s.range_pips,InpMinRangePips) && AtMost(s.range_pips,InpMaxRangePips);
 s.atr_ok=s.atr_valid && AtLeast(s.range_atr,InpMinRangeATR) && AtMost(s.range_atr,InpMaxRangeATR);
 s.combined=s.body_ok && (!PipsMode() || s.pips_ok) && (!ATRMode() || s.atr_ok);
 s.entry=s.side>0?q.ask:q.bid; s.sl=s.side>0?s.l:s.h; s.r=s.side*(s.entry-s.sl);
 s.path_valid=s.r>0; s.entry_msc=q.time_msc; s.spread=(q.ask-q.bid)/PIP;
 s.tp=s.path_valid?RoundTick(s.entry+s.side*s.r*InpRR):0;
 return true;
}
// Read only shift 1 (trigger) and ATR shift 2. No retry after this bar's first event.
bool ReadSignal(const MqlTick &q,datetime bar,Signal &s) {
 MqlRates rates[1];
 if(CopyRates(_Symbol,tf,1,1,rates)!=1) { data_failures++; return false; }
 double a[1]={0};
 bool available=BarsCalculated(atr_handle)>=InpATRPeriod+3 && CopyBuffer(atr_handle,0,2,1,a)==1;
 if(!MakeSignal(rates[0],q,bar,a[0],available,s)) return false;
 candidates++; if(s.body_ok) count_body++; if(s.pips_ok) count_pips++; if(s.atr_ok) count_atr++;
 if(s.combined) { count_combined++; signals++; HashSignal(s.id); }
 return true;
}

double DirectionVolume(int side) {
 double used=0;
 for(int j=PositionsTotal()-1;j>=0;j--) if(PositionGetTicket(j)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1)==side) used+=PositionGetDouble(POSITION_VOLUME);
 for(int j=OrdersTotal()-1;j>=0;j--) if(OrderGetTicket(j)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol) {
  ENUM_ORDER_TYPE t=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
  bool buy=t==ORDER_TYPE_BUY || t==ORDER_TYPE_BUY_LIMIT || t==ORDER_TYPE_BUY_STOP || t==ORDER_TYPE_BUY_STOP_LIMIT;
  if((buy?1:-1)==side) used+=OrderGetDouble(ORDER_VOLUME_CURRENT);
 }
 return used;
}
double FloorVolume(double raw,double step) { return NormalizeDouble(MathFloor((raw+step*1e-10)/step)*step,8); }
// Research checks the actual account snapshot; virtual observations never consume portfolio capacity.
void ValidateCommercial(Signal &s,const MqlTick &q) {
 s.reject="";
 if(!hedging && InpAllowSameDirectionPositions && InpMaxConcurrentPositions!=1) Reason(s.reject,"NETTING_CONFIGURATION");
 if(!s.combined) Reason(s.reject,"FILTERS");
 if(ATRMode() && !s.atr_valid) Reason(s.reject,"ATR_UNAVAILABLE");
 if(!s.path_valid) Reason(s.reject,"SL_WRONG_SIDE");
 if(InpUseSpreadFilter && s.spread>InpMaxSpreadPips+1e-8) Reason(s.reject,"SPREAD");
 if(!OnGrid(s.sl)) Reason(s.reject,"SL_OFF_TICK_GRID");
 double minstop=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*point_size;
 double close=s.side>0?q.bid:q.ask;
 if(s.side*(close-s.sl)<=0 || s.side*(close-s.sl)+1e-10<minstop || s.side*(s.tp-close)<=0 || s.side*(s.tp-close)+1e-10<minstop) Reason(s.reject,"STOPS_LEVEL");
 long mode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
 if(mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY || (mode==SYMBOL_TRADE_MODE_LONGONLY && s.side<0) || (mode==SYMBOL_TRADE_MODE_SHORTONLY && s.side>0)) Reason(s.reject,"SYMBOL_TRADE_MODE");
 long flags=SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
 if((flags&SYMBOL_ORDER_MARKET)==0 || (flags&SYMBOL_ORDER_SL)==0 || (flags&SYMBOL_ORDER_TP)==0) Reason(s.reject,"ORDER_MODE");
 int own=0; double aggregate=0; bool aggregate_valid=true;
 for(int j=PositionsTotal()-1;j>=0;j--) if(PositionGetTicket(j)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol) {
  if(!hedging && PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic) Reason(s.reject,"NETTING_FOREIGN_POSITION");
  if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic) continue;
  own++; int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
  if(side!=s.side) Reason(s.reject,"OPPOSITE_POSITION");
  if(side==s.side && (!InpAllowSameDirectionPositions || !hedging)) Reason(s.reject,"SAME_DIRECTION_POSITION");
  double loss=0,sl=PositionGetDouble(POSITION_SL);
  if(sl<=0 || !OrderCalcProfit(OrderSide(side),_Symbol,PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),sl,loss)) aggregate_valid=false;
  else aggregate+=MathMax(0,-loss);
 }
 if(InpMaxConcurrentPositions>0 && own>=InpMaxConcurrentPositions) Reason(s.reject,"POSITION_LIMIT");
 // Any unsettled own market request blocks new entries, avoiding unaccounted risk.
 for(int j=0;j<ArraySize(tracked);j++) {
  ulong settled_ticket=0;
  if(tracked[j].position_id==0 || OrderSelect(tracked[j].order) || !PositionByID(tracked[j].position_id,settled_ticket)) { Reason(s.reject,"REQUEST_UNSETTLED"); break; }
 }
 s.risk_money=AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPercent/100;
 double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
 double probe=0;
 if(!s.path_valid || !OrderCalcProfit(OrderSide(s.side),_Symbol,vmin,s.entry,s.sl,probe) || probe>=0) { Reason(s.reject,"RISK_CALCULATION"); s.executable=false; return; }
 double loss_per_lot=-probe/vmin;
 double cap=vmax,limit=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT);
 if(limit>0) cap=MathMin(cap,MathMax(0,limit-DirectionVolume(s.side)));
 s.lots=FloorVolume(MathMin(s.risk_money/loss_per_lot,cap),step);
 if(s.lots<vmin-1e-10) Reason(s.reject,"VOLUME_BELOW_MINIMUM");
 if(s.lots*loss_per_lot>s.risk_money+1e-7) Reason(s.reject,"RISK_ROUNDING");
 if(InpMaxAggregateRiskPercent>0 && (!aggregate_valid || aggregate+s.lots*loss_per_lot>AccountInfoDouble(ACCOUNT_BALANCE)*InpMaxAggregateRiskPercent/100+1e-7)) Reason(s.reject,"AGGREGATE_RISK");
 double margin=0;
 if(s.lots>=vmin && (!OrderCalcMargin(OrderSide(s.side),_Symbol,s.lots,s.entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))) Reason(s.reject,"MARGIN");
 s.executable=s.reject=="";
}

string SignalHeader() {
 return "RunID,SignalID,Timeframe,SignalTime,SignalTimestamp,Direction,Open,High,Low,Close,RangePips,BodyPips,BodyPercent,UpperWickPips,LowerWickPips,ATRReference,ATRPips,RangeATR,ATRValid,EntryTimeMsc,EntryBar,SpreadPips,ExpectedEntry,SL,TP,ExpectedRiskPips,BodyPass,PipsPass,ATRPass,CombinedPass,PathValid,CommercialExecutable,RejectReason,RequestedRiskMoney,ExpectedLots";
}
string SignalRow(const Signal &s) {
 return Q(run_id)+","+Q(s.id)+","+Q(EnumToString(tf))+","+Q(T(s.time))+","+I(s.time)+","+D(s.side)+","+N(s.o)+","+N(s.h)+","+N(s.l)+","+N(s.c)+","+N(s.range_pips)+","+N(s.body_pips)+","+N(s.body_pct)+","+N(s.upper)+","+N(s.lower)+","+(s.atr_valid?N(s.atr):"")+","+(s.atr_valid?N(s.atr/PIP):"")+","+(s.atr_valid?N(s.range_atr):"")+","+B(s.atr_valid)+","+I(s.entry_msc)+","+I(s.entry_bar)+","+N(s.spread)+","+N(s.entry)+","+N(s.sl)+","+N(s.tp)+","+N(s.r/PIP)+","+B(s.body_ok)+","+B(s.pips_ok)+","+B(s.atr_ok)+","+B(s.combined)+","+B(s.path_valid)+","+B(s.executable)+","+Q(s.reject)+","+N(s.risk_money)+","+N(s.lots,8);
}
string ExcursionHeader() { return "MFE_Pips,MAE_Pips,MFE_R,MAE_R,MFE_TimeMsc,MAE_TimeMsc"; }
string ExcursionRow(const Excursion &e,double r) { return N(e.mfe/PIP)+","+N(e.mae/PIP)+","+(r>0?N(e.mfe/r):"")+","+(r>0?N(e.mae/r):"")+","+I(e.mfe_time)+","+I(e.mae_time); }
void Observe(Excursion &e,int side,double entry,double close,long msc) {
 double move=side*(close-entry);
 if(move>e.mfe) { e.mfe=move; e.mfe_time=msc; }
 if(-move>e.mae) { e.mae=-move; e.mae_time=msc; }
}

string BodyBin(double x) {
 if(x<50-1e-8) return "[0,50)"; if(x<60-1e-8) return "[50,60)"; if(x<70-1e-8) return "[60,70)";
 if(x<80-1e-8) return "[70,80)"; if(x<90-1e-8) return "[80,90)"; if(x<95-1e-8) return "[90,95)"; return "[95,100]";
}
string ATRBin(const Signal &s) {
 if(!s.atr_valid) return "MISSING"; double x=s.range_atr;
 if(x<0.5) return "[0,0.5)"; if(x<0.75) return "[0.5,0.75)"; if(x<1) return "[0.75,1)";
 if(x<1.25) return "[1,1.25)"; if(x<1.5) return "[1.25,1.5)"; if(x<2) return "[1.5,2)"; if(x<3) return "[2,3)"; return "[3,inf)";
}
void GroupAdd(string dim,string key,const Observation &o,string end) {
 int g=-1;
 for(int j=0;j<ArraySize(groups);j++) if(groups[j].dimension==dim && groups[j].key==key) { g=j; break; }
 if(g<0) { g=ArraySize(groups); ArrayResize(groups,g+1); ZeroMemory(groups[g]); groups[g].dimension=dim; groups[g].key=key; }
 groups[g].total++;
 if(!o.s.path_valid) return;
 groups[g].valid++; if(StringFind(end,"CENSORED_")==0) groups[g].censored++;
 double mfe=o.e.mfe/o.s.r,mae=o.e.mae/o.s.r; int n=ArraySize(groups[g].mfes);
 ArrayResize(groups[g].mfes,n+1,1024); ArrayResize(groups[g].maes,n+1,1024);
 ArrayResize(groups[g].mfe_pips,n+1,1024); ArrayResize(groups[g].mae_pips,n+1,1024);
 groups[g].mfes[n]=mfe; groups[g].maes[n]=mae; groups[g].mfe_pips[n]=o.e.mfe/PIP; groups[g].mae_pips[n]=o.e.mae/PIP;
 groups[g].sum_mfe+=mfe; groups[g].sum_mae+=mae; groups[g].sum_mfe_pips+=o.e.mfe/PIP; groups[g].sum_mae_pips+=o.e.mae/PIP; groups[g].sum_sl+=o.s.r/PIP;
 for(int k=0;k<7;k++) { if(o.state[k]==1) groups[g].hits[k]++; else if(o.state[k]==2) groups[g].stops[k]++; else groups[g].unresolved[k]++; }
}
void Aggregate(const Observation &o,string end) {
 if(!InpEnableTelemetry) return;
 MqlDateTime dt; TimeToStruct(o.s.time,dt);
 double bin=MathFloor(o.s.range_pips/InpSummaryPipBinWidth)*InpSummaryPipBinWidth;
 GroupAdd("ALL","ALL",o,end); GroupAdd("TIMEFRAME",EnumToString(tf),o,end);
 GroupAdd("BODY",BodyBin(o.s.body_pct),o,end); GroupAdd("RANGE_ATR",ATRBin(o.s),o,end);
 GroupAdd("RANGE_PIPS","["+N(bin,2)+","+N(bin+InpSummaryPipBinWidth,2)+")",o,end);
 GroupAdd("DIRECTION",D(o.s.side),o,end); GroupAdd("SERVER_HOUR",I(dt.hour),o,end);
}
double Median(double &values[]) { int n=ArraySize(values); if(n==0) return 0; ArraySort(values); return n%2==1?values[n/2]:(values[n/2-1]+values[n/2])/2; }
void Summary() {
 for(int g=0;g<ArraySize(groups);g++) {
  double n=(double)groups[g].valid;
  string metrics=n>0?N(groups[g].sum_mfe/n)+","+N(Median(groups[g].mfes))+","+N(groups[g].sum_mae/n)+","+N(Median(groups[g].maes))+","+N(groups[g].sum_mfe_pips/n)+","+N(Median(groups[g].mfe_pips))+","+N(groups[g].sum_mae_pips/n)+","+N(Median(groups[g].mae_pips))+","+N(groups[g].sum_sl/n):",,,,,,,,";
  for(int k=0;k<7;k++) {
   long resolved=groups[g].hits[k]+groups[g].stops[k];
   Write(fsummary,Q(run_id)+","+Q(groups[g].dimension)+","+Q(groups[g].key)+","+I(groups[g].total)+","+I(groups[g].valid)+","+I(groups[g].censored)+","+N(levels[k],1)+","+I(groups[g].hits[k])+","+I(groups[g].stops[k])+","+I(groups[g].unresolved[k])+","+I(resolved)+","+(resolved>0?N(100.0*groups[g].hits[k]/resolved):"")+","+(n>0?N(100.0*groups[g].hits[k]/n):"")+","+metrics);
  }
 }
}
void FinishObservation(const Observation &o,string end,long msc) {
 if(StringFind(end,"CENSORED_")==0) censored_count++;
 Write(fresearch,SignalRow(o.s)+","+ExcursionRow(o.e,o.s.r)+","+Q(end)+","+I(msc));
 for(int k=0;k<7;k++) {
  string outcome=!o.s.path_valid?"NOT_EXECUTABLE":o.state[k]==1?"TARGET_BEFORE_SL":o.state[k]==2?"SL_BEFORE_TARGET":end;
  Write(flevel,Q(run_id)+","+Q(o.s.id)+","+N(levels[k],1)+","+Q(outcome)+","+(o.arrival[k]>0?I(o.arrival[k]):"")+","+I(msc));
 }
 Aggregate(o,end);
}
void RemoveObservation(int j) { int n=ArraySize(active); if(j<n-1) active[j]=active[n-1]; ArrayResize(active,n-1); }
// Expiry checked before the boundary tick: observation interval [entry, N-bar boundary).
void ExpireResearch(const MqlTick &q) {
 for(int j=ArraySize(active)-1;j>=0;j--) {
  int age=iBarShift(_Symbol,tf,active[j].s.entry_bar,true);
  if(age<0) { FinishObservation(active[j],"CENSORED_DATA_GAP",q.time_msc); RemoveObservation(j); continue; }
  if(age>=InpResearchMaxBars) { FinishObservation(active[j],"CENSORED_HORIZON",q.time_msc); RemoveObservation(j); continue; }
 }
}
void ResearchTick(const MqlTick &q) {
 for(int j=ArraySize(active)-1;j>=0;j--) {
  double close=active[j].s.side>0?q.bid:q.ask;
  Observe(active[j].e,active[j].s.side,active[j].s.entry,close,q.time_msc);
  double move=active[j].s.side*(close-active[j].s.entry);
  bool stop=active[j].s.side*(close-active[j].s.sl)<=1e-10;
  for(int k=0;k<7;k++) if(active[j].state[k]==0) {
   if(stop) { active[j].state[k]=2; active[j].arrival[k]=q.time_msc; }
   else if(move+1e-10>=levels[k]*active[j].s.r) { active[j].state[k]=1; active[j].arrival[k]=q.time_msc; }
  }
  if(stop) { FinishObservation(active[j],"STOP",q.time_msc); RemoveObservation(j); }
 }
}
void StartObservation(const Signal &s) {
 Observation o; ZeroMemory(o); o.s=s; observations++;
 if(!s.path_valid) { FinishObservation(o,"NOT_EXECUTABLE",s.entry_msc); return; }
 int n=ArraySize(active); ArrayResize(active,n+1,128); active[n]=o;
}

bool PositionByID(ulong id,ulong &ticket) {
 for(int j=PositionsTotal()-1;j>=0;j--) { ulong t=PositionGetTicket(j); if(t>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) { ticket=t; return true; } }
 return false;
}
void TradeQuote(TradeTrack &t,double close,long msc) {
 if(msc<t.entry_msc || close<=0) return;
 if(t.close_min==0 || close<t.close_min) { t.close_min=close; t.min_time=msc; }
 if(t.close_max==0 || close>t.close_max) { t.close_max=close; t.max_time=msc; }
 ZeroMemory(t.e);
 Observe(t.e,t.s.side,t.entry,t.close_min,t.min_time); Observe(t.e,t.s.side,t.entry,t.close_max,t.max_time);
}
void RemoveTrade(int j) { int n=ArraySize(tracked); if(j<n-1) tracked[j]=tracked[n-1]; ArrayResize(tracked,n-1); }
void AddTicket(string &list,ulong ticket) {
 string needle="|"+U(ticket)+"|";
 if(StringFind("|"+list+"|",needle)>=0) return;
 if(list!="") list+="|"; list+=U(ticket);
}
// Rebuild totals from position history, never increment them from repeated callbacks.
// Read order IDs BEFORE HistorySelectByPosition, which replaces history lists.
void ReconcileTrades() {
 for(int j=ArraySize(tracked)-1;j>=0;j--) {
  if(tracked[j].position_id==0 && HistoryOrderSelect(tracked[j].order)) tracked[j].position_id=(ulong)HistoryOrderGetInteger(tracked[j].order,ORDER_POSITION_ID);
  ulong ticket=0;
  if(tracked[j].position_id==0) {
   if(HistoryOrderSelect(tracked[j].order)) {
    long state=HistoryOrderGetInteger(tracked[j].order,ORDER_STATE);
    if(state==ORDER_STATE_REJECTED || state==ORDER_STATE_CANCELED || state==ORDER_STATE_EXPIRED) { Event("ORDER_NO_FILL",tracked[j].s.id,EnumToString((ENUM_ORDER_STATE)state),tracked[j].order); RemoveTrade(j); }
   }
   continue;
  }
  bool open=PositionByID(tracked[j].position_id,ticket);
  if(open) tracked[j].position_ticket=ticket;
  if(!tracked[j].dirty && open) continue;
  if(!HistorySelectByPosition(tracked[j].position_id)) continue;
  double inv=0,outv=0,weighted=0,exitweighted=0,cin=0,cout=0,swap=0,gross=0,fees=0;
  long entry_time=0,exit_time=0; string deals="",orders="",exit_reasons="";
  bool anomalous=false;
  for(int k=0;k<HistoryDealsTotal();k++) {
   ulong d=HistoryDealGetTicket(k); long type=HistoryDealGetInteger(d,DEAL_TYPE);
   if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
   long en=HistoryDealGetInteger(d,DEAL_ENTRY),msc=HistoryDealGetInteger(d,DEAL_TIME_MSC);
   double vol=HistoryDealGetDouble(d,DEAL_VOLUME),price=HistoryDealGetDouble(d,DEAL_PRICE);
   double commission=HistoryDealGetDouble(d,DEAL_COMMISSION);
   fees+=HistoryDealGetDouble(d,DEAL_FEE); swap+=HistoryDealGetDouble(d,DEAL_SWAP); gross+=HistoryDealGetDouble(d,DEAL_PROFIT);
   AddTicket(deals,d); AddTicket(orders,(ulong)HistoryDealGetInteger(d,DEAL_ORDER));
   if(en==DEAL_ENTRY_IN) {
    inv+=vol; weighted+=vol*price; cin+=commission;
    if(entry_time==0 || msc<entry_time) entry_time=msc;
    // Freeze each fill's monetary risk when first reconciled; do not revalue it at exit.
    if(StringFind("|"+tracked[j].risk_deals+"|","|"+U(d)+"|")<0) {
     double loss=0;
     if(OrderCalcProfit(OrderSide(tracked[j].s.side),_Symbol,vol,price,tracked[j].s.sl,loss)) tracked[j].risk_effective+=MathMax(0,-loss);
     else tracked[j].risk_anomaly=true;
     AddTicket(tracked[j].risk_deals,d);
    }
   } else if(en==DEAL_ENTRY_OUT || en==DEAL_ENTRY_OUT_BY) {
    outv+=vol; exitweighted+=vol*price; cout+=commission; exit_time=MathMax(exit_time,msc);
    string why=EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(d,DEAL_REASON));
    if(StringFind(exit_reasons,why)<0) Reason(exit_reasons,why);
   } else anomalous=true;
  }
  if(inv<=0) continue;
  tracked[j].entry=weighted/inv; tracked[j].volume=inv; tracked[j].entry_msc=entry_time;
  double effective_risk=tracked[j].risk_effective; anomalous=anomalous || tracked[j].risk_anomaly;
  // Include every partial exit execution, including gaps beyond SL/TP.
  for(int k=0;k<HistoryDealsTotal();k++) {
   ulong d=HistoryDealGetTicket(k); long en=HistoryDealGetInteger(d,DEAL_ENTRY);
   if(en==DEAL_ENTRY_OUT || en==DEAL_ENTRY_OUT_BY) TradeQuote(tracked[j],HistoryDealGetDouble(d,DEAL_PRICE),HistoryDealGetInteger(d,DEAL_TIME_MSC));
  }
  tracked[j].dirty=false;
  if(open || outv<inv-1e-8 || OrderSelect(tracked[j].order)) continue;
  double r=tracked[j].s.side*(tracked[j].entry-tracked[j].s.sl);
  double net=gross+cin+cout+swap+fees;
  double rr=r>0?tracked[j].s.side*(tracked[j].s.tp-tracked[j].entry)/r:0;
  string row=Q(run_id)+","+Q(tracked[j].s.id)+","+U(tracked[j].position_id)+","+U(tracked[j].position_ticket)+","+Q(orders)+","+Q(deals)+","+I(entry_time)+","+I(exit_time)+","+D(tracked[j].s.side)+","+Q(EnumToString(tf))+","+N(tracked[j].s.entry)+","+N(tracked[j].entry)+","+N(exitweighted/outv)+","+N(tracked[j].s.sl)+","+N(tracked[j].s.tp)+","+N(InpRR)+","+N(rr)+","+N(tracked[j].s.lots,8)+","+N(inv,8)+","+N(tracked[j].s.risk_money)+","+N(tracked[j].s.r/PIP)+","+N(r/PIP)+","+N(effective_risk)+","+N(tracked[j].s.spread)+","+N(cin)+","+N(cout)+","+N(cin+cout)+","+N(swap)+","+N(fees)+","+N(gross)+","+N(net)+","+(effective_risk>0?N(net/effective_risk):"")+","+ExcursionRow(tracked[j].e,r)+","+N((exit_time-entry_time)/1000.0,3)+","+Q(exit_reasons)+","+N(tracked[j].s.side*(tracked[j].entry-tracked[j].s.entry)/PIP)+","+B(anomalous);
  Write(ftrade,row); trades_count++;
  Event("POSITION_COMPLETE",tracked[j].s.id,exit_reasons,tracked[j].order,0,tracked[j].position_id);
  RemoveTrade(j);
 }
}
void TrackTick(const MqlTick &q) {
 for(int j=0;j<ArraySize(tracked);j++) {
  ulong ticket=0;
  if(tracked[j].entry>0 && PositionByID(tracked[j].position_id,ticket)) TradeQuote(tracked[j],tracked[j].s.side>0?q.bid:q.ask,q.time_msc);
 }
}
bool BuildRequest(const Signal &s,MqlTradeRequest &request) {
 ZeroMemory(request); request.action=TRADE_ACTION_DEAL; request.symbol=_Symbol; request.magic=InpMagic;
 request.type=OrderSide(s.side); request.volume=s.lots; request.price=s.entry; request.sl=s.sl; request.tp=s.tp;
 request.deviation=InpDeviationPoints; request.comment="CMR12_"+I(s.time);
 long fill=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
 if((fill&SYMBOL_FILLING_FOK)!=0) request.type_filling=ORDER_FILLING_FOK;
 else if((fill&SYMBOL_FILLING_IOC)!=0) request.type_filling=ORDER_FILLING_IOC;
 else return false; // Do not leave a RETURN residual pending after the entry event.
 return true;
}
bool Preflight(Signal &s,MqlTradeRequest &req) {
 if(!s.executable) return false;
 if(!BuildRequest(s,req)) { Reason(s.reject,"FILL_POLICY"); s.executable=false; return false; }
 MqlTradeCheckResult check={};
 if(!OrderCheck(req,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE)) {
  Reason(s.reject,"ORDERCHECK_"+I(check.retcode)+"_"+check.comment); s.executable=false; return false;
 }
 return true;
}
void SendSignal(Signal &s,MqlTradeRequest &req) {
 MqlTradeResult result={};
 bool sent=OrderSend(req,result);
 Event("SEND_RESULT",s.id,result.comment,result.order,result.deal,0,result.retcode);
 if(!sent || (result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL && result.retcode!=TRADE_RETCODE_PLACED)) {
  s.executable=false; Reason(s.reject,"SEND_"+I(result.retcode)); return;
 }
 TradeTrack tr; ZeroMemory(tr); tr.s=s; tr.order=result.order; tr.dirty=true;
 if(result.deal>0 && HistoryDealSelect(result.deal)) {
  tr.position_id=(ulong)HistoryDealGetInteger(result.deal,DEAL_POSITION_ID);
  if(tr.order==0) tr.order=(ulong)HistoryDealGetInteger(result.deal,DEAL_ORDER);
 }
 int n=ArraySize(tracked); ArrayResize(tracked,n+1); tracked[n]=tr;
 ReconcileTrades();
}
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result) {
 if(!ready || InpMode!=MODE_TRADING) return;
 if(trans.type==TRADE_TRANSACTION_REQUEST && request.magic==InpMagic && request.symbol==_Symbol) Event("REQUEST", "",result.comment,result.order,result.deal,0,result.retcode);
 if(trans.symbol!=_Symbol) return;
 bool own=false;
 for(int j=0;j<ArraySize(tracked);j++) if(tracked[j].order==trans.order || (trans.position>0 && tracked[j].position_ticket==trans.position)) { tracked[j].dirty=true; own=true; }
 if(trans.deal>0 && HistoryDealSelect(trans.deal)) {
  ulong pid=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
  for(int j=0;j<ArraySize(tracked);j++) if(tracked[j].position_id==pid || tracked[j].order==(ulong)HistoryDealGetInteger(trans.deal,DEAL_ORDER)) {
   tracked[j].position_id=pid; tracked[j].dirty=true; own=true;
  }
 }
 if(own) Event(EnumToString(trans.type),"",N(trans.price),trans.order,trans.deal,trans.position);
}
void OnTrade() { if(ready && InpMode==MODE_TRADING) ReconcileTrades(); }

void Meta(string key,string value) { Write(fmeta,Q(run_id)+","+Q(key)+","+Q(value)); }
void Metadata(string end) {
 Meta("Version","1.20"); Meta("Mode",EnumToString(InpMode)); Meta("Symbol",_Symbol); Meta("Timeframe",EnumToString(tf));
 Meta("FirstTickMsc",I(first_tick)); Meta("LastTickMsc",I(last_tick)); Meta("FirstObservedServerTime",first_tick>0?T((datetime)(first_tick/1000)):""); Meta("LastObservedServerTime",last_tick>0?T((datetime)(last_tick/1000)):"");
 Meta("TicksProcessed",I(ticks_seen)); Meta("InvalidTicks",I(bad_ticks)); Meta("SkippedBars",I(missed_bars)); Meta("DataFailures",I(data_failures));
 Meta("InitialBalance",N(initial_balance)); Meta("Currency",AccountInfoString(ACCOUNT_CURRENCY)); Meta("Leverage",I(AccountInfoInteger(ACCOUNT_LEVERAGE)));
 Meta("Server",AccountInfoString(ACCOUNT_SERVER)); Meta("ServerTimezone",InpServerTimezone); Meta("AccountMarginMode",EnumToString((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)));
 Meta("Point",N(point_size)); Meta("Pip",N(PIP)); Meta("TickSize",N(tick_size)); Meta("Digits",I(digits));
 Meta("TickValueProfit",N(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_PROFIT))); Meta("TickValueLoss",N(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS)));
 Meta("ContractSize",N(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE))); Meta("VolumeMin",N(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN))); Meta("VolumeMax",N(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX))); Meta("VolumeStep",N(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))); Meta("VolumeLimit",N(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT)));
 Meta("StopsLevelPoints",I(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL))); Meta("FreezeLevelPoints",I(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))); Meta("FloatingSpread",B((bool)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD_FLOAT)));
 Meta("Candidates",I(candidates)); Meta("Signals",I(signals)); Meta("BodyPassCount",I(count_body)); Meta("PipsPassCount",I(count_pips)); Meta("ATRPassCount",I(count_atr)); Meta("CombinedPassCount",I(count_combined));
 Meta("Trades",I(trades_count)); Meta("Observations",I(observations)); Meta("CensoredObservations",I(censored_count)); Meta("UnfinishedTradeRequests",I(ArraySize(tracked))); Meta("SignalSequenceFNV1a64",U(signature));
 Meta("EndReason",end); Meta("IOFailure",B(io_failed)); Meta("TickCoverage","ONTICK_ONLY_NOT_VERIFIED");
 Meta("InpMode",I(InpMode)); Meta("InpSignalTimeframe",I(InpSignalTimeframe)); Meta("InpMinBodyPercent",N(InpMinBodyPercent)); Meta("InpRangeFilter",I(InpRangeFilter));
 Meta("InpMinRangePips",N(InpMinRangePips)); Meta("InpMinRangeATR",N(InpMinRangeATR)); Meta("InpMaxRangePips",N(InpMaxRangePips)); Meta("InpMaxRangeATR",N(InpMaxRangeATR));
 Meta("InpATRPeriod",I(InpATRPeriod)); Meta("InpATRTimeframe",I(InpATRTimeframe)); Meta("InpRR",N(InpRR)); Meta("InpRiskPercent",N(InpRiskPercent));
 Meta("InpUseSpreadFilter",B(InpUseSpreadFilter)); Meta("InpMaxSpreadPips",N(InpMaxSpreadPips)); Meta("InpAllowSameDirectionPositions",B(InpAllowSameDirectionPositions)); Meta("InpMaxConcurrentPositions",I(InpMaxConcurrentPositions)); Meta("InpMaxAggregateRiskPercent",N(InpMaxAggregateRiskPercent));
 Meta("InpMagic",U(InpMagic)); Meta("InpDeviationPoints",I(InpDeviationPoints)); Meta("InpResearchMaxBars",I(InpResearchMaxBars)); Meta("InpResearchMinBodyPercent",N(InpResearchMinBodyPercent)); Meta("InpMinTradesForScore",I(InpMinTradesForScore)); Meta("InpEnableTelemetry",B(InpEnableTelemetry)); Meta("InpRunLabel",InpRunLabel); Meta("InpServerTimezone",InpServerTimezone); Meta("InpSummaryPipBinWidth",N(InpSummaryPipBinWidth));
}
bool InitCSV() {
 if(!InpEnableTelemetry) return true;
 // Agent-local sandbox + microsecond nonce + explicit collision check.
 string label=InpRunLabel; StringReplace(label,"\\","_"); StringReplace(label,"/","_"); StringReplace(label,":","_");
 run_id=label+"_"+I((long)TimeLocal())+"_"+U(GetMicrosecondCount())+"_"+U((ulong)ChartID());
 folder="CandleMomentum_Research_v1_2\\"+run_id;
 for(int k=0;FileIsExist(folder+"\\RunMetadata.csv");k++) { folder="CandleMomentum_Research_v1_2\\"+run_id+"_"+I(k); }
 run_id=StringSubstr(folder,StringLen("CandleMomentum_Research_v1_2\\"));
 fmeta=OpenCSV("RunMetadata.csv","RunID,Key,Value");
 if(InpMode==MODE_RESEARCH) {
  fresearch=OpenCSV("ResearchSignals.csv",SignalHeader()+","+ExcursionHeader()+",EndReason,EndTimeMsc");
  flevel=OpenCSV("ResearchLevels.csv","RunID,SignalID,TargetR,Outcome,ArrivalTimeMsc,ObservationEndTimeMsc");
  fsummary=OpenCSV("ResearchSummary.csv","RunID,Dimension,Group,Total,Valid,CensoredObservations,TargetR,Hits,Stops,CensoredForTarget,Resolved,HitPctResolved,HitPctAllValid,MeanMFE_R,MedianMFE_R,MeanMAE_R,MedianMAE_R,MeanMFE_Pips,MedianMFE_Pips,MeanMAE_Pips,MedianMAE_Pips,MeanSL_Pips");
  if(fresearch==INVALID_HANDLE || flevel==INVALID_HANDLE || fsummary==INVALID_HANDLE) return false;
 } else {
  fsignal=OpenCSV("Signals.csv",SignalHeader());
  ftrade=OpenCSV("Trades.csv","RunID,SignalID,PositionID,PositionTicket,OrderTickets,DealTickets,EntryTimeMsc,ExitTimeMsc,Direction,Timeframe,ExpectedEntry,ActualEntry,ActualExit,SL,TP,ExpectedRR,EffectiveRR,ExpectedLots,ExecutedLots,RequestedRiskMoney,ExpectedRiskPips,EffectiveRiskPips,EffectiveRiskMoney,SpreadPips,EntryCommission,ExitCommission,TotalCommission,Swap,Fees,GrossProfit,NetProfit,NetR,"+ExcursionHeader()+",DurationSeconds,ExitReason,EntrySlippagePips,HistoryAnomaly");
  fevent=OpenCSV("ExecutionEvents.csv","RunID,ObservedTimeMsc,Event,SignalID,OrderTicket,DealTicket,PositionIDOrTicket,Retcode,Detail");
  if(fsignal==INVALID_HANDLE || ftrade==INVALID_HANDLE || fevent==INVALID_HANDLE) return false;
 }
 Print("CSV folder: ",TerminalInfoString(TERMINAL_DATA_PATH),"\\MQL5\\Files\\",folder);
 return fmeta!=INVALID_HANDLE && !io_failed;
}
void CloseFiles() {
 int files[7]={fsignal,ftrade,fevent,fresearch,flevel,fsummary,fmeta};
 for(int j=0;j<7;j++) if(files[j]!=INVALID_HANDLE) { FileFlush(files[j]); FileClose(files[j]); }
 fsignal=ftrade=fevent=fresearch=flevel=fsummary=fmeta=INVALID_HANDLE;
}
void Finish(string reason) {
 if(finished || !ready) return; finished=true;
 ReconcileTrades();
 for(int j=0;j<ArraySize(active);j++) FinishObservation(active[j],reason=="TEST_END"?"CENSORED_TEST_END":"CENSORED_DEINIT",last_tick);
 ArrayResize(active,0);
 for(int j=0;j<ArraySize(tracked);j++) Event("UNFINISHED_AT_END",tracked[j].s.id,reason,tracked[j].order,0,tracked[j].position_id);
 Summary(); Metadata(reason); CloseFiles();
}
int OnInit() {
 tf=SignalPeriod(InpSignalTimeframe);
 if(SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE)!="EUR" || SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT)!="USD") { Print("Only EURUSD, including broker suffixes, is supported."); return INIT_PARAMETERS_INCORRECT; }
 if(tf!=PERIOD_M1 && tf!=PERIOD_M3 && tf!=PERIOD_M5 && tf!=PERIOD_M15 && tf!=PERIOD_M30 && tf!=PERIOD_H1 && tf!=PERIOD_H2 && tf!=PERIOD_H4) return INIT_PARAMETERS_INCORRECT;
 if(InpMinBodyPercent<0 || InpMinBodyPercent>100 || InpResearchMinBodyPercent<0 || InpResearchMinBodyPercent>100 || InpATRPeriod<1 || InpRR<=0 || InpRiskPercent<=0 || InpRiskPercent>100 || InpResearchMaxBars<1 || InpMinTradesForScore<1 || InpMaxConcurrentPositions<0 || InpMaxAggregateRiskPercent<0 || InpDeviationPoints<0 || InpSummaryPipBinWidth<=0 || InpMaxSpreadPips<0) return INIT_PARAMETERS_INCORRECT;
 if(InpMinRangePips<0 || InpMaxRangePips<0 || InpMinRangeATR<0 || InpMaxRangeATR<0 || (PipsMode() && InpMaxRangePips>0 && InpMaxRangePips<InpMinRangePips) || (ATRMode() && InpMaxRangeATR>0 && InpMaxRangeATR<InpMinRangeATR)) return INIT_PARAMETERS_INCORRECT;
 tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); point_size=SymbolInfoDouble(_Symbol,SYMBOL_POINT); digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
 if(tick_size<=0 || point_size<=0 || SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)<=0 || SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)<=0) return INIT_FAILED;
 hedging=AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
 if(InpMode==MODE_TRADING && !hedging && InpAllowSameDirectionPositions && InpMaxConcurrentPositions!=1) { Print("Independent concurrent entries require a HEDGING account. For netting disable same-direction entries or set maximum positions to 1."); return INIT_PARAMETERS_INCORRECT; }
 if(InpMode==MODE_TRADING) {
  for(int j=PositionsTotal()-1;j>=0;j--) if(PositionGetTicket(j)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==(long)InpMagic) { Print("Existing own position: cannot recover full excursion history on restart. Use a clean run/magic after closing it externally."); return INIT_FAILED; }
  for(int j=OrdersTotal()-1;j>=0;j--) if(OrderGetTicket(j)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_MAGIC)==(long)InpMagic) { Print("Existing own order: initialization refused."); return INIT_FAILED; }
 }
 initial_balance=AccountInfoDouble(ACCOUNT_BALANCE); atr_handle=iATR(_Symbol,tf,InpATRPeriod);
 if(atr_handle==INVALID_HANDLE) return INIT_FAILED;
 if(!InitCSV()) { CloseFiles(); IndicatorRelease(atr_handle); atr_handle=INVALID_HANDLE; return INIT_FAILED; }
 ready=true; return INIT_SUCCEEDED;
}
void OnTick() {
 if(!ready || finished) return;
 MqlTick q; if(!SymbolInfoTick(_Symbol,q) || !GoodQuote(q)) {
  bad_ticks++;
  if(InpMode==MODE_TRADING) { datetime invalid_bar=iTime(_Symbol,tf,0); if(invalid_bar>0) last_bar=invalid_bar; }
  return;
 }
 if(first_tick==0) first_tick=q.time_msc; last_tick=q.time_msc; ticks_seen++;
 ReconcileTrades(); TrackTick(q);
 datetime bar=iTime(_Symbol,tf,0);
 if(bar==0) {
  data_failures++; last_bar=-1;
  for(int j=0;j<ArraySize(active);j++) FinishObservation(active[j],"CENSORED_DATA_GAP",q.time_msc);
  ArrayResize(active,0); return;
 }
 if(bar!=last_bar) ExpireResearch(q);
 ResearchTick(q);
 // Bootstrap or failed-series recovery: never trade an old trigger on attachment/recovery.
 if(last_bar<=0) { last_bar=bar; return; }
 if(bar==last_bar) return;
 int shift=iBarShift(_Symbol,tf,last_bar,true); last_bar=bar;
 if(shift!=1) { missed_bars+=MathMax(1,shift-1); return; }
 Signal s; if(!ReadSignal(q,bar,s)) return;
 if(InpMode==MODE_TRADING && !s.combined) return;
 if(InpMode==MODE_RESEARCH && s.body_pct+1e-8<InpResearchMinBodyPercent) return;
 ValidateCommercial(s,q); MqlTradeRequest req={}; Preflight(s,req);
 if(InpMode==MODE_RESEARCH) { StartObservation(s); ResearchTick(q); }
 else { if(s.executable) SendSignal(s,req); Write(fsignal,SignalRow(s)); TrackTick(q); }
}
double OnTester() {
 Finish("TEST_END");
 if(InpMode!=MODE_TRADING) return -1000000000.0;
 double n=TesterStatistics(STAT_TRADES),net=TesterStatistics(STAT_PROFIT),dd=TesterStatistics(STAT_EQUITY_DD);
 if(n<InpMinTradesForScore) return -1000000.0+n/InpMinTradesForScore;
 double score=net/MathMax(1.0,dd)*MathMin(1.0,n/(2.0*InpMinTradesForScore));
 if(!MathIsValidNumber(score)) return -1000000000.0;
 return MathMax(-999999.0,MathMin(999999.0,score));
}
void OnDeinit(const int reason) { Finish("DEINIT_"+I(reason)); CloseFiles(); if(atr_handle!=INVALID_HANDLE) IndicatorRelease(atr_handle); }
