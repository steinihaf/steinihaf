// mqlcheck stand-in for <Trade\TerminalInfo.mqh> (CTerminalInfo) - Standard Library signatures
#pragma once
#pragma GCC system_header
#include <Object.mqh>
class CTerminalInfo : public CObject
  {
public:
   CTerminalInfo() {}
   int      Build() const { return 4000; }
   bool     IsConnected() const { return true; }
   bool     IsDLLsAllowed() const { return false; }
   bool     IsTradeAllowed() const { return true; }
   bool     IsEmailEnabled() const { return false; }
   bool     IsFtpEnabled() const { return false; }
   int      MaxBars() const { return 0; }
   int      CodePage() const { return 0; }
   int      CPUCores() const { return 1; }
   int      MemoryPhysical() const { return 0; }
   int      MemoryTotal() const { return 0; }
   int      MemoryAvailable() const { return 0; }
   int      MemoryUsed() const { return 0; }
   bool     IsX64() const { return true; }
   int      OpenCLSupport() const { return 0; }
   int      DiskSpace() const { return 0; }
   string   Language() const { return ""; }
   string   Name() const { return ""; }
   string   Company() const { return ""; }
   string   Path() const { return ""; }
   string   DataPath() const { return ""; }
   string   CommonDataPath() const { return ""; }
   long     InfoInteger(const int) const { return 0; }
   string   InfoString(const int) const { return ""; }
  };
