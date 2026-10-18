// mqlcheck: MQL5 built-ins part 1 - globals, output, math, strings, time, arrays.
// Everything is inline with a trivial body; only the signatures matter.
#pragma once

//---------------------------------------------------------------- predefined variables
inline string          _Symbol      = "EURUSD";
inline ENUM_TIMEFRAMES _Period      = PERIOD_H1;
inline int             _Digits      = 5;
inline double          _Point       = 0.00001;
inline int             _LastError   = 0;
inline bool            _StopFlag    = false;
inline int             _RandomSeed  = 0;
inline int             _UninitReason = 0;
inline bool            _IsX64       = true;
inline int             _AppliedTo   = 0;

inline string          Symbol()  { return _Symbol; }
inline ENUM_TIMEFRAMES Period()  { return _Period; }
inline int             Digits()  { return _Digits; }
inline double          Point()   { return _Point; }
inline bool            IsStopped() { return _StopFlag; }
inline int             GetLastError() { return _LastError; }
inline void            ResetLastError() { _LastError = 0; }
inline void            SetUserError(ushort) {}
inline int             UninitializeReason() { return _UninitReason; }

//---------------------------------------------------------------- output
template<class... A> inline void   Print(const A &...) {}
template<class... A> inline void   PrintFormat(const string &, const A &...) {}
template<class... A> inline void   printf(const string &, const A &...) {}
template<class... A> inline int    Comment(const A &...) { return 0; }
template<class... A> inline void   Alert(const A &...) {}
template<class... A> inline string StringFormat(const string &fmt, const A &...) { return fmt; }
template<class... A> inline int    StringConcatenate(string &out, const A &...) { return out.Len(); }
inline bool SendNotification(const string &) { return true; }
inline bool SendMail(const string &, const string &) { return true; }
inline bool SendFTP(const string &, const string & = "") { return true; }
inline bool PlaySound(const string &) { return true; }
inline int  MessageBox(const string &, const string & = "", int = 0) { return 1; }
inline void DebugBreak() {}
inline void ExpertRemove() {}
inline void TesterStop() {}
inline bool TesterDeposit(double) { return true; }
inline bool TesterWithdrawal(double) { return true; }
inline double TesterStatistics(int) { return 0; }
inline void TerminalClose(int = 0) {}
template<class T> inline void ZeroMemory(T &) {}
template<class T> inline T *GetPointer(T &o) { return &o; }
template<class T> inline T *GetPointer(T *p) { return p; }
template<class T> inline ENUM_POINTER_TYPE CheckPointer(T *p) { return p ? POINTER_DYNAMIC : POINTER_INVALID; }
template<class T> inline ENUM_POINTER_TYPE CheckPointer(const T &) { return POINTER_AUTOMATIC; }
template<class E, typename std::enable_if<std::is_enum<E>::value, int>::type = 0>
inline string EnumToString(E) { return "ENUM"; }

//---------------------------------------------------------------- timers / events
inline bool EventSetTimer(int) { return true; }
inline bool EventSetMillisecondTimer(int) { return true; }
inline void EventKillTimer() {}
inline bool EventChartCustom(long, ushort, long, double, const string &) { return true; }
inline void Sleep(int) {}
inline uint  GetTickCount() { return 0; }
inline ulong GetTickCount64() { return 0; }
inline ulong GetMicrosecondCount() { return 0; }

//---------------------------------------------------------------- math
template<class T> inline T MathAbs(T v) { return v < 0 ? -v : v; }
template<class A, class B> inline typename std::common_type<A, B>::type MathMax(A a, B b) { return a > b ? a : b; }
template<class A, class B> inline typename std::common_type<A, B>::type MathMin(A a, B b) { return a < b ? a : b; }
inline double MathFloor(double v) { return v; }
inline double MathCeil(double v) { return v; }
inline double MathRound(double v) { return v; }
inline double MathPow(double v, double) { return v; }
inline double MathSqrt(double v) { return v; }
inline double MathLog(double v) { return v; }
inline double MathLog10(double v) { return v; }
inline double MathLog1p(double v) { return v; }
inline double MathExp(double v) { return v; }
inline double MathExpm1(double v) { return v; }
inline double MathMod(double v, double) { return v; }
inline double MathSin(double v) { return v; }
inline double MathCos(double v) { return v; }
inline double MathTan(double v) { return v; }
inline double MathArcsin(double v) { return v; }
inline double MathArccos(double v) { return v; }
inline double MathArctan(double v) { return v; }
inline double MathArctan2(double v, double) { return v; }
inline double MathSinh(double v) { return v; }
inline double MathCosh(double v) { return v; }
inline double MathTanh(double v) { return v; }
inline int    MathRand() { return 0; }
inline void   MathSrand(int) {}
inline bool   MathIsValidNumber(double) { return true; }
inline bool   MathClassify(double) { return true; }
inline double NormalizeDouble(double v, int) { return v; }
template<class T> inline T fabs(T v) { return MathAbs(v); }
template<class A, class B> inline typename std::common_type<A, B>::type fmax(A a, B b) { return MathMax(a, b); }
template<class A, class B> inline typename std::common_type<A, B>::type fmin(A a, B b) { return MathMin(a, b); }
inline double floor(double v) { return v; }
inline double ceil(double v) { return v; }
inline double round(double v) { return v; }
inline double pow(double v, double) { return v; }
inline double sqrt(double v) { return v; }
inline double log(double v) { return v; }
inline double log10(double v) { return v; }
inline double exp(double v) { return v; }
inline double fmod(double v, double) { return v; }
inline double sin(double v) { return v; }
inline double cos(double v) { return v; }
inline double tan(double v) { return v; }
inline double asin(double v) { return v; }
inline double acos(double v) { return v; }
inline double atan(double v) { return v; }
inline int    rand() { return 0; }
inline void   srand(int) {}

//---------------------------------------------------------------- strings
inline int    StringLen(const string &s) { return s.Len(); }
inline int    StringFind(const string &, const string &, int = 0) { return -1; }
inline string StringSubstr(const string &s, int, int = -1) { return s; }
inline int    StringReplace(string &, const string &, const string &) { return 0; }
inline bool   StringToUpper(string &) { return true; }
inline bool   StringToLower(string &) { return true; }
inline bool   StringTrimLeft(string &) { return true; }
inline bool   StringTrimRight(string &) { return true; }
inline ushort StringGetCharacter(const string &s, int i) { return s[i]; }
inline bool   StringSetCharacter(string &, int, ushort) { return true; }
inline int    StringCompare(const string &, const string &, bool = true) { return 0; }
inline double StringToDouble(const string &) { return 0; }
inline long   StringToInteger(const string &) { return 0; }
inline datetime StringToTime(const string &) { return 0; }
inline color  StringToColor(const string &) { return 0; }
inline bool   StringAdd(string &, const string &) { return true; }
inline bool   StringInit(string &, int = 0, ushort = 0) { return true; }
inline int    StringBufferLen(const string &s) { return s.Len(); }
inline bool   StringFill(string &, ushort) { return true; }
inline bool   StringReserve(string &, uint) { return true; }
inline int    StringSplit(const string &, ushort, MqlArray<string> &) { return 0; }
template<unsigned long N> inline int StringSplit(const string &, ushort, string (&)[N]) { return 0; }
inline string CharToString(uchar) { return ""; }
inline string ShortToString(ushort) { return ""; }
template<MQL_ARR(A)> inline string CharArrayToString(const A &, int = 0, int = -1, uint = 0) { return ""; }
template<MQL_ARR(A)> inline string ShortArrayToString(const A &, int = 0, int = -1) { return ""; }
template<MQL_ARR(A)> inline int StringToCharArray(const string &, A &, int = 0, int = -1, uint = 0) { return 0; }
template<MQL_ARR(A)> inline int StringToShortArray(const string &, A &, int = 0, int = -1) { return 0; }
inline string DoubleToString(double, int = 8) { return "0"; }
inline string IntegerToString(long, int = 0, ushort = ' ') { return "0"; }
inline string TimeToString(datetime, int = TIME_DATE | TIME_MINUTES) { return "1970.01.01 00:00"; }
inline string ColorToString(color, bool = false) { return "clrNONE"; }
inline color  ColorToARGB(color, uchar = 255) { return 0; }
inline datetime TimeToStr(datetime, int = TIME_DATE | TIME_MINUTES) { return 0; }
inline int    StringLenUtf8(const string &s) { return s.Len(); }
inline int    StringToUtf8(const string &, MqlArray<uchar> &) { return 0; }
template<class... A> inline string StringSubstrLegacy(const A &...) { return ""; }

//---------------------------------------------------------------- date / time
inline datetime TimeCurrent() { return 0; }
inline datetime TimeCurrent(MqlDateTime &) { return 0; }
inline datetime TimeLocal() { return 0; }
inline datetime TimeLocal(MqlDateTime &) { return 0; }
inline datetime TimeGMT() { return 0; }
inline datetime TimeGMT(MqlDateTime &) { return 0; }
inline datetime TimeTradeServer() { return 0; }
inline datetime TimeTradeServer(MqlDateTime &) { return 0; }
inline int      TimeGMTOffset() { return 0; }
inline int      TimeDaylightSavings() { return 0; }
inline bool     TimeToStruct(datetime, MqlDateTime &) { return true; }
inline datetime StructToTime(const MqlDateTime &) { return 0; }
inline int      PeriodSeconds(int = PERIOD_CURRENT) { return 60; }
inline int      TimeDayOfWeek(datetime) { return 0; }   // MQL4-ism, tolerated

//---------------------------------------------------------------- arrays
template<MQL_ARR(A)> inline int  ArraySize(const A &) { return 0; }
template<class T> inline int ArraySize(const MqlArray<T> &a) { return a.Size(); }
template<MQL_ARR(A)> inline int  ArrayResize(A &, int, int = 0) { return 0; }
template<class T> inline int ArrayResize(MqlArray<T> &a, int n, int = 0) { a.Resize(n); return n; }
template<class T, unsigned long N> inline int ArrayResize(MqlArray2<T, N> &a, int n, int = 0) { a.Resize(n); return n; }
template<MQL_ARR(A)> inline bool ArraySetAsSeries(const A &, bool) { return true; }
template<class T> inline bool ArraySetAsSeries(const MqlArray<T> &a, bool s) { a.SetAsSeries(s); return true; }
template<MQL_ARR(A)> inline bool ArrayGetAsSeries(const A &) { return false; }
template<MQL_ARR(A)> inline bool ArrayIsSeries(const A &) { return false; }
template<MQL_ARR(A)> inline bool ArrayIsDynamic(const A &) { return true; }
template<MQL_ARR(A), class V> inline int ArrayInitialize(A &, V) { return 0; }
template<MQL_ARR(A), class V> inline void ArrayFill(A &, int, int, V) {}
template<MQL_ARR(A), MQL_ARR(B)> inline int ArrayCopy(A &, const B &, int = 0, int = 0, int = WHOLE_ARRAY) { return 0; }
template<MQL_ARR(A), MQL_ARR(B)> inline int ArrayCompare(const A &, const B &, int = 0, int = 0, int = WHOLE_ARRAY) { return 0; }
template<MQL_ARR(A)> inline int  ArrayMaximum(const A &, int = 0, int = WHOLE_ARRAY) { return 0; }
template<MQL_ARR(A)> inline int  ArrayMinimum(const A &, int = 0, int = WHOLE_ARRAY) { return 0; }
template<MQL_ARR(A)> inline bool ArraySort(A &, int = WHOLE_ARRAY, int = 0, int = 0) { return true; }
template<MQL_ARR(A), class V> inline int ArrayBsearch(const A &, V, int = WHOLE_ARRAY, int = 0, int = 0) { return 0; }
template<MQL_ARR(A)> inline void ArrayFree(A &) {}
template<class T> inline void ArrayFree(MqlArray<T> &a) { a.Free(); }
template<MQL_ARR(A), MQL_ARR(B)> inline bool ArrayInsert(A &, const B &, uint, uint = 0, uint = WHOLE_ARRAY) { return true; }
template<MQL_ARR(A)> inline bool ArrayRemove(A &, uint, uint = WHOLE_ARRAY) { return true; }
template<MQL_ARR(A)> inline bool ArrayReverse(A &, uint = 0, uint = WHOLE_ARRAY) { return true; }
template<MQL_ARR(A)> inline void ArrayPrint(const A &, uint = 0, const string & = NULL, ulong = 0, ulong = WHOLE_ARRAY, ulong = 0) {}
template<MQL_ARR(A)> inline int  ArrayRange(const A &, int) { return 0; }
template<MQL_ARR(A), MQL_ARR(B)> inline bool ArraySwap(A &, B &) { return true; }
template<MQL_ARR(A)> inline int  ArrayDimension(const A &) { return 1; }

//---------------------------------------------------------------- global variables of the terminal
inline datetime GlobalVariableSet(const string &, double) { return 0; }
inline double   GlobalVariableGet(const string &) { return 0; }
inline bool     GlobalVariableGet(const string &, double &) { return true; }
inline bool     GlobalVariableCheck(const string &) { return false; }
inline bool     GlobalVariableDel(const string &) { return true; }
inline datetime GlobalVariableTime(const string &) { return 0; }
inline bool     GlobalVariableTemp(const string &) { return true; }
inline bool     GlobalVariableSetOnCondition(const string &, double, double) { return true; }
inline int      GlobalVariablesDeleteAll(const string & = NULL, datetime = 0) { return 0; }
inline int      GlobalVariablesTotal() { return 0; }
inline string   GlobalVariableName(int) { return ""; }
inline int      GlobalVariablesFlush() { return 0; }

//---------------------------------------------------------------- files (common subset)
inline int  FileOpen(const string &, int, short = '\t', uint = CP_ACP) { return 0; }
inline void FileClose(int) {}
inline bool FileIsExist(const string &, int = 0) { return false; }
inline bool FileDelete(const string &, int = 0) { return true; }
inline bool FileMove(const string &, int, const string &, int) { return true; }
inline bool FileCopy(const string &, int, const string &, int) { return true; }
inline bool FileSeek(int, long, int) { return true; }
inline ulong FileTell(int) { return 0; }
inline ulong FileSize(int) { return 0; }
inline bool FileIsEnding(int) { return true; }
inline bool FileIsLineEnding(int) { return true; }
inline void FileFlush(int) {}
template<class... A> inline uint FileWrite(int, const A &...) { return 0; }
inline uint FileWriteString(int, const string &, int = -1) { return 0; }
inline uint FileWriteDouble(int, double) { return 0; }
inline uint FileWriteInteger(int, int, int = 4) { return 0; }
inline uint FileWriteLong(int, long) { return 0; }
inline uint FileWriteFloat(int, float) { return 0; }
template<class S> inline uint FileWriteStruct(int, const S &, int = -1) { return 0; }
template<MQL_ARR(A)> inline uint FileWriteArray(int, const A &, int = 0, int = WHOLE_ARRAY) { return 0; }
inline string FileReadString(int, int = -1) { return ""; }
inline double FileReadDouble(int) { return 0; }
inline int    FileReadInteger(int, int = 4) { return 0; }
inline long   FileReadLong(int) { return 0; }
inline float  FileReadFloat(int) { return 0; }
inline double FileReadNumber(int) { return 0; }
inline bool   FileReadBool(int) { return false; }
inline datetime FileReadDatetime(int) { return 0; }
template<class S> inline uint FileReadStruct(int, S &, int = -1) { return 0; }
template<MQL_ARR(A)> inline uint FileReadArray(int, A &, int = 0, int = WHOLE_ARRAY) { return 0; }
inline long FileFindFirst(const string &, string &, int = 0) { return 0; }
inline bool FileFindNext(long, string &) { return false; }
inline void FileFindClose(long) {}
inline bool FolderCreate(const string &, int = 0) { return true; }
inline bool FolderDelete(const string &, int = 0) { return true; }
inline bool FolderClean(const string &, int = 0) { return true; }
inline long FileGetInteger(int, int) { return 0; }
inline long FileGetInteger(const string &, int, bool = false) { return 0; }
