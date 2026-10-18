#property script_show_inputs
input datetime InpFrom=D'2026.10.12 00:00';
input datetime InpTo=D'2026.10.13 00:00';
// One CSV per export, not per tick. End is exclusive, server time.
void OnStart() {
 if(InpTo<=InpFrom) { Print("Invalid range"); return; }
 string name="CMR_Ticks_"+IntegerToString(InpFrom)+"_"+IntegerToString(InpTo)+"_"+StringFormat("%I64u",GetMicrosecondCount())+".csv";
 int file=FileOpen(name,FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
 if(file==INVALID_HANDLE) { Print("File error ",GetLastError()); return; }
 FileWrite(file,"TimeMsc","Bid","Ask","Flags");
 long total=0; bool complete=true;
 for(ulong start=(ulong)InpFrom*1000;start<(ulong)InpTo*1000 && !IsStopped();start+=3600000) {
  ulong end=(ulong)MathMin((double)(start+3599999),(double)((ulong)InpTo*1000-1));
  MqlTick ticks[]; ResetLastError();
  int n=CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL,start,end); int error=GetLastError();
  if(n<0 || error!=0) { complete=false; Print("INCOMPLETE tick chunk ",start," error ",error); break; }
  for(int j=0;j<n;j++) FileWrite(file,ticks[j].time_msc,DoubleToString(ticks[j].bid,10),DoubleToString(ticks[j].ask,10),ticks[j].flags);
  total+=n;
 }
 FileClose(file);
 Print("Tick export ",name," ticks=",total," complete=",complete && !IsStopped(),". Availability does not certify real-tick provenance.");
}
