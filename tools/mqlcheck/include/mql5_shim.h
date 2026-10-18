//+------------------------------------------------------------------+
//| mql5_shim.h                                        tools/mqlcheck |
//|                                                                  |
//| Fake MQL5 runtime API for "g++ -std=c++17 -fsyntax-only".        |
//| Nothing in here is meant to run: bodies are trivial stubs, only  |
//| the names, types, overloads and default arguments matter.        |
//|                                                                  |
//| It deliberately avoids <string>/<vector>/<cmath>/<cstdlib>: those |
//| drag in libc declarations (time, index, abs, round, exit, y0,    |
//| random, ...) and glibc typedefs that collide with ordinary MQL5  |
//| identifiers. Only <type_traits> and <initializer_list> are used. |
//|                                                                  |
//| Design rules (keep the checker GENEROUS):                        |
//|  - built-ins take int/long where MQL5 takes an enum, so any enum |
//|    or plain integer is accepted; the real enums still exist for  |
//|    EnumToString() and casts                                      |
//|  - every "array" parameter is a template constrained to          |
//|    MqlArray<T> (dynamic, produced by the pre-processor) or a     |
//|    fixed C array                                                 |
//|  - variadic templates for Print/Comment/Alert/StringFormat/...   |
//+------------------------------------------------------------------+
#pragma once
#pragma GCC system_header
#include <initializer_list>
#include <type_traits>

//---------------------------------------------------------------- predefined macros
#define __MQL5__       1
#define __MQLBUILD__   4000
#define __MQL5BUILD__  4000
#ifndef __FUNCSIG__
#define __FUNCSIG__    __PRETTY_FUNCTION__
#endif
#define __DATETIME__   __DATE__
#define __PATH__       __FILE__
#ifndef NULL
#define NULL           __null
#endif
#define IS_DEBUG_MODE   0
#define IS_PROFILE_MODE 0

//---------------------------------------------------------------- integral types
// glibc already typedefs uint/ulong/ushort (g++ defines _GNU_SOURCE), so the
// spellings below must be identical to glibc's: ulong is "unsigned long",
// which is 64-bit on x86-64 Linux - the same width as MQL5's ulong.
typedef unsigned char      uchar;
typedef unsigned short     ushort;
typedef unsigned int       uint;
typedef unsigned long      ulong;
typedef long               datetime;   // 64-bit, like MQL5
typedef unsigned int       color;      // 0x00BBGGRR, like MQL5
static_assert(sizeof(long) == 8 && sizeof(ulong) == 8, "mqlcheck expects a 64-bit long (LP64 platform)");

namespace mqlsh
  {
   inline int slen(const char *s) { int n = 0; if(s) while(s[n]) n++; return n; }
   inline int cmp(const char *a, const char *b)
     {
      if(!a) a = "";
      if(!b) b = "";
      while(*a && *a == *b) { a++; b++; }
      return (int)(unsigned char)*a - (int)(unsigned char)*b;
     }
   template<class T> struct is_number
      : std::integral_constant<bool, std::is_arithmetic<T>::value || std::is_enum<T>::value> {};
  }
#define MQL_NUMBER(T) class T, typename std::enable_if<mqlsh::is_number<T>::value, int>::type = 0

//---------------------------------------------------------------- string
// MQL5 string: implicit from const char*, NO implicit conversion back to
// const char* (use c_str()), NO implicit conversion from numbers (MQL5 wants
// IntegerToString/DoubleToString or a (string) cast, see MqlStrCast below).
class string
  {
   char *p_;
   int   n_;
   void  set(const char *s, int n)
     {
      char *q = new char[n + 1];
      for(int i = 0; i < n; i++) q[i] = s[i];
      q[n] = 0;
      delete[] p_;
      p_ = q;
      n_ = n;
     }
public:
   string() : p_(nullptr), n_(0) { set("", 0); }
   string(const char *s) : p_(nullptr), n_(0) { set(s ? s : "", mqlsh::slen(s)); }   // implicit on purpose
   string(const string &o) : p_(nullptr), n_(0) { set(o.c_str(), o.n_); }
   string(string &&o) noexcept : p_(o.p_), n_(o.n_) { o.p_ = nullptr; o.n_ = 0; }
   ~string() { delete[] p_; }
   string &operator=(const string &o) { if(this != &o) set(o.c_str(), o.n_); return *this; }
   string &operator=(string &&o) noexcept
     {
      if(this != &o) { delete[] p_; p_ = o.p_; n_ = o.n_; o.p_ = nullptr; o.n_ = 0; }
      return *this;
     }
   string &operator=(const char *s) { set(s ? s : "", mqlsh::slen(s)); return *this; }

   const char *c_str() const { return p_ ? p_ : ""; }
   int         Len()   const { return n_; }
   ushort      operator[](long i) const { return (i >= 0 && i < n_) ? (ushort)(uchar)p_[i] : (ushort)0; }

   string &append(const char *s, int n)
     {
      char *q = new char[n_ + n + 1];
      for(int i = 0; i < n_; i++) q[i] = p_[i];
      for(int i = 0; i < n; i++) q[n_ + i] = s[i];
      q[n_ + n] = 0;
      delete[] p_;
      p_ = q;
      n_ += n;
      return *this;
     }
   string &operator+=(const string &o) { return append(o.c_str(), o.n_); }
   string &operator+=(const char *s)   { return append(s ? s : "", mqlsh::slen(s)); }

   friend string operator+(const string &a, const string &b) { string r(a); r += b; return r; }
   friend string operator+(const string &a, const char *b)   { string r(a); r += b; return r; }
   friend string operator+(const char *a, const string &b)   { string r(a); r += b; return r; }

   friend bool operator==(const string &a, const string &b) { return mqlsh::cmp(a.c_str(), b.c_str()) == 0; }
   friend bool operator==(const string &a, const char *b)   { return mqlsh::cmp(a.c_str(), b) == 0; }
   friend bool operator==(const char *a, const string &b)   { return mqlsh::cmp(a, b.c_str()) == 0; }
   friend bool operator!=(const string &a, const string &b) { return !(a == b); }
   friend bool operator!=(const string &a, const char *b)   { return !(a == b); }
   friend bool operator!=(const char *a, const string &b)   { return !(a == b); }
   friend bool operator< (const string &a, const string &b) { return mqlsh::cmp(a.c_str(), b.c_str()) <  0; }
   friend bool operator> (const string &a, const string &b) { return mqlsh::cmp(a.c_str(), b.c_str()) >  0; }
   friend bool operator<=(const string &a, const string &b) { return mqlsh::cmp(a.c_str(), b.c_str()) <= 0; }
   friend bool operator>=(const string &a, const string &b) { return mqlsh::cmp(a.c_str(), b.c_str()) >= 0; }
  };

// MQL5 compiles `str + 5` (and `str += 5`) with the warning "implicit
// conversion from 'number' to 'string'". Mirror that exactly: accepted, but
// flagged with a warning at the call site via [[deprecated]].
template<MQL_NUMBER(T)>
[[deprecated("MQL5 warning: implicit conversion from 'number' to 'string' (use (string) cast / IntegerToString / DoubleToString)")]]
inline string operator+(const string &a, T) { return a; }
template<MQL_NUMBER(T)>
[[deprecated("MQL5 warning: implicit conversion from 'number' to 'string' (use (string) cast / IntegerToString / DoubleToString)")]]
inline string operator+(T, const string &b) { return b; }
template<MQL_NUMBER(T)>
[[deprecated("MQL5 warning: implicit conversion from 'number' to 'string' (use (string) cast / IntegerToString / DoubleToString)")]]
inline string &operator+=(string &a, T) { return a; }

//---------------------------------------------------------------- (string) cast
// The pre-processor rewrites "(string)x" to "(MqlStrCast)x". A MqlStrCast IS a
// string, so it concatenates, compares and assigns like one.
struct MqlStrCast : public string
  {
   MqlStrCast(const string &s) : string(s) {}
   MqlStrCast(const char *s) : string(s) {}
   template<MQL_NUMBER(T)> MqlStrCast(T) : string("0") {}
  };

//---------------------------------------------------------------- arrays
// "T name[]" (dynamic array) is rewritten to "MqlArray<T> name" by the
// pre-processor. Storage is a dummy: nothing here ever runs.
template<class T> class MqlArray
  {
   T   *d_;
   int  n_;
   mutable bool series_;
public:
   typedef T value_type;
   MqlArray() : d_(nullptr), n_(0), series_(false) {}
   MqlArray(std::initializer_list<T> il) : d_(nullptr), n_((int)il.size()), series_(false) {}
   MqlArray(const MqlArray &o) : d_(nullptr), n_(o.n_), series_(o.series_) {}
   MqlArray &operator=(const MqlArray &o) { n_ = o.n_; return *this; }
   T       &operator[](long i)       { return d_[i]; }
   const T &operator[](long i) const { return d_[i]; }
   int   Size() const { return n_; }
   void  Resize(int n) { n_ = n < 0 ? 0 : n; }
   void  Free() { n_ = 0; }
   void  SetAsSeries(bool s) const { series_ = s; }
   bool  IsSeries() const { return series_; }
  };

// "T name[][N]" (dynamic first dimension, fixed second) -> MqlArray2<T,N>
template<class T, unsigned long N> class MqlArray2
  {
   typedef T Row[N];
   Row *d_;
   int  n_;
   mutable bool series_;
public:
   typedef T value_type;
   MqlArray2() : d_(nullptr), n_(0), series_(false) {}
   Row       &operator[](long i)       { return d_[i]; }
   const Row &operator[](long i) const { return d_[i]; }
   int  Size() const { return n_ * (int)N; }
   void Resize(int n) { n_ = n < 0 ? 0 : n; }
   void Free() { n_ = 0; }
   void SetAsSeries(bool s) const { series_ = s; }
   bool IsSeries() const { return series_; }
  };

template<class A> struct MqlIsArray : std::false_type { typedef void elem; };
template<class T> struct MqlIsArray<MqlArray<T>> : std::true_type { typedef T elem; };
template<class T, unsigned long N> struct MqlIsArray<MqlArray2<T, N>> : std::true_type { typedef T elem; };
template<class T, unsigned long N> struct MqlIsArray<T[N]> : std::true_type { typedef T elem; };
template<class T, unsigned long N, unsigned long M> struct MqlIsArray<T[N][M]> : std::true_type { typedef T elem; };
template<class T, unsigned long N, unsigned long M, unsigned long K> struct MqlIsArray<T[N][M][K]> : std::true_type { typedef T elem; };
// any array (dynamic or fixed, any element type)
#define MQL_ARR(A) class A, typename std::enable_if<MqlIsArray<A>::value, int>::type = 0
// any array whose element type is exactly T
#define MQL_ARR_OF(A, T) class A, typename std::enable_if<MqlIsArray<A>::value && std::is_same<typename MqlIsArray<A>::elem, T>::value, int>::type = 0

//==================================================================== constants
#define WHOLE_ARRAY      (-1)
#define WRONG_VALUE      (-1)
#define INVALID_HANDLE   (-1)
#define CLR_NONE         0xFFFFFFFF
#define clrNONE          0xFFFFFFFF
#define CHARTS_MAX       100
#define INT_VALUE        4
#define SHORT_VALUE      2
#define CHAR_VALUE       1
#define DBL_MAX          1.7976931348623157e+308
#define DBL_MIN          2.2250738585072014e-308
#define DBL_EPSILON      2.2204460492503131e-016
#define DBL_DIG          15
#define DBL_MANT_DIG     53
#define DBL_MAX_EXP      1024
#define DBL_MIN_EXP      (-1021)
#define DBL_MAX_10_EXP   308
#define DBL_MIN_10_EXP   (-307)
#define FLT_MAX          3.402823466e+38F
#define FLT_MIN          1.175494351e-38F
#define FLT_EPSILON      1.192092896e-07F
#define FLT_DIG          6
#define FLT_MANT_DIG     24
#define FLT_MAX_EXP      128
#define FLT_MIN_EXP      (-125)
#define FLT_MAX_10_EXP   38
#define FLT_MIN_10_EXP   (-37)
#define EMPTY_VALUE      DBL_MAX
#define CHAR_MIN         (-128)
#define CHAR_MAX         127
#define UCHAR_MAX        255
#define SHORT_MIN        (-32768)
#define SHORT_MAX        32767
#define USHORT_MAX       65535
#define INT_MIN          (-2147483647 - 1)
#define INT_MAX          2147483647
#define UINT_MAX         0xFFFFFFFFU
#define LONG_MIN         (-9223372036854775807L - 1)
#define LONG_MAX         9223372036854775807L
#define ULONG_MAX        0xFFFFFFFFFFFFFFFFUL
#define M_E              2.71828182845904523536
#define M_LOG2E          1.44269504088896340736
#define M_LOG10E         0.434294481903251827651
#define M_LN2            0.693147180559945309417
#define M_LN10           2.30258509299404568402
#define M_PI             3.14159265358979323846
#define M_PI_2           1.57079632679489661923
#define M_PI_4           0.785398163397448309616
#define M_1_PI           0.318309886183790671538
#define M_2_PI           0.636619772367581343076
#define M_2_SQRTPI       1.12837916709551257390
#define M_SQRT2          1.41421356237309504880
#define M_SQRT1_2        0.707106781186547524401
// TimeToString flags
#define TIME_DATE        1
#define TIME_MINUTES     2
#define TIME_SECONDS     4
// ArrayPrint flags
#define ARRAYPRINT_HEADER  1
#define ARRAYPRINT_INDEX   2
#define ARRAYPRINT_LIMIT   4
#define ARRAYPRINT_ALIGN   8
#define ARRAYPRINT_DATE    16
#define ARRAYPRINT_MINUTES 32
#define ARRAYPRINT_SECONDS 64
// code pages
#define CP_ACP         0
#define CP_OEMCP       1
#define CP_MACCP       2
#define CP_THREAD_ACP  3
#define CP_SYMBOL      42
#define CP_UTF7        65000
#define CP_UTF8        65001
// MessageBox
#define MB_OK                0
#define MB_OKCANCEL          1
#define MB_ABORTRETRYIGNORE  2
#define MB_YESNOCANCEL       3
#define MB_YESNO             4
#define MB_RETRYCANCEL       5
#define MB_CANCELTRYCONTINUE 6
#define MB_ICONSTOP          16
#define MB_ICONERROR         16
#define MB_ICONHAND          16
#define MB_ICONQUESTION      32
#define MB_ICONEXCLAMATION   48
#define MB_ICONWARNING       48
#define MB_ICONINFORMATION   64
#define MB_ICONASTERISK      64
#define MB_DEFBUTTON1        0
#define MB_DEFBUTTON2        256
#define MB_DEFBUTTON3        512
#define MB_DEFBUTTON4        768
#define IDOK        1
#define IDCANCEL    2
#define IDABORT     3
#define IDRETRY     4
#define IDIGNORE    5
#define IDYES       6
#define IDNO        7
#define IDTRYAGAIN  10
#define IDCONTINUE  11
// keyboard codes for CHARTEVENT_KEYDOWN
#define KEY_LEFT 37
#define KEY_UP 38
#define KEY_RIGHT 39
#define KEY_DOWN 40
#define KEY_HOME 36
#define KEY_END 35
#define KEY_PAGEUP 33
#define KEY_PAGEDOWN 34
#define KEY_ESCAPE 27
#define KEY_ENTER 13
#define KEY_TAB 9
#define KEY_DELETE 46
#define KEY_INSERT 45
#define KEY_SPACE 32
#define KEY_NUMLOCK_DOWN 98
#define KEY_NUMLOCK_LEFT 100
#define KEY_NUMLOCK_5 101
#define KEY_NUMLOCK_RIGHT 102
#define KEY_NUMLOCK_UP 104
#define KEY_NUMPAD_5 12
// CopyTicks / MqlTick flags
#define COPY_TICKS_ALL   (-1)
#define COPY_TICKS_INFO  1
#define COPY_TICKS_TRADE 2
#define TICK_FLAG_BID    2
#define TICK_FLAG_ASK    4
#define TICK_FLAG_LAST   8
#define TICK_FLAG_VOLUME 16
#define TICK_FLAG_BUY    32
#define TICK_FLAG_SELL   64
// object visibility flags (OBJPROP_TIMEFRAMES)
#define OBJ_NO_PERIODS  0
#define OBJ_PERIOD_M1   0x00000001
#define OBJ_PERIOD_M2   0x00000002
#define OBJ_PERIOD_M3   0x00000004
#define OBJ_PERIOD_M4   0x00000008
#define OBJ_PERIOD_M5   0x00000010
#define OBJ_PERIOD_M6   0x00000020
#define OBJ_PERIOD_M10  0x00000040
#define OBJ_PERIOD_M12  0x00000080
#define OBJ_PERIOD_M15  0x00000100
#define OBJ_PERIOD_M20  0x00000200
#define OBJ_PERIOD_M30  0x00000400
#define OBJ_PERIOD_H1   0x00000800
#define OBJ_PERIOD_H2   0x00001000
#define OBJ_PERIOD_H3   0x00002000
#define OBJ_PERIOD_H4   0x00004000
#define OBJ_PERIOD_H6   0x00008000
#define OBJ_PERIOD_H8   0x00010000
#define OBJ_PERIOD_H12  0x00020000
#define OBJ_PERIOD_D1   0x00040000
#define OBJ_PERIOD_W1   0x00080000
#define OBJ_PERIOD_MN1  0x00100000
#define OBJ_ALL_PERIODS 0x001fffff
// symbol flag constants (plain integers in MQL5)
#define SYMBOL_EXPIRATION_GTC           1
#define SYMBOL_EXPIRATION_DAY           2
#define SYMBOL_EXPIRATION_SPECIFIED     4
#define SYMBOL_EXPIRATION_SPECIFIED_DAY 8
#define SYMBOL_FILLING_FOK              1
#define SYMBOL_FILLING_IOC              2
#define SYMBOL_FILLING_BOC              4
#define SYMBOL_ORDER_MARKET             1
#define SYMBOL_ORDER_LIMIT              2
#define SYMBOL_ORDER_STOP               4
#define SYMBOL_ORDER_STOP_LIMIT         8
#define SYMBOL_ORDER_SL                 16
#define SYMBOL_ORDER_TP                 32
#define SYMBOL_ORDER_CLOSEBY            64
// ResourceCreate / TextOut color formats
#define COLOR_FORMAT_XRGB_NOALPHA   0
#define COLOR_FORMAT_ARGB_RAW       1
#define COLOR_FORMAT_ARGB_NORMALIZE 2

//==================================================================== program / init
enum ENUM_INIT_RETCODE { INIT_SUCCEEDED = 0, INIT_FAILED = 1, INIT_PARAMETERS_INCORRECT = 2, INIT_AGENT_NOT_SUITABLE = 3 };
enum ENUM_DEINIT_REASON
  {
   REASON_PROGRAM = 0, REASON_REMOVE = 1, REASON_RECOMPILE = 2, REASON_CHARTCHANGE = 3, REASON_CHARTCLOSE = 4,
   REASON_PARAMETERS = 5, REASON_ACCOUNT = 6, REASON_TEMPLATE = 7, REASON_INITFAILED = 8, REASON_CLOSE = 9
  };
enum ENUM_PROGRAM_TYPE { PROGRAM_SCRIPT = 1, PROGRAM_EXPERT = 2, PROGRAM_INDICATOR = 4, PROGRAM_SERVICE = 8 };
enum ENUM_LICENSE_TYPE { LICENSE_FREE = 0, LICENSE_DEMO = 1, LICENSE_FULL = 2, LICENSE_TIME = 3 };
enum ENUM_POINTER_TYPE { POINTER_INVALID = 0, POINTER_DYNAMIC = 1, POINTER_AUTOMATIC = 2 };
enum ENUM_DATATYPE
  {
   TYPE_BOOL = 1, TYPE_CHAR = 2, TYPE_UCHAR = 3, TYPE_SHORT = 4, TYPE_USHORT = 5, TYPE_COLOR = 6, TYPE_INT = 7, TYPE_UINT = 8,
   TYPE_DATETIME = 9, TYPE_LONG = 10, TYPE_ULONG = 11, TYPE_FLOAT = 12, TYPE_DOUBLE = 13, TYPE_STRING = 14
  };
enum ENUM_DAY_OF_WEEK { SUNDAY = 0, MONDAY = 1, TUESDAY = 2, WEDNESDAY = 3, THURSDAY = 4, FRIDAY = 5, SATURDAY = 6 };

//==================================================================== timeframes / series
enum ENUM_TIMEFRAMES
  {
   PERIOD_CURRENT = 0, PERIOD_M1 = 1, PERIOD_M2 = 2, PERIOD_M3 = 3, PERIOD_M4 = 4, PERIOD_M5 = 5, PERIOD_M6 = 6,
   PERIOD_M10 = 10, PERIOD_M12 = 12, PERIOD_M15 = 15, PERIOD_M20 = 20, PERIOD_M30 = 30,
   PERIOD_H1 = 16385, PERIOD_H2 = 16386, PERIOD_H3 = 16387, PERIOD_H4 = 16388, PERIOD_H6 = 16390, PERIOD_H8 = 16392,
   PERIOD_H12 = 16396, PERIOD_D1 = 16408, PERIOD_W1 = 32769, PERIOD_MN1 = 49153
  };
enum ENUM_SERIESMODE { MODE_OPEN = 0, MODE_LOW = 1, MODE_HIGH = 2, MODE_CLOSE = 3, MODE_VOLUME = 4, MODE_REAL_VOLUME = 5, MODE_SPREAD = 6 };
enum ENUM_SERIES_INFO_INTEGER { SERIES_BARS_COUNT, SERIES_FIRSTDATE, SERIES_LASTBAR_DATE, SERIES_SERVER_FIRSTDATE, SERIES_TERMINAL_FIRSTDATE, SERIES_SYNCHRONIZED };

//==================================================================== indicators
enum ENUM_MA_METHOD { MODE_SMA = 0, MODE_EMA = 1, MODE_SMMA = 2, MODE_LWMA = 3 };
enum ENUM_APPLIED_PRICE { PRICE_CLOSE = 1, PRICE_OPEN = 2, PRICE_HIGH = 3, PRICE_LOW = 4, PRICE_MEDIAN = 5, PRICE_TYPICAL = 6, PRICE_WEIGHTED = 7 };
enum ENUM_APPLIED_VOLUME { VOLUME_TICK = 0, VOLUME_REAL = 1 };
enum ENUM_STO_PRICE { STO_LOWHIGH = 0, STO_CLOSECLOSE = 1 };
enum ENUM_INDICATOR_LINES
  {
   MAIN_LINE = 0, SIGNAL_LINE = 1, BASE_LINE = 0, UPPER_BAND = 1, LOWER_BAND = 2, PLUSDI_LINE = 1, MINUSDI_LINE = 2,
   UPPER_LINE = 0, LOWER_LINE = 1, TENKANSEN_LINE = 0, KIJUNSEN_LINE = 1, SENKOUSPANA_LINE = 2, SENKOUSPANB_LINE = 3, CHIKOUSPAN_LINE = 4,
   GATORJAW_LINE = 0, GATORTEETH_LINE = 1, GATORLIPS_LINE = 2, UPPER_HISTOGRAM = 0, LOWER_HISTOGRAM = 2
  };
enum ENUM_INDICATOR
  {
   IND_AC, IND_AD, IND_ADX, IND_ADXW, IND_ALLIGATOR, IND_AMA, IND_AO, IND_ATR, IND_BANDS, IND_BEARS, IND_BULLS, IND_BWMFI, IND_CCI, IND_CHAIKIN,
   IND_CUSTOM, IND_DEMA, IND_DEMARKER, IND_ENVELOPES, IND_FORCE, IND_FRACTALS, IND_FRAMA, IND_GATOR, IND_ICHIMOKU, IND_MA, IND_MACD, IND_MFI,
   IND_MOMENTUM, IND_OBV, IND_OSMA, IND_RSI, IND_RVI, IND_SAR, IND_STDDEV, IND_STOCHASTIC, IND_TEMA, IND_TRIX, IND_VIDYA, IND_VOLUMES, IND_WPR
  };
enum ENUM_INDEXBUFFER_TYPE { INDICATOR_DATA, INDICATOR_COLOR_INDEX, INDICATOR_CALCULATIONS };
enum ENUM_CUSTOMIND_PROPERTY_INTEGER { INDICATOR_DIGITS, INDICATOR_HEIGHT, INDICATOR_LEVELS, INDICATOR_LEVELCOLOR, INDICATOR_LEVELSTYLE, INDICATOR_LEVELWIDTH, INDICATOR_FIXED_MINIMUM, INDICATOR_FIXED_MAXIMUM };
enum ENUM_CUSTOMIND_PROPERTY_DOUBLE { INDICATOR_MINIMUM, INDICATOR_MAXIMUM, INDICATOR_LEVELVALUE };
enum ENUM_CUSTOMIND_PROPERTY_STRING { INDICATOR_SHORTNAME, INDICATOR_LEVELTEXT };
enum ENUM_PLOT_PROPERTY_INTEGER { PLOT_ARROW, PLOT_ARROW_SHIFT, PLOT_DRAW_BEGIN, PLOT_DRAW_TYPE, PLOT_SHOW_DATA, PLOT_SHIFT, PLOT_LINE_STYLE, PLOT_LINE_WIDTH, PLOT_COLOR_INDEXES, PLOT_LINE_COLOR };
enum ENUM_PLOT_PROPERTY_DOUBLE { PLOT_EMPTY_VALUE };
enum ENUM_PLOT_PROPERTY_STRING { PLOT_LABEL };
enum ENUM_DRAW_TYPE
  {
   DRAW_NONE, DRAW_LINE, DRAW_SECTION, DRAW_HISTOGRAM, DRAW_HISTOGRAM2, DRAW_ARROW, DRAW_ZIGZAG, DRAW_FILLING, DRAW_BARS, DRAW_CANDLES,
   DRAW_COLOR_LINE, DRAW_COLOR_SECTION, DRAW_COLOR_HISTOGRAM, DRAW_COLOR_HISTOGRAM2, DRAW_COLOR_ARROW, DRAW_COLOR_ZIGZAG, DRAW_COLOR_BARS, DRAW_COLOR_CANDLES
  };

//==================================================================== objects
enum ENUM_OBJECT
  {
   OBJ_VLINE = 0, OBJ_HLINE = 1, OBJ_TREND = 2, OBJ_TRENDBYANGLE = 3, OBJ_CYCLES = 4, OBJ_ARROWED_LINE = 108, OBJ_CHANNEL = 5,
   OBJ_STDDEVCHANNEL = 6, OBJ_REGRESSION = 7, OBJ_PITCHFORK = 8, OBJ_GANNLINE = 9, OBJ_GANNFAN = 10, OBJ_GANNGRID = 11, OBJ_FIBO = 12,
   OBJ_FIBOTIMES = 13, OBJ_FIBOFAN = 14, OBJ_FIBOARC = 15, OBJ_FIBOCHANNEL = 16, OBJ_EXPANSION = 17, OBJ_ELLIOTWAVE5 = 18, OBJ_ELLIOTWAVE3 = 19,
   OBJ_RECTANGLE = 20, OBJ_TRIANGLE = 21, OBJ_ELLIPSE = 22, OBJ_ARROW_THUMB_UP = 23, OBJ_ARROW_THUMB_DOWN = 24, OBJ_ARROW_UP = 25,
   OBJ_ARROW_DOWN = 26, OBJ_ARROW_STOP = 27, OBJ_ARROW_CHECK = 28, OBJ_ARROW_LEFT_PRICE = 29, OBJ_ARROW_RIGHT_PRICE = 30, OBJ_ARROW_BUY = 31,
   OBJ_ARROW_SELL = 32, OBJ_ARROW = 100, OBJ_TEXT = 101, OBJ_LABEL = 102, OBJ_BUTTON = 103, OBJ_CHART = 104, OBJ_BITMAP = 105,
   OBJ_BITMAP_LABEL = 106, OBJ_EDIT = 107, OBJ_EVENT = 109, OBJ_RECTANGLE_LABEL = 110
  };
enum ENUM_OBJECT_PROPERTY_INTEGER
  {
   OBJPROP_COLOR, OBJPROP_STYLE, OBJPROP_WIDTH, OBJPROP_BACK, OBJPROP_ZORDER, OBJPROP_FILL, OBJPROP_HIDDEN, OBJPROP_SELECTED, OBJPROP_READONLY,
   OBJPROP_TYPE, OBJPROP_TIME, OBJPROP_SELECTABLE, OBJPROP_CREATETIME, OBJPROP_LEVELS, OBJPROP_LEVELCOLOR, OBJPROP_LEVELSTYLE, OBJPROP_LEVELWIDTH,
   OBJPROP_ALIGN, OBJPROP_FONTSIZE, OBJPROP_RAY_LEFT, OBJPROP_RAY_RIGHT, OBJPROP_RAY, OBJPROP_ELLIPSE, OBJPROP_ARROWCODE, OBJPROP_TIMEFRAMES,
   OBJPROP_ANCHOR, OBJPROP_XDISTANCE, OBJPROP_YDISTANCE, OBJPROP_DIRECTION, OBJPROP_DEGREE, OBJPROP_DRAWLINES, OBJPROP_STATE, OBJPROP_CHART_ID,
   OBJPROP_XSIZE, OBJPROP_YSIZE, OBJPROP_XOFFSET, OBJPROP_YOFFSET, OBJPROP_PERIOD, OBJPROP_DATE_SCALE, OBJPROP_PRICE_SCALE, OBJPROP_CHART_SCALE,
   OBJPROP_BGCOLOR, OBJPROP_CORNER, OBJPROP_BORDER_TYPE, OBJPROP_BORDER_COLOR
  };
enum ENUM_OBJECT_PROPERTY_DOUBLE { OBJPROP_PRICE, OBJPROP_LEVELVALUE, OBJPROP_SCALE, OBJPROP_ANGLE, OBJPROP_DEVIATION };
enum ENUM_OBJECT_PROPERTY_STRING { OBJPROP_NAME, OBJPROP_TEXT, OBJPROP_TOOLTIP, OBJPROP_LEVELTEXT, OBJPROP_FONT, OBJPROP_BMPFILE, OBJPROP_SYMBOL };
enum ENUM_LINE_STYLE { STYLE_SOLID = 0, STYLE_DASH = 1, STYLE_DOT = 2, STYLE_DASHDOT = 3, STYLE_DASHDOTDOT = 4 };
enum ENUM_ANCHOR_POINT { ANCHOR_LEFT_UPPER, ANCHOR_LEFT, ANCHOR_LEFT_LOWER, ANCHOR_LOWER, ANCHOR_RIGHT_LOWER, ANCHOR_RIGHT, ANCHOR_RIGHT_UPPER, ANCHOR_UPPER, ANCHOR_CENTER };
enum ENUM_ARROW_ANCHOR { ANCHOR_TOP, ANCHOR_BOTTOM };
enum ENUM_BASE_CORNER { CORNER_LEFT_UPPER, CORNER_LEFT_LOWER, CORNER_RIGHT_LOWER, CORNER_RIGHT_UPPER };
enum ENUM_ALIGN_MODE { ALIGN_LEFT, ALIGN_CENTER, ALIGN_RIGHT };
enum ENUM_BORDER_TYPE { BORDER_FLAT, BORDER_RAISED, BORDER_SUNKEN };
enum ENUM_ELLIOT_WAVE_DEGREE
  {
   ELLIOTT_GRAND_SUPERCYCLE, ELLIOTT_SUPERCYCLE, ELLIOTT_CYCLE, ELLIOTT_PRIMARY, ELLIOTT_INTERMEDIATE, ELLIOTT_MINOR, ELLIOTT_MINUTE,
   ELLIOTT_MINUETTE, ELLIOTT_SUBMINUETTE
  };
enum ENUM_GANN_DIRECTION { GANN_UP_TREND, GANN_DOWN_TREND };

//==================================================================== chart
enum ENUM_CHART_PROPERTY_INTEGER
  {
   CHART_SHOW, CHART_IS_OBJECT, CHART_BRING_TO_TOP, CHART_CONTEXT_MENU, CHART_CROSSHAIR_TOOL, CHART_MOUSE_SCROLL, CHART_EVENT_MOUSE_WHEEL,
   CHART_EVENT_MOUSE_MOVE, CHART_EVENT_OBJECT_CREATE, CHART_EVENT_OBJECT_DELETE, CHART_MODE, CHART_FOREGROUND, CHART_SHIFT, CHART_AUTOSCROLL,
   CHART_KEYBOARD_CONTROL, CHART_QUICK_NAVIGATION, CHART_SCALE, CHART_SCALEFIX, CHART_SCALEFIX_11, CHART_SCALE_PT_PER_BAR, CHART_SHOW_TICKER,
   CHART_SHOW_OHLC, CHART_SHOW_BID_LINE, CHART_SHOW_ASK_LINE, CHART_SHOW_LAST_LINE, CHART_SHOW_PERIOD_SEP, CHART_SHOW_GRID, CHART_SHOW_VOLUMES,
   CHART_SHOW_OBJECT_DESCR, CHART_VISIBLE_BARS, CHART_WINDOWS_TOTAL, CHART_WINDOW_IS_VISIBLE, CHART_WINDOW_HANDLE, CHART_WINDOW_YDISTANCE,
   CHART_FIRST_VISIBLE_BAR, CHART_WIDTH_IN_BARS, CHART_WIDTH_IN_PIXELS, CHART_HEIGHT_IN_PIXELS, CHART_COLOR_BACKGROUND, CHART_COLOR_FOREGROUND,
   CHART_COLOR_GRID, CHART_COLOR_VOLUME, CHART_COLOR_CHART_UP, CHART_COLOR_CHART_DOWN, CHART_COLOR_CHART_LINE, CHART_COLOR_CANDLE_BULL,
   CHART_COLOR_CANDLE_BEAR, CHART_COLOR_BID, CHART_COLOR_ASK, CHART_COLOR_LAST, CHART_COLOR_STOP_LEVEL, CHART_SHOW_TRADE_LEVELS,
   CHART_DRAG_TRADE_LEVELS, CHART_SHOW_DATE_SCALE, CHART_SHOW_PRICE_SCALE, CHART_SHOW_ONE_CLICK, CHART_IS_MAXIMIZED, CHART_IS_MINIMIZED,
   CHART_IS_DOCKED, CHART_FLOAT_LEFT, CHART_FLOAT_TOP, CHART_FLOAT_RIGHT, CHART_FLOAT_BOTTOM, CHART_SHOW_TRADE_HISTORY
  };
enum ENUM_CHART_PROPERTY_DOUBLE { CHART_SHIFT_SIZE, CHART_FIXED_POSITION, CHART_FIXED_MAX, CHART_FIXED_MIN, CHART_POINTS_PER_BAR, CHART_PRICE_MIN, CHART_PRICE_MAX };
enum ENUM_CHART_PROPERTY_STRING { CHART_COMMENT, CHART_EXPERT_NAME, CHART_SCRIPT_NAME };
enum ENUM_CHART_MODE { CHART_BARS, CHART_CANDLES, CHART_LINE };
enum ENUM_CHART_VOLUME_MODE { CHART_VOLUME_HIDE, CHART_VOLUME_TICK, CHART_VOLUME_REAL };
enum ENUM_CHART_POSITION { CHART_BEGIN, CHART_CURRENT_POS, CHART_END };
enum ENUM_CHART_EVENT
  {
   CHARTEVENT_KEYDOWN = 0, CHARTEVENT_OBJECT_CLICK = 1, CHARTEVENT_OBJECT_DRAG = 2, CHARTEVENT_OBJECT_ENDEDIT = 3, CHARTEVENT_CLICK = 4,
   CHARTEVENT_CHART_CHANGE = 5, CHARTEVENT_OBJECT_CREATE = 7, CHARTEVENT_OBJECT_CHANGE = 8, CHARTEVENT_OBJECT_DELETE = 9,
   CHARTEVENT_MOUSE_MOVE = 10, CHARTEVENT_MOUSE_WHEEL = 11, CHARTEVENT_CUSTOM = 1000, CHARTEVENT_CUSTOM_LAST = 66535
  };

//==================================================================== trading
enum ENUM_ORDER_TYPE
  {
   ORDER_TYPE_BUY = 0, ORDER_TYPE_SELL = 1, ORDER_TYPE_BUY_LIMIT = 2, ORDER_TYPE_SELL_LIMIT = 3, ORDER_TYPE_BUY_STOP = 4,
   ORDER_TYPE_SELL_STOP = 5, ORDER_TYPE_BUY_STOP_LIMIT = 6, ORDER_TYPE_SELL_STOP_LIMIT = 7, ORDER_TYPE_CLOSE_BY = 8
  };
enum ENUM_ORDER_TYPE_FILLING { ORDER_FILLING_FOK = 0, ORDER_FILLING_IOC = 1, ORDER_FILLING_RETURN = 2, ORDER_FILLING_BOC = 3 };
enum ENUM_ORDER_TYPE_TIME { ORDER_TIME_GTC = 0, ORDER_TIME_DAY = 1, ORDER_TIME_SPECIFIED = 2, ORDER_TIME_SPECIFIED_DAY = 3 };
enum ENUM_ORDER_STATE
  {
   ORDER_STATE_STARTED = 0, ORDER_STATE_PLACED = 1, ORDER_STATE_CANCELED = 2, ORDER_STATE_PARTIAL = 3, ORDER_STATE_FILLED = 4,
   ORDER_STATE_REJECTED = 5, ORDER_STATE_EXPIRED = 6, ORDER_STATE_REQUEST_ADD = 7, ORDER_STATE_REQUEST_MODIFY = 8, ORDER_STATE_REQUEST_CANCEL = 9
  };
enum ENUM_ORDER_REASON { ORDER_REASON_CLIENT = 0, ORDER_REASON_MOBILE = 1, ORDER_REASON_WEB = 2, ORDER_REASON_EXPERT = 3, ORDER_REASON_SL = 4, ORDER_REASON_TP = 5, ORDER_REASON_SO = 6 };
enum ENUM_ORDER_PROPERTY_INTEGER
  {
   ORDER_TICKET, ORDER_TIME_SETUP, ORDER_TYPE, ORDER_STATE, ORDER_TIME_EXPIRATION, ORDER_TIME_DONE, ORDER_TIME_SETUP_MSC, ORDER_TIME_DONE_MSC,
   ORDER_TYPE_FILLING, ORDER_TYPE_TIME, ORDER_MAGIC, ORDER_REASON, ORDER_POSITION_ID, ORDER_POSITION_BY_ID
  };
enum ENUM_ORDER_PROPERTY_DOUBLE { ORDER_VOLUME_INITIAL, ORDER_VOLUME_CURRENT, ORDER_PRICE_OPEN, ORDER_SL, ORDER_TP, ORDER_PRICE_CURRENT, ORDER_PRICE_STOPLIMIT };
enum ENUM_ORDER_PROPERTY_STRING { ORDER_SYMBOL, ORDER_COMMENT, ORDER_EXTERNAL_ID };

enum ENUM_POSITION_TYPE { POSITION_TYPE_BUY = 0, POSITION_TYPE_SELL = 1 };
enum ENUM_POSITION_REASON { POSITION_REASON_CLIENT = 0, POSITION_REASON_MOBILE = 1, POSITION_REASON_WEB = 2, POSITION_REASON_EXPERT = 3 };
enum ENUM_POSITION_PROPERTY_INTEGER
  {
   POSITION_TICKET, POSITION_TIME, POSITION_TIME_MSC, POSITION_TIME_UPDATE, POSITION_TIME_UPDATE_MSC, POSITION_TYPE, POSITION_MAGIC,
   POSITION_IDENTIFIER, POSITION_REASON
  };
enum ENUM_POSITION_PROPERTY_DOUBLE { POSITION_VOLUME, POSITION_PRICE_OPEN, POSITION_SL, POSITION_TP, POSITION_PRICE_CURRENT, POSITION_SWAP, POSITION_PROFIT };
enum ENUM_POSITION_PROPERTY_STRING { POSITION_SYMBOL, POSITION_COMMENT, POSITION_EXTERNAL_ID };

enum ENUM_DEAL_TYPE
  {
   DEAL_TYPE_BUY = 0, DEAL_TYPE_SELL = 1, DEAL_TYPE_BALANCE = 2, DEAL_TYPE_CREDIT = 3, DEAL_TYPE_CHARGE = 4, DEAL_TYPE_CORRECTION = 5,
   DEAL_TYPE_BONUS = 6, DEAL_TYPE_COMMISSION = 7, DEAL_TYPE_COMMISSION_DAILY = 8, DEAL_TYPE_COMMISSION_MONTHLY = 9,
   DEAL_TYPE_COMMISSION_AGENT_DAILY = 10, DEAL_TYPE_COMMISSION_AGENT_MONTHLY = 11, DEAL_TYPE_INTEREST = 12, DEAL_TYPE_BUY_CANCELED = 13,
   DEAL_TYPE_SELL_CANCELED = 14, DEAL_DIVIDEND = 15, DEAL_DIVIDEND_FRANKED = 16, DEAL_TAX = 17
  };
enum ENUM_DEAL_ENTRY { DEAL_ENTRY_IN = 0, DEAL_ENTRY_OUT = 1, DEAL_ENTRY_INOUT = 2, DEAL_ENTRY_OUT_BY = 3 };
enum ENUM_DEAL_REASON
  {
   DEAL_REASON_CLIENT = 0, DEAL_REASON_MOBILE = 1, DEAL_REASON_WEB = 2, DEAL_REASON_EXPERT = 3, DEAL_REASON_SL = 4, DEAL_REASON_TP = 5,
   DEAL_REASON_SO = 6, DEAL_REASON_ROLLOVER = 7, DEAL_REASON_VMARGIN = 8, DEAL_REASON_SPLIT = 9, DEAL_REASON_CORPORATE_ACTION = 10
  };
enum ENUM_DEAL_PROPERTY_INTEGER { DEAL_TICKET, DEAL_ORDER, DEAL_TIME, DEAL_TIME_MSC, DEAL_TYPE, DEAL_ENTRY, DEAL_MAGIC, DEAL_REASON, DEAL_POSITION_ID };
enum ENUM_DEAL_PROPERTY_DOUBLE { DEAL_VOLUME, DEAL_PRICE, DEAL_COMMISSION, DEAL_SWAP, DEAL_PROFIT, DEAL_FEE, DEAL_SL, DEAL_TP };
enum ENUM_DEAL_PROPERTY_STRING { DEAL_SYMBOL, DEAL_COMMENT, DEAL_EXTERNAL_ID };

enum ENUM_TRADE_REQUEST_ACTIONS { TRADE_ACTION_DEAL = 1, TRADE_ACTION_PENDING = 5, TRADE_ACTION_SLTP = 6, TRADE_ACTION_MODIFY = 7, TRADE_ACTION_REMOVE = 8, TRADE_ACTION_CLOSE_BY = 10 };
enum ENUM_TRADE_TRANSACTION_TYPE
  {
   TRADE_TRANSACTION_ORDER_ADD = 0, TRADE_TRANSACTION_ORDER_UPDATE = 1, TRADE_TRANSACTION_ORDER_DELETE = 2, TRADE_TRANSACTION_DEAL_ADD = 3,
   TRADE_TRANSACTION_DEAL_UPDATE = 4, TRADE_TRANSACTION_DEAL_DELETE = 5, TRADE_TRANSACTION_HISTORY_ADD = 6, TRADE_TRANSACTION_HISTORY_UPDATE = 7,
   TRADE_TRANSACTION_HISTORY_DELETE = 8, TRADE_TRANSACTION_POSITION = 9, TRADE_TRANSACTION_REQUEST = 10
  };
// trade server return codes (uint in MQL5; unsigned enum here so comparing
// with CTrade::ResultRetcode() is sign-clean)
enum ENUM_TRADE_RETCODE : unsigned int
  {
   TRADE_RETCODE_REQUOTE = 10004, TRADE_RETCODE_REJECT = 10006, TRADE_RETCODE_CANCEL = 10007, TRADE_RETCODE_PLACED = 10008,
   TRADE_RETCODE_DONE = 10009, TRADE_RETCODE_DONE_PARTIAL = 10010, TRADE_RETCODE_ERROR = 10011, TRADE_RETCODE_TIMEOUT = 10012,
   TRADE_RETCODE_INVALID = 10013, TRADE_RETCODE_INVALID_VOLUME = 10014, TRADE_RETCODE_INVALID_PRICE = 10015, TRADE_RETCODE_INVALID_STOPS = 10016,
   TRADE_RETCODE_TRADE_DISABLED = 10017, TRADE_RETCODE_MARKET_CLOSED = 10018, TRADE_RETCODE_NO_MONEY = 10019, TRADE_RETCODE_PRICE_CHANGED = 10020,
   TRADE_RETCODE_PRICE_OFF = 10021, TRADE_RETCODE_INVALID_EXPIRATION = 10022, TRADE_RETCODE_ORDER_CHANGED = 10023,
   TRADE_RETCODE_TOO_MANY_REQUESTS = 10024, TRADE_RETCODE_NO_CHANGES = 10025, TRADE_RETCODE_SERVER_DISABLES_AT = 10026,
   TRADE_RETCODE_CLIENT_DISABLES_AT = 10027, TRADE_RETCODE_LOCKED = 10028, TRADE_RETCODE_FROZEN = 10029, TRADE_RETCODE_INVALID_FILL = 10030,
   TRADE_RETCODE_CONNECTION = 10031, TRADE_RETCODE_ONLY_REAL = 10032, TRADE_RETCODE_LIMIT_ORDERS = 10033, TRADE_RETCODE_LIMIT_VOLUME = 10034,
   TRADE_RETCODE_INVALID_ORDER = 10035, TRADE_RETCODE_POSITION_CLOSED = 10036, TRADE_RETCODE_INVALID_CLOSE_VOLUME = 10038,
   TRADE_RETCODE_CLOSE_ORDER_EXIST = 10039, TRADE_RETCODE_LIMIT_POSITIONS = 10040, TRADE_RETCODE_REJECT_CANCEL = 10041,
   TRADE_RETCODE_LONG_ONLY = 10042, TRADE_RETCODE_SHORT_ONLY = 10043, TRADE_RETCODE_CLOSE_ONLY = 10044, TRADE_RETCODE_FIFO_CLOSE = 10045,
   TRADE_RETCODE_HEDGE_PROHIBITED = 10046
  };

//==================================================================== runtime error codes (GetLastError)
enum ENUM_ERROR_CODE
  {
   ERR_SUCCESS = 0, ERR_INTERNAL_ERROR = 4001, ERR_WRONG_INTERNAL_PARAMETER = 4002, ERR_INVALID_PARAMETER = 4003, ERR_NOT_ENOUGH_MEMORY = 4004,
   ERR_STRUCT_WITHOBJECTS_ORCLASS = 4005, ERR_INVALID_ARRAY = 4006, ERR_ARRAY_RESIZE_ERROR = 4007, ERR_STRING_RESIZE_ERROR = 4008,
   ERR_NOTINITIALIZED_STRING = 4009, ERR_INVALID_DATETIME = 4010, ERR_ARRAY_BAD_SIZE = 4011, ERR_INVALID_POINTER = 4012, ERR_INVALID_POINTER_TYPE = 4013,
   ERR_FUNCTION_NOT_ALLOWED = 4014, ERR_RESOURCE_NAME_DUPLICATED = 4015, ERR_RESOURCE_NOT_FOUND = 4016, ERR_RESOURCE_UNSUPPORTED_TYPE = 4017,
   ERR_RESOURCE_NAME_IS_TOO_LONG = 4018, ERR_MATH_OVERFLOW = 4019, ERR_SLEEP_ERROR = 4020, ERR_PROGRAM_STOPPED = 4022,
   ERR_CHART_WRONG_ID = 4101, ERR_CHART_NO_REPLY = 4102, ERR_CHART_NOT_FOUND = 4103, ERR_CHART_NO_EXPERT = 4104, ERR_CHART_CANNOT_OPEN = 4105,
   ERR_CHART_CANNOT_CHANGE = 4106, ERR_CHART_WRONG_PARAMETER = 4107, ERR_CHART_CANNOT_CREATE_TIMER = 4108, ERR_CHART_WRONG_PROPERTY = 4109,
   ERR_CHART_SCREENSHOT_FAILED = 4110, ERR_CHART_NAVIGATE_FAILED = 4111, ERR_CHART_TEMPLATE_FAILED = 4112, ERR_CHART_WINDOW_NOT_FOUND = 4113,
   ERR_CHART_INDICATOR_CANNOT_ADD = 4114, ERR_CHART_INDICATOR_CANNOT_DEL = 4115, ERR_CHART_INDICATOR_NOT_FOUND = 4116,
   ERR_OBJECT_ERROR = 4201, ERR_OBJECT_NOT_FOUND = 4202, ERR_OBJECT_WRONG_PROPERTY = 4203, ERR_OBJECT_GETDATE_FAILED = 4204, ERR_OBJECT_GETVALUE_FAILED = 4205,
   ERR_MARKET_UNKNOWN_SYMBOL = 4301, ERR_MARKET_NOT_SELECTED = 4302, ERR_MARKET_WRONG_PROPERTY = 4303, ERR_MARKET_LASTTIME_UNKNOWN = 4304, ERR_MARKET_SELECT_ERROR = 4305,
   ERR_HISTORY_NOT_FOUND = 4401, ERR_HISTORY_WRONG_PROPERTY = 4402, ERR_HISTORY_TIMEOUT = 4403, ERR_HISTORY_BARS_LIMIT = 4404, ERR_HISTORY_LOAD_ERRORS = 4405, ERR_HISTORY_SMALL_BUFFER = 4407,
   ERR_GLOBALVARIABLE_NOT_FOUND = 4501, ERR_GLOBALVARIABLE_EXISTS = 4502, ERR_GLOBALVARIABLE_NOT_MODIFIED = 4503, ERR_GLOBALVARIABLE_CANNOTREAD = 4504, ERR_GLOBALVARIABLE_CANNOTWRITE = 4505,
   ERR_MAIL_SEND_FAILED = 4510, ERR_PLAY_SOUND_FAILED = 4511, ERR_MQL5_WRONG_PROPERTY = 4512, ERR_TERMINAL_WRONG_PROPERTY = 4513, ERR_FTP_SEND_FAILED = 4514,
   ERR_NOTIFICATION_SEND_FAILED = 4515, ERR_NOTIFICATION_WRONG_PARAMETER = 4516, ERR_NOTIFICATION_WRONG_SETTINGS = 4517, ERR_NOTIFICATION_TOO_FREQUENT = 4518,
   ERR_FTP_NOSERVER = 4519, ERR_FTP_NOLOGIN = 4520, ERR_FTP_FILE_ERROR = 4521, ERR_FTP_CONNECT_FAILED = 4522, ERR_FTP_CHANGEDIR = 4523, ERR_FTP_NOTHING_TO_SEND = 4524,
   ERR_BUFFERS_NO_MEMORY = 4601, ERR_BUFFERS_WRONG_INDEX = 4602, ERR_CUSTOM_WRONG_PROPERTY = 4603,
   ERR_ACCOUNT_WRONG_PROPERTY = 4701, ERR_TRADE_WRONG_PROPERTY = 4751, ERR_TRADE_DISABLED = 4752, ERR_TRADE_POSITION_NOT_FOUND = 4753,
   ERR_TRADE_ORDER_NOT_FOUND = 4754, ERR_TRADE_DEAL_NOT_FOUND = 4755, ERR_TRADE_SEND_FAILED = 4756, ERR_TRADE_CALC_FAILED = 4758,
   ERR_INDICATOR_UNKNOWN_SYMBOL = 4801, ERR_INDICATOR_CANNOT_CREATE = 4802, ERR_INDICATOR_NO_MEMORY = 4803, ERR_INDICATOR_CANNOT_APPLY = 4804,
   ERR_INDICATOR_CANNOT_ADD = 4805, ERR_INDICATOR_DATA_NOT_FOUND = 4806, ERR_INDICATOR_WRONG_HANDLE = 4807, ERR_INDICATOR_WRONG_PARAMETERS = 4808,
   ERR_INDICATOR_PARAMETERS_MISSING = 4809, ERR_INDICATOR_CUSTOM_NAME = 4810, ERR_INDICATOR_PARAMETER_TYPE = 4811, ERR_INDICATOR_WRONG_INDEX = 4812,
   ERR_BOOKS_CANNOT_ADD = 4901, ERR_BOOKS_CANNOT_DELETE = 4902, ERR_BOOKS_CANNOT_GET = 4903, ERR_BOOKS_CANNOT_SUBSCRIBE = 4904,
   ERR_TOO_MANY_FILES = 5001, ERR_WRONG_FILENAME = 5002, ERR_TOO_LONG_FILENAME = 5003, ERR_CANNOT_OPEN_FILE = 5004, ERR_FILE_CACHEBUFFER_ERROR = 5005,
   ERR_CANNOT_DELETE_FILE = 5006, ERR_INVALID_FILEHANDLE = 5007, ERR_WRONG_FILEHANDLE = 5008, ERR_FILE_NOTTOWRITE = 5009, ERR_FILE_NOTTOREAD = 5010,
   ERR_FILE_NOTBIN = 5011, ERR_FILE_NOTTXT = 5012, ERR_FILE_NOTTXTORCSV = 5013, ERR_FILE_NOTCSV = 5014, ERR_FILE_READERROR = 5015,
   ERR_FILE_BINSTRINGSIZE = 5016, ERR_INCOMPATIBLE_FILE = 5017, ERR_FILE_IS_DIRECTORY = 5018, ERR_FILE_NOT_EXIST = 5019, ERR_FILE_CANNOT_REWRITE = 5020,
   ERR_WRONG_DIRECTORYNAME = 5021, ERR_DIRECTORY_NOT_EXIST = 5022, ERR_FILE_ISNOT_DIRECTORY = 5023, ERR_CANNOT_DELETE_DIRECTORY = 5024,
   ERR_CANNOT_CLEAN_DIRECTORY = 5025, ERR_FILE_WRITEERROR = 5026, ERR_FILE_ENDOFFILE = 5027,
   ERR_NO_STRING_DATE = 5030, ERR_WRONG_STRING_DATE = 5031, ERR_WRONG_STRING_TIME = 5032, ERR_STRING_TIME_ERROR = 5033, ERR_STRING_OUT_OF_MEMORY = 5034,
   ERR_STRING_SMALL_LEN = 5035, ERR_STRING_TOO_BIGNUMBER = 5036, ERR_WRONG_FORMATSTRING = 5037, ERR_TOO_MANY_FORMATTERS = 5038, ERR_TOO_MANY_PARAMETERS = 5039,
   ERR_WRONG_STRING_PARAMETER = 5040, ERR_STRINGPOS_OUTOFRANGE = 5041, ERR_STRING_ZEROADDED = 5042, ERR_STRING_UNKNOWNTYPE = 5043, ERR_WRONG_STRING_OBJECT = 5044,
   ERR_INCOMPATIBLE_ARRAYS = 5050, ERR_SMALL_ASSERIES_ARRAY = 5051, ERR_SMALL_ARRAY = 5052, ERR_ZEROSIZE_ARRAY = 5053, ERR_NUMBER_ARRAYS_ONLY = 5054,
   ERR_ONEDIM_ARRAYS_ONLY = 5055, ERR_SERIES_ARRAY = 5056, ERR_DOUBLE_ARRAY_ONLY = 5057, ERR_FLOAT_ARRAY_ONLY = 5058, ERR_LONG_ARRAY_ONLY = 5059,
   ERR_INT_ARRAY_ONLY = 5060, ERR_SHORT_ARRAY_ONLY = 5061, ERR_CHAR_ARRAY_ONLY = 5062, ERR_STRING_ARRAY_ONLY = 5063,
   ERR_WEBREQUEST_INVALID_ADDRESS = 5200, ERR_WEBREQUEST_CONNECT_FAILED = 5201, ERR_WEBREQUEST_TIMEOUT = 5202, ERR_WEBREQUEST_REQUEST_FAILED = 5203,
   ERR_USER_ERROR_FIRST = 65536
  };

//==================================================================== account
enum ENUM_ACCOUNT_INFO_INTEGER
  {
   ACCOUNT_LOGIN, ACCOUNT_TRADE_MODE, ACCOUNT_LEVERAGE, ACCOUNT_LIMIT_ORDERS, ACCOUNT_MARGIN_SO_MODE, ACCOUNT_TRADE_ALLOWED, ACCOUNT_TRADE_EXPERT,
   ACCOUNT_MARGIN_MODE, ACCOUNT_CURRENCY_DIGITS, ACCOUNT_FIFO_CLOSE, ACCOUNT_HEDGE_ALLOWED
  };
enum ENUM_ACCOUNT_INFO_DOUBLE
  {
   ACCOUNT_BALANCE, ACCOUNT_CREDIT, ACCOUNT_PROFIT, ACCOUNT_EQUITY, ACCOUNT_MARGIN, ACCOUNT_MARGIN_FREE, ACCOUNT_MARGIN_LEVEL, ACCOUNT_MARGIN_SO_CALL,
   ACCOUNT_MARGIN_SO_SO, ACCOUNT_MARGIN_INITIAL, ACCOUNT_MARGIN_MAINTENANCE, ACCOUNT_ASSETS, ACCOUNT_LIABILITIES, ACCOUNT_COMMISSION_BLOCKED
  };
enum ENUM_ACCOUNT_INFO_STRING { ACCOUNT_NAME, ACCOUNT_SERVER, ACCOUNT_CURRENCY, ACCOUNT_COMPANY };
enum ENUM_ACCOUNT_TRADE_MODE { ACCOUNT_TRADE_MODE_DEMO = 0, ACCOUNT_TRADE_MODE_CONTEST = 1, ACCOUNT_TRADE_MODE_REAL = 2 };
enum ENUM_ACCOUNT_STOPOUT_MODE { ACCOUNT_STOPOUT_MODE_PERCENT = 0, ACCOUNT_STOPOUT_MODE_MONEY = 1 };
enum ENUM_ACCOUNT_MARGIN_MODE { ACCOUNT_MARGIN_MODE_RETAIL_NETTING = 0, ACCOUNT_MARGIN_MODE_EXCHANGE = 1, ACCOUNT_MARGIN_MODE_RETAIL_HEDGING = 2 };

//==================================================================== symbol
enum ENUM_SYMBOL_INFO_INTEGER
  {
   SYMBOL_SUBSCRIPTION_DELAY, SYMBOL_SECTOR, SYMBOL_INDUSTRY, SYMBOL_CUSTOM, SYMBOL_BACKGROUND_COLOR, SYMBOL_CHART_MODE, SYMBOL_EXIST, SYMBOL_SELECT,
   SYMBOL_VISIBLE, SYMBOL_SESSION_DEALS, SYMBOL_SESSION_BUY_ORDERS, SYMBOL_SESSION_SELL_ORDERS, SYMBOL_VOLUME, SYMBOL_VOLUMEHIGH, SYMBOL_VOLUMELOW,
   SYMBOL_TIME, SYMBOL_TIME_MSC, SYMBOL_DIGITS, SYMBOL_SPREAD_FLOAT, SYMBOL_SPREAD, SYMBOL_TICKS_BOOKDEPTH, SYMBOL_TRADE_CALC_MODE, SYMBOL_TRADE_MODE,
   SYMBOL_START_TIME, SYMBOL_EXPIRATION_TIME, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL, SYMBOL_TRADE_EXEMODE, SYMBOL_SWAP_MODE,
   SYMBOL_SWAP_ROLLOVER3DAYS, SYMBOL_MARGIN_HEDGED_USE_LEG, SYMBOL_EXPIRATION_MODE, SYMBOL_FILLING_MODE, SYMBOL_ORDER_MODE, SYMBOL_ORDER_GTC_MODE,
   SYMBOL_OPTION_MODE, SYMBOL_OPTION_RIGHT
  };
enum ENUM_SYMBOL_INFO_DOUBLE
  {
   SYMBOL_BID, SYMBOL_BIDHIGH, SYMBOL_BIDLOW, SYMBOL_ASK, SYMBOL_ASKHIGH, SYMBOL_ASKLOW, SYMBOL_LAST, SYMBOL_LASTHIGH, SYMBOL_LASTLOW,
   SYMBOL_VOLUME_REAL, SYMBOL_VOLUMEHIGH_REAL, SYMBOL_VOLUMELOW_REAL, SYMBOL_OPTION_STRIKE, SYMBOL_POINT, SYMBOL_TRADE_TICK_VALUE,
   SYMBOL_TRADE_TICK_VALUE_PROFIT, SYMBOL_TRADE_TICK_VALUE_LOSS, SYMBOL_TRADE_TICK_SIZE, SYMBOL_TRADE_CONTRACT_SIZE, SYMBOL_TRADE_ACCRUED_INTEREST,
   SYMBOL_TRADE_FACE_VALUE, SYMBOL_TRADE_LIQUIDITY_RATE, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX, SYMBOL_VOLUME_STEP, SYMBOL_VOLUME_LIMIT,
   SYMBOL_SWAP_LONG, SYMBOL_SWAP_SHORT, SYMBOL_SWAP_SUNDAY, SYMBOL_SWAP_MONDAY, SYMBOL_SWAP_TUESDAY, SYMBOL_SWAP_WEDNESDAY, SYMBOL_SWAP_THURSDAY,
   SYMBOL_SWAP_FRIDAY, SYMBOL_SWAP_SATURDAY, SYMBOL_MARGIN_INITIAL, SYMBOL_MARGIN_MAINTENANCE, SYMBOL_MARGIN_LONG, SYMBOL_MARGIN_SHORT,
   SYMBOL_MARGIN_LIMIT, SYMBOL_MARGIN_STOP, SYMBOL_MARGIN_STOPLIMIT, SYMBOL_SESSION_VOLUME, SYMBOL_SESSION_TURNOVER, SYMBOL_SESSION_INTEREST,
   SYMBOL_SESSION_BUY_ORDERS_VOLUME, SYMBOL_SESSION_SELL_ORDERS_VOLUME, SYMBOL_SESSION_OPEN, SYMBOL_SESSION_CLOSE, SYMBOL_SESSION_AW,
   SYMBOL_SESSION_PRICE_SETTLEMENT, SYMBOL_SESSION_PRICE_LIMIT_MIN, SYMBOL_SESSION_PRICE_LIMIT_MAX, SYMBOL_MARGIN_HEDGED, SYMBOL_PRICE_CHANGE,
   SYMBOL_PRICE_VOLATILITY, SYMBOL_PRICE_THEORETICAL, SYMBOL_PRICE_DELTA, SYMBOL_PRICE_THETA, SYMBOL_PRICE_GAMMA, SYMBOL_PRICE_VEGA, SYMBOL_PRICE_RHO,
   SYMBOL_PRICE_OMEGA, SYMBOL_PRICE_SENSITIVITY
  };
enum ENUM_SYMBOL_INFO_STRING
  {
   SYMBOL_BASIS, SYMBOL_CATEGORY, SYMBOL_COUNTRY, SYMBOL_SECTOR_NAME, SYMBOL_INDUSTRY_NAME, SYMBOL_CURRENCY_BASE, SYMBOL_CURRENCY_PROFIT,
   SYMBOL_CURRENCY_MARGIN, SYMBOL_BANK, SYMBOL_DESCRIPTION, SYMBOL_EXCHANGE, SYMBOL_FORMULA, SYMBOL_ISIN, SYMBOL_PAGE, SYMBOL_PATH
  };
enum ENUM_SYMBOL_TRADE_MODE { SYMBOL_TRADE_MODE_DISABLED = 0, SYMBOL_TRADE_MODE_LONGONLY = 1, SYMBOL_TRADE_MODE_SHORTONLY = 2, SYMBOL_TRADE_MODE_CLOSEONLY = 3, SYMBOL_TRADE_MODE_FULL = 4 };
enum ENUM_SYMBOL_TRADE_EXECUTION { SYMBOL_TRADE_EXECUTION_REQUEST = 0, SYMBOL_TRADE_EXECUTION_INSTANT = 1, SYMBOL_TRADE_EXECUTION_MARKET = 2, SYMBOL_TRADE_EXECUTION_EXCHANGE = 3 };
enum ENUM_SYMBOL_CALC_MODE
  {
   SYMBOL_CALC_MODE_FOREX, SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE, SYMBOL_CALC_MODE_FUTURES, SYMBOL_CALC_MODE_CFD, SYMBOL_CALC_MODE_CFDINDEX,
   SYMBOL_CALC_MODE_CFDLEVERAGE, SYMBOL_CALC_MODE_EXCH_STOCKS, SYMBOL_CALC_MODE_EXCH_FUTURES, SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS,
   SYMBOL_CALC_MODE_EXCH_BONDS, SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX, SYMBOL_CALC_MODE_EXCH_BONDS_MOEX, SYMBOL_CALC_MODE_SERV_COLLATERAL
  };
enum ENUM_SYMBOL_SWAP_MODE
  {
   SYMBOL_SWAP_MODE_DISABLED, SYMBOL_SWAP_MODE_POINTS, SYMBOL_SWAP_MODE_CURRENCY_SYMBOL, SYMBOL_SWAP_MODE_CURRENCY_MARGIN, SYMBOL_SWAP_MODE_CURRENCY_DEPOSIT,
   SYMBOL_SWAP_MODE_INTEREST_CURRENT, SYMBOL_SWAP_MODE_INTEREST_OPEN, SYMBOL_SWAP_MODE_REOPEN_CURRENT, SYMBOL_SWAP_MODE_REOPEN_BID
  };
enum ENUM_SYMBOL_CHART_MODE { SYMBOL_CHART_MODE_BID, SYMBOL_CHART_MODE_LAST };
enum ENUM_SYMBOL_OPTION_MODE { SYMBOL_OPTION_MODE_EUROPEAN, SYMBOL_OPTION_MODE_AMERICAN };
enum ENUM_SYMBOL_OPTION_RIGHT { SYMBOL_OPTION_RIGHT_CALL, SYMBOL_OPTION_RIGHT_PUT };
enum ENUM_BOOK_TYPE { BOOK_TYPE_SELL = 1, BOOK_TYPE_BUY = 2, BOOK_TYPE_SELL_MARKET = 3, BOOK_TYPE_BUY_MARKET = 4 };

//==================================================================== terminal / mql
enum ENUM_TERMINAL_INFO_INTEGER
  {
   TERMINAL_BUILD, TERMINAL_CONNECTED, TERMINAL_DLLS_ALLOWED, TERMINAL_TRADE_ALLOWED, TERMINAL_EMAIL_ENABLED, TERMINAL_FTP_ENABLED,
   TERMINAL_NOTIFICATIONS_ENABLED, TERMINAL_MAXBARS, TERMINAL_MQID, TERMINAL_CODEPAGE, TERMINAL_CPU_CORES, TERMINAL_DISK_SPACE,
   TERMINAL_MEMORY_PHYSICAL, TERMINAL_MEMORY_TOTAL, TERMINAL_MEMORY_AVAILABLE, TERMINAL_MEMORY_USED, TERMINAL_X64, TERMINAL_OPENCL_SUPPORT,
   TERMINAL_SCREEN_DPI, TERMINAL_PING_LAST, TERMINAL_VPS, TERMINAL_KEYSTATE_LEFT, TERMINAL_KEYSTATE_UP, TERMINAL_KEYSTATE_RIGHT,
   TERMINAL_KEYSTATE_DOWN, TERMINAL_KEYSTATE_SHIFT, TERMINAL_KEYSTATE_CONTROL, TERMINAL_KEYSTATE_MENU, TERMINAL_KEYSTATE_CAPSLOCK,
   TERMINAL_KEYSTATE_NUMLOCK, TERMINAL_KEYSTATE_SCRLOCK, TERMINAL_KEYSTATE_ENTER, TERMINAL_KEYSTATE_INSERT, TERMINAL_KEYSTATE_DELETE,
   TERMINAL_KEYSTATE_HOME, TERMINAL_KEYSTATE_END, TERMINAL_KEYSTATE_TAB, TERMINAL_KEYSTATE_PAGEUP, TERMINAL_KEYSTATE_PAGEDOWN,
   TERMINAL_KEYSTATE_ESCAPE, TERMINAL_COMMUNITY_ACCOUNT, TERMINAL_COMMUNITY_CONNECTION, TERMINAL_SCREEN_LEFT, TERMINAL_SCREEN_TOP,
   TERMINAL_SCREEN_WIDTH, TERMINAL_SCREEN_HEIGHT, TERMINAL_LEFT, TERMINAL_TOP, TERMINAL_RIGHT, TERMINAL_BOTTOM
  };
enum ENUM_TERMINAL_INFO_DOUBLE { TERMINAL_COMMUNITY_BALANCE, TERMINAL_RETRANSMISSION };
enum ENUM_TERMINAL_INFO_STRING { TERMINAL_LANGUAGE, TERMINAL_COMPANY, TERMINAL_NAME, TERMINAL_PATH, TERMINAL_DATA_PATH, TERMINAL_COMMONDATA_PATH };
enum ENUM_MQL_INFO_INTEGER
  {
   MQL_PROGRAM_TYPE, MQL_DLLS_ALLOWED, MQL_TRADE_ALLOWED, MQL_SIGNALS_ALLOWED, MQL_DEBUG, MQL_PROFILER, MQL_TESTER, MQL_OPTIMIZATION,
   MQL_VISUAL_MODE, MQL_FRAME_MODE, MQL_LICENSE_TYPE, MQL_FORWARD, MQL_STARTDATE, MQL_MEMORY_LIMIT, MQL_MEMORY_USED, MQL_HANDLES_USED
  };
enum ENUM_MQL_INFO_STRING { MQL_PROGRAM_NAME, MQL_PROGRAM_PATH };

//==================================================================== files
enum ENUM_FILE_OPEN_FLAGS
  {
   FILE_READ = 1, FILE_WRITE = 2, FILE_BIN = 4, FILE_CSV = 8, FILE_TXT = 16, FILE_ANSI = 32, FILE_UNICODE = 64,
   FILE_SHARE_READ = 128, FILE_SHARE_WRITE = 256, FILE_REWRITE = 512, FILE_COMMON = 4096
  };
enum ENUM_FILE_PROPERTY_INTEGER
  {
   FILE_EXISTS, FILE_CREATE_DATE, FILE_MODIFY_DATE, FILE_ACCESS_DATE, FILE_SIZE, FILE_POSITION, FILE_END, FILE_LINE_END, FILE_IS_COMMON,
   FILE_IS_TEXT, FILE_IS_BINARY, FILE_IS_CSV, FILE_IS_ANSI, FILE_IS_READABLE, FILE_IS_WRITABLE
  };
enum ENUM_FILE_POSITION { SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2 };

//==================================================================== misc
enum ENUM_CALENDAR_EVENT_IMPORTANCE { CALENDAR_IMPORTANCE_NONE, CALENDAR_IMPORTANCE_LOW, CALENDAR_IMPORTANCE_MODERATE, CALENDAR_IMPORTANCE_HIGH };
enum ENUM_CALENDAR_EVENT_IMPACT { CALENDAR_IMPACT_NA, CALENDAR_IMPACT_POSITIVE, CALENDAR_IMPACT_NEGATIVE };
enum ENUM_CRYPT_METHOD { CRYPT_BASE64, CRYPT_AES128, CRYPT_AES256, CRYPT_DES, CRYPT_HASH_SHA1, CRYPT_HASH_SHA256, CRYPT_HASH_MD5, CRYPT_ARCH_ZIP };
enum ENUM_STAT_FLAG
  {
   STAT_INITIAL_DEPOSIT, STAT_WITHDRAWAL, STAT_PROFIT, STAT_GROSS_PROFIT, STAT_GROSS_LOSS, STAT_MAX_PROFITTRADE, STAT_MAX_LOSSTRADE,
   STAT_CONPROFITMAX, STAT_CONPROFITMAX_TRADES, STAT_MAX_CONWINS, STAT_MAX_CONPROFIT_TRADES, STAT_CONLOSSMAX, STAT_CONLOSSMAX_TRADES, STAT_MAX_CONLOSSES,
   STAT_MAX_CONLOSS_TRADES, STAT_BALANCEMIN, STAT_BALANCE_DD, STAT_BALANCEDD_PERCENT, STAT_BALANCE_DDREL_PERCENT, STAT_BALANCE_DD_RELATIVE,
   STAT_EQUITYMIN, STAT_EQUITY_DD, STAT_EQUITYDD_PERCENT, STAT_EQUITY_DDREL_PERCENT, STAT_EQUITY_DD_RELATIVE, STAT_EXPECTED_PAYOFF, STAT_PROFIT_FACTOR,
   STAT_RECOVERY_FACTOR, STAT_SHARPE_RATIO, STAT_MIN_MARGINLEVEL, STAT_CUSTOM_ONTESTER, STAT_DEALS, STAT_TRADES, STAT_PROFIT_TRADES, STAT_LOSS_TRADES,
   STAT_SHORT_TRADES, STAT_LONG_TRADES, STAT_PROFIT_SHORTTRADES, STAT_PROFIT_LONGTRADES, STAT_PROFITTRADES_AVGCON, STAT_LOSSTRADES_AVGCON
  };

//==================================================================== web colors (MQL5 BGR encoding 0x00BBGGRR)
#define MQL_COLOR(name, v) const color name = (color)(v);
MQL_COLOR(clrBlack, 0x000000) MQL_COLOR(clrDarkGreen, 0x006400) MQL_COLOR(clrDarkSlateGray, 0x4F4F2F) MQL_COLOR(clrOlive, 0x008080)
MQL_COLOR(clrGreen, 0x008000) MQL_COLOR(clrTeal, 0x808000) MQL_COLOR(clrNavy, 0x800000) MQL_COLOR(clrPurple, 0x800080)
MQL_COLOR(clrMaroon, 0x000080) MQL_COLOR(clrIndigo, 0x82004B) MQL_COLOR(clrMidnightBlue, 0x701919) MQL_COLOR(clrDarkBlue, 0x8B0000)
MQL_COLOR(clrDarkOliveGreen, 0x2F6B55) MQL_COLOR(clrSaddleBrown, 0x13458B) MQL_COLOR(clrForestGreen, 0x228B22) MQL_COLOR(clrOliveDrab, 0x238E6B)
MQL_COLOR(clrSeaGreen, 0x578B2E) MQL_COLOR(clrDarkGoldenrod, 0x0B86B8) MQL_COLOR(clrDarkSlateBlue, 0x8B3D48) MQL_COLOR(clrSienna, 0x2D52A0)
MQL_COLOR(clrMediumBlue, 0xCD0000) MQL_COLOR(clrBrown, 0x2A2AA5) MQL_COLOR(clrDarkTurquoise, 0xD1CE00) MQL_COLOR(clrDimGray, 0x696969)
MQL_COLOR(clrLightSeaGreen, 0xAAB220) MQL_COLOR(clrDarkViolet, 0xD30094) MQL_COLOR(clrFireBrick, 0x2222B2) MQL_COLOR(clrMediumVioletRed, 0x8515C7)
MQL_COLOR(clrMediumSeaGreen, 0x71B33C) MQL_COLOR(clrChocolate, 0x1E69D2) MQL_COLOR(clrCrimson, 0x3C14DC) MQL_COLOR(clrSteelBlue, 0xB48246)
MQL_COLOR(clrGoldenrod, 0x20A5DA) MQL_COLOR(clrMediumSpringGreen, 0x9AFA00) MQL_COLOR(clrLawnGreen, 0x00FC7C) MQL_COLOR(clrCadetBlue, 0xA09E5F)
MQL_COLOR(clrDarkOrchid, 0xCC3299) MQL_COLOR(clrYellowGreen, 0x32CD9A) MQL_COLOR(clrLimeGreen, 0x32CD32) MQL_COLOR(clrOrangeRed, 0x0045FF)
MQL_COLOR(clrDarkOrange, 0x008CFF) MQL_COLOR(clrOrange, 0x00A5FF) MQL_COLOR(clrGold, 0x00D7FF) MQL_COLOR(clrYellow, 0x00FFFF)
MQL_COLOR(clrChartreuse, 0x00FF7F) MQL_COLOR(clrLime, 0x00FF00) MQL_COLOR(clrSpringGreen, 0x7FFF00) MQL_COLOR(clrAqua, 0xFFFF00)
MQL_COLOR(clrDeepSkyBlue, 0xFFBF00) MQL_COLOR(clrBlue, 0xFF0000) MQL_COLOR(clrMagenta, 0xFF00FF) MQL_COLOR(clrRed, 0x0000FF)
MQL_COLOR(clrGray, 0x808080) MQL_COLOR(clrSlateGray, 0x908070) MQL_COLOR(clrPeru, 0x3F85CD) MQL_COLOR(clrBlueViolet, 0xE22B8A)
MQL_COLOR(clrLightSlateGray, 0x998877) MQL_COLOR(clrDeepPink, 0x9314FF) MQL_COLOR(clrMediumTurquoise, 0xCCD148) MQL_COLOR(clrDodgerBlue, 0xFF901E)
MQL_COLOR(clrTurquoise, 0xD0E040) MQL_COLOR(clrRoyalBlue, 0xE16941) MQL_COLOR(clrSlateBlue, 0xCD5A6A) MQL_COLOR(clrDarkKhaki, 0x6BB7BD)
MQL_COLOR(clrIndianRed, 0x5C5CCD) MQL_COLOR(clrMediumOrchid, 0xD355BA) MQL_COLOR(clrGreenYellow, 0x2FFFAD) MQL_COLOR(clrMediumAquamarine, 0xAACD66)
MQL_COLOR(clrDarkSeaGreen, 0x8FBC8F) MQL_COLOR(clrTomato, 0x4763FF) MQL_COLOR(clrRosyBrown, 0x8F8FBC) MQL_COLOR(clrOrchid, 0xD670DA)
MQL_COLOR(clrMediumPurple, 0xDB7093) MQL_COLOR(clrPaleVioletRed, 0x9370DB) MQL_COLOR(clrCoral, 0x507FFF) MQL_COLOR(clrCornflowerBlue, 0xED9564)
MQL_COLOR(clrDarkGray, 0xA9A9A9) MQL_COLOR(clrSandyBrown, 0x60A4F4) MQL_COLOR(clrMediumSlateBlue, 0xEE687B) MQL_COLOR(clrTan, 0x8CB4D2)
MQL_COLOR(clrDarkSalmon, 0x7A96E9) MQL_COLOR(clrBurlyWood, 0x87B8DE) MQL_COLOR(clrHotPink, 0xB469FF) MQL_COLOR(clrSalmon, 0x7280FA)
MQL_COLOR(clrViolet, 0xEE82EE) MQL_COLOR(clrLightCoral, 0x8080F0) MQL_COLOR(clrSkyBlue, 0xEBCE87) MQL_COLOR(clrLightSalmon, 0x7AA0FF)
MQL_COLOR(clrPlum, 0xDDA0DD) MQL_COLOR(clrKhaki, 0x8CE6F0) MQL_COLOR(clrLightGreen, 0x90EE90) MQL_COLOR(clrAquamarine, 0xD4FF7F)
MQL_COLOR(clrSilver, 0xC0C0C0) MQL_COLOR(clrLightSkyBlue, 0xFACE87) MQL_COLOR(clrLightSteelBlue, 0xDEC4B0) MQL_COLOR(clrLightBlue, 0xE6D8AD)
MQL_COLOR(clrPaleGreen, 0x98FB98) MQL_COLOR(clrThistle, 0xD8BFD8) MQL_COLOR(clrPowderBlue, 0xE6E0B0) MQL_COLOR(clrPaleGoldenrod, 0xAAE8EE)
MQL_COLOR(clrPaleTurquoise, 0xEEEEAF) MQL_COLOR(clrLightGray, 0xD3D3D3) MQL_COLOR(clrWheat, 0xB3DEF5) MQL_COLOR(clrNavajoWhite, 0xADDEFF)
MQL_COLOR(clrMoccasin, 0xB5E4FF) MQL_COLOR(clrLightPink, 0xC1B6FF) MQL_COLOR(clrGainsboro, 0xDCDCDC) MQL_COLOR(clrPeachPuff, 0xB9DAFF)
MQL_COLOR(clrPink, 0xCBC0FF) MQL_COLOR(clrBisque, 0xC4E4FF) MQL_COLOR(clrLightGoldenrod, 0xD2FAFA) MQL_COLOR(clrBlanchedAlmond, 0xCDEBFF)
MQL_COLOR(clrLemonChiffon, 0xCDFAFF) MQL_COLOR(clrBeige, 0xDCF5F5) MQL_COLOR(clrAntiqueWhite, 0xD7EBFA) MQL_COLOR(clrPapayaWhip, 0xD5EFFF)
MQL_COLOR(clrCornsilk, 0xDCF8FF) MQL_COLOR(clrLightYellow, 0xE0FFFF) MQL_COLOR(clrLightCyan, 0xFFFFE0) MQL_COLOR(clrLinen, 0xE6F0FA)
MQL_COLOR(clrLavender, 0xFAE6E6) MQL_COLOR(clrMistyRose, 0xE1E4FF) MQL_COLOR(clrOldLace, 0xE6F5FD) MQL_COLOR(clrWhiteSmoke, 0xF5F5F5)
MQL_COLOR(clrSeashell, 0xEEF5FF) MQL_COLOR(clrIvory, 0xF0FFFF) MQL_COLOR(clrHoneydew, 0xF0FFF0) MQL_COLOR(clrFloralWhite, 0xF0FAFF)
MQL_COLOR(clrAzure, 0xFFFFF0) MQL_COLOR(clrMintCream, 0xFAFFF5) MQL_COLOR(clrSnow, 0xFAFAFF) MQL_COLOR(clrWhite, 0xFFFFFF)
MQL_COLOR(clrLavenderBlush, 0xF5F0FF) MQL_COLOR(clrAliceBlue, 0xFFF8F0) MQL_COLOR(clrGhostWhite, 0xFFF8F8)
// aliases that MQL5 also knows
MQL_COLOR(clrCyan, 0xFFFF00) MQL_COLOR(clrFuchsia, 0xFF00FF) MQL_COLOR(clrDarkCyan, 0x8B8B00) MQL_COLOR(clrDarkMagenta, 0x8B008B)
MQL_COLOR(clrDarkRed, 0x00008B) MQL_COLOR(clrDarkGrey, 0xA9A9A9) MQL_COLOR(clrGrey, 0x808080) MQL_COLOR(clrLightGrey, 0xD3D3D3)
MQL_COLOR(clrDimGrey, 0x696969) MQL_COLOR(clrDarkSlateGrey, 0x4F4F2F) MQL_COLOR(clrSlateGrey, 0x908070) MQL_COLOR(clrLightSlateGrey, 0x998877)
#undef MQL_COLOR

//==================================================================== structures (real MQL5 field names)
struct MqlDateTime
  {
   int year, mon, day, hour, min, sec, day_of_week, day_of_year;
  };
struct MqlRates
  {
   datetime time;
   double   open, high, low, close;
   long     tick_volume;
   int      spread;
   long     real_volume;
  };
struct MqlTick
  {
   datetime time;
   double   bid, ask, last;
   ulong    volume;
   long     time_msc;
   uint     flags;
   double   volume_real;
  };
struct MqlBookInfo
  {
   ENUM_BOOK_TYPE type;
   double         price;
   long           volume;
   double         volume_real;
  };
struct MqlParam
  {
   ENUM_DATATYPE type;
   long          integer_value;
   double        double_value;
   string        string_value;
  };
struct MqlTradeRequest
  {
   ENUM_TRADE_REQUEST_ACTIONS action;
   ulong                      magic;
   ulong                      order;
   string                     symbol;
   double                     volume;
   double                     price;
   double                     stoplimit;
   double                     sl;
   double                     tp;
   ulong                      deviation;
   ENUM_ORDER_TYPE            type;
   ENUM_ORDER_TYPE_FILLING    type_filling;
   ENUM_ORDER_TYPE_TIME       type_time;
   datetime                   expiration;
   string                     comment;
   ulong                      position;
   ulong                      position_by;
  };
struct MqlTradeResult
  {
   uint   retcode;
   ulong  deal;
   ulong  order;
   double volume;
   double price;
   double bid;
   double ask;
   string comment;
   uint   request_id;
   int    retcode_external;
  };
struct MqlTradeCheckResult
  {
   uint   retcode;
   double balance;
   double equity;
   double profit;
   double margin;
   double margin_free;
   double margin_level;
   string comment;
  };
struct MqlTradeTransaction
  {
   ulong                         deal;
   ulong                         order;
   string                        symbol;
   ENUM_TRADE_TRANSACTION_TYPE   type;
   ENUM_ORDER_TYPE               order_type;
   ENUM_ORDER_STATE              order_state;
   ENUM_DEAL_TYPE                deal_type;
   ENUM_ORDER_TYPE_TIME          time_type;
   datetime                      time_expiration;
   double                        price;
   double                        price_trigger;
   double                        price_sl;
   double                        price_tp;
   double                        volume;
   ulong                         position;
   ulong                         position_by;
  };
struct MqlCalendarCountry
  {
   ulong  id;
   string name;
   string code;
   string currency;
   string currency_symbol;
   string url_name;
  };
struct MqlCalendarEvent
  {
   ulong  id;
   int    type;
   int    sector;
   int    frequency;
   int    time_mode;
   ulong  country_id;
   int    unit;
   int    importance;
   int    multiplier;
   uint   digits;
   string source_url;
   string event_code;
   string name;
  };
struct MqlCalendarValue
  {
   ulong    id;
   ulong    event_id;
   datetime time;
   datetime period;
   int      revision;
   long     actual_value;
   long     prev_value;
   long     revised_prev_value;
   long     forecast_value;
   int      impact_type;
   bool   HasActualValue() const { return true; }
   bool   HasPreviousValue() const { return true; }
   bool   HasRevisedValue() const { return true; }
   bool   HasForecastValue() const { return true; }
   double GetActualValue() const { return 0; }
   double GetPreviousValue() const { return 0; }
   double GetRevisedValue() const { return 0; }
   double GetForecastValue() const { return 0; }
  };

//==================================================================== predefined variables
inline string          _Symbol       = "EURUSD";
inline ENUM_TIMEFRAMES _Period       = PERIOD_H1;
inline int             _Digits       = 5;
inline double          _Point        = 0.00001;
inline int             _LastError    = 0;
inline bool            _StopFlag     = false;
inline int             _RandomSeed   = 0;
inline int             _UninitReason = 0;
inline bool            _IsX64        = true;
inline int             _AppliedTo    = 0;

inline string          Symbol()           { return _Symbol; }
inline ENUM_TIMEFRAMES Period()           { return _Period; }
inline int             Digits()           { return _Digits; }
inline double          Point()            { return _Point; }
inline bool            IsStopped()        { return _StopFlag; }
inline int             GetLastError()     { return _LastError; }
inline void            ResetLastError()   { _LastError = 0; }
inline void            SetUserError(ushort) {}
inline int             UninitializeReason() { return _UninitReason; }
inline void            ExpertRemove() {}
inline void            TerminalClose(int = 0) {}
inline void            DebugBreak() {}
inline void            Sleep(int) {}
inline uint            GetTickCount() { return 0; }
inline ulong           GetTickCount64() { return 0; }
inline ulong           GetMicrosecondCount() { return 0; }

//==================================================================== output / variadics
template<class... A> inline void   Print(const A &...) {}
template<class... A> inline void   PrintFormat(const string &, const A &...) {}
template<class... A> inline void   printf(const string &, const A &...) {}
template<class... A> inline void   Comment(const A &...) {}
template<class... A> inline void   Alert(const A &...) {}
template<class... A> inline string StringFormat(const string &fmt, const A &...) { return fmt; }
template<class... A> inline int    StringConcatenate(string &out, const A &...) { return out.Len(); }
inline bool   SendNotification(const string &) { return true; }
inline bool   SendMail(const string &, const string &) { return true; }
inline bool   SendFTP(const string &, const string & = NULL) { return true; }
inline bool   PlaySound(const string & = NULL) { return true; }
inline int    MessageBox(const string &, const string & = NULL, int = 0) { return 1; }
template<class T> inline void ZeroMemory(T &) {}
template<class T> inline T *GetPointer(T &o) { return &o; }
template<class T> inline T *GetPointer(T *p) { return p; }
template<class T> inline ENUM_POINTER_TYPE CheckPointer(T *p) { return p ? POINTER_DYNAMIC : POINTER_INVALID; }
template<class T> inline ENUM_POINTER_TYPE CheckPointer(const T &) { return POINTER_AUTOMATIC; }
template<class E, typename std::enable_if<std::is_enum<E>::value, int>::type = 0>
inline string EnumToString(E) { return "ENUM"; }

//==================================================================== events / timer
inline bool EventSetTimer(int) { return true; }
inline bool EventSetMillisecondTimer(int) { return true; }
inline void EventKillTimer() {}
inline bool EventChartCustom(long, ushort, long, double, const string &) { return true; }

//==================================================================== math
template<MQL_NUMBER(T)> inline T MathAbs(T v) { return v; }
template<MQL_NUMBER(A), MQL_NUMBER(B)> inline typename std::common_type<A, B>::type MathMax(A a, B b) { return a > b ? a : b; }
template<MQL_NUMBER(A), MQL_NUMBER(B)> inline typename std::common_type<A, B>::type MathMin(A a, B b) { return a < b ? a : b; }
inline double MathFloor(double v) { return v; }
inline double MathCeil(double v) { return v; }
inline double MathRound(double v) { return v; }
inline double MathPow(double v, double) { return v; }
inline double MathSqrt(double v) { return v; }
inline double MathLog(double v) { return v; }
inline double MathLog10(double v) { return v; }
inline double MathLog2(double v) { return v; }
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
inline double MathArcsinh(double v) { return v; }
inline double MathArccosh(double v) { return v; }
inline double MathArctanh(double v) { return v; }
inline int    MathRand() { return 0; }
inline void   MathSrand(int) {}
inline bool   MathIsValidNumber(double) { return true; }
inline int    MathClassify(double) { return 0; }
inline ushort MathSwap(ushort v) { return v; }
inline uint   MathSwap(uint v) { return v; }
inline ulong  MathSwap(ulong v) { return v; }
inline double NormalizeDouble(double v, int) { return v; }
// C-style aliases that MQL5 also accepts
template<MQL_NUMBER(T)> inline T fabs(T v) { return v; }
template<MQL_NUMBER(A), MQL_NUMBER(B)> inline typename std::common_type<A, B>::type fmax(A a, B b) { return a > b ? a : b; }
template<MQL_NUMBER(A), MQL_NUMBER(B)> inline typename std::common_type<A, B>::type fmin(A a, B b) { return a < b ? a : b; }
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
inline double atan2(double v, double) { return v; }
inline int    rand() { return 0; }
inline void   srand(int) {}

//==================================================================== strings
inline int      StringLen(const string &s) { return s.Len(); }
inline int      StringFind(const string &, const string &, int = 0) { return -1; }
inline string   StringSubstr(const string &s, int, int = -1) { return s; }
inline int      StringReplace(string &, const string &, const string &) { return 0; }
inline bool     StringToUpper(string &) { return true; }
inline bool     StringToLower(string &) { return true; }
inline int      StringTrimLeft(string &) { return 0; }
inline int      StringTrimRight(string &) { return 0; }
inline ushort   StringGetCharacter(const string &s, int i) { return s[i]; }
inline bool     StringSetCharacter(string &, int, ushort) { return true; }
inline int      StringCompare(const string &, const string &, bool = true) { return 0; }
inline double   StringToDouble(const string &) { return 0; }
inline long     StringToInteger(const string &) { return 0; }
inline datetime StringToTime(const string &) { return 0; }
inline color    StringToColor(const string &) { return 0; }
inline bool     StringAdd(string &, const string &) { return true; }
inline bool     StringInit(string &, int = 0, ushort = 0) { return true; }
inline int      StringBufferLen(const string &s) { return s.Len(); }
inline bool     StringFill(string &, ushort) { return true; }
inline bool     StringReserve(string &, uint) { return true; }
inline int      StringSplit(const string &, ushort, MqlArray<string> &) { return 0; }
template<unsigned long N> inline int StringSplit(const string &, ushort, string (&)[N]) { return 0; }
inline string   CharToString(uchar) { return ""; }
inline string   ShortToString(ushort) { return ""; }
template<MQL_ARR(A)> inline string CharArrayToString(const A &, int = 0, int = -1, uint = CP_ACP) { return ""; }
template<MQL_ARR(A)> inline string ShortArrayToString(const A &, int = 0, int = -1) { return ""; }
template<MQL_ARR(A)> inline int    StringToCharArray(const string &, A &, int = 0, int = -1, uint = CP_ACP) { return 0; }
template<MQL_ARR(A)> inline int    StringToShortArray(const string &, A &, int = 0, int = -1) { return 0; }
inline string   DoubleToString(double, int = 8) { return "0"; }
inline string   IntegerToString(long, int = 0, ushort = ' ') { return "0"; }
inline string   TimeToString(datetime, int = TIME_DATE | TIME_MINUTES) { return "1970.01.01 00:00"; }
inline string   ColorToString(color, bool = false) { return "clrNONE"; }
inline color    ColorToARGB(color, uchar = 255) { return 0; }

//==================================================================== date / time
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

//==================================================================== arrays
template<MQL_ARR(A)> inline int  ArraySize(const A &) { return 0; }
template<MQL_ARR(A)> inline int  ArrayResize(A &, int, int = 0) { return 0; }
template<MQL_ARR(A)> inline bool ArraySetAsSeries(const A &, bool) { return true; }
template<MQL_ARR(A)> inline bool ArrayGetAsSeries(const A &) { return false; }
template<MQL_ARR(A)> inline bool ArrayIsSeries(const A &) { return false; }
template<MQL_ARR(A)> inline bool ArrayIsDynamic(const A &) { return true; }
template<MQL_ARR(A), class V> inline int  ArrayInitialize(A &, V) { return 0; }
template<MQL_ARR(A), class V> inline void ArrayFill(A &, int, int, V) {}
template<MQL_ARR(A), MQL_ARR(B)> inline int  ArrayCopy(A &, const B &, int = 0, int = 0, int = WHOLE_ARRAY) { return 0; }
template<MQL_ARR(A), MQL_ARR(B)> inline int  ArrayCompare(const A &, const B &, int = 0, int = 0, int = WHOLE_ARRAY) { return 0; }
template<MQL_ARR(A)> inline int  ArrayMaximum(const A &, int = 0, int = WHOLE_ARRAY) { return 0; }
template<MQL_ARR(A)> inline int  ArrayMinimum(const A &, int = 0, int = WHOLE_ARRAY) { return 0; }
template<MQL_ARR(A)> inline bool ArraySort(A &, int = WHOLE_ARRAY, int = 0, int = 0) { return true; }
template<MQL_ARR(A), class V> inline int ArrayBsearch(const A &, V, int = WHOLE_ARRAY, int = 0, int = 0) { return 0; }
template<MQL_ARR(A)> inline void ArrayFree(A &) {}
template<MQL_ARR(A), MQL_ARR(B)> inline bool ArrayInsert(A &, const B &, uint, uint = 0, uint = WHOLE_ARRAY) { return true; }
template<MQL_ARR(A)> inline bool ArrayRemove(A &, uint, uint = WHOLE_ARRAY) { return true; }
template<MQL_ARR(A)> inline bool ArrayReverse(A &, uint = 0, uint = WHOLE_ARRAY) { return true; }
template<MQL_ARR(A)> inline void ArrayPrint(const A &, uint = 8, const string & = NULL, ulong = 0, ulong = WHOLE_ARRAY, ulong = ARRAYPRINT_HEADER | ARRAYPRINT_INDEX | ARRAYPRINT_LIMIT | ARRAYPRINT_ALIGN) {}
template<MQL_ARR(A)> inline int  ArrayRange(const A &, int) { return 0; }
template<MQL_ARR(A), MQL_ARR(B)> inline bool ArraySwap(A &, B &) { return true; }
template<MQL_ARR(A)> inline int  ArrayDimension(const A &) { return 1; }

//==================================================================== terminal global variables
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

//==================================================================== files
inline int    FileOpen(const string &, int, short = '\t', uint = CP_ACP) { return 0; }
inline void   FileClose(int) {}
inline bool   FileIsExist(const string &, int = 0) { return false; }
inline bool   FileDelete(const string &, int = 0) { return true; }
inline bool   FileMove(const string &, int, const string &, int) { return true; }
inline bool   FileCopy(const string &, int, const string &, int) { return true; }
inline bool   FileSeek(int, long, int) { return true; }
inline ulong  FileTell(int) { return 0; }
inline ulong  FileSize(int) { return 0; }
inline bool   FileIsEnding(int) { return true; }
inline bool   FileIsLineEnding(int) { return true; }
inline void   FileFlush(int) {}
template<class... A> inline uint FileWrite(int, const A &...) { return 0; }
inline uint   FileWriteString(int, const string &, int = -1) { return 0; }
inline uint   FileWriteDouble(int, double) { return 0; }
inline uint   FileWriteFloat(int, float) { return 0; }
inline uint   FileWriteInteger(int, int, int = INT_VALUE) { return 0; }
inline uint   FileWriteLong(int, long) { return 0; }
template<class S> inline uint FileWriteStruct(int, const S &, int = -1) { return 0; }
template<MQL_ARR(A)> inline uint FileWriteArray(int, const A &, int = 0, int = WHOLE_ARRAY) { return 0; }
inline string FileReadString(int, int = -1) { return ""; }
inline double FileReadNumber(int) { return 0; }
inline double FileReadDouble(int) { return 0; }
inline float  FileReadFloat(int) { return 0; }
inline int    FileReadInteger(int, int = INT_VALUE) { return 0; }
inline long   FileReadLong(int) { return 0; }
inline bool   FileReadBool(int) { return false; }
inline datetime FileReadDatetime(int) { return 0; }
template<class S> inline uint FileReadStruct(int, S &, int = -1) { return 0; }
template<MQL_ARR(A)> inline uint FileReadArray(int, A &, int = 0, int = WHOLE_ARRAY) { return 0; }
inline long   FileFindFirst(const string &, string &, int = 0) { return 0; }
inline bool   FileFindNext(long, string &) { return false; }
inline void   FileFindClose(long) {}
inline bool   FolderCreate(const string &, int = 0) { return true; }
inline bool   FolderDelete(const string &, int = 0) { return true; }
inline bool   FolderClean(const string &, int = 0) { return true; }
inline long   FileGetInteger(int, int) { return 0; }
inline long   FileGetInteger(const string &, int, bool = false) { return 0; }
inline int    FileSelectDialog(const string &, const string &, const string &, uint, MqlArray<string> &, const string &) { return 0; }
inline bool   FileLoad(const string &, MqlArray<uchar> &, int = 0) { return true; }
template<MQL_ARR(A)> inline long FileLoad(const string &, A &, int = 0) { return 0; }
template<MQL_ARR(A)> inline bool FileSave(const string &, const A &, int = 0) { return true; }

//==================================================================== timeseries access
inline int      Bars(const string &, int) { return 0; }
inline int      Bars(const string &, int, datetime, datetime) { return 0; }
inline int      iBars(const string &, int) { return 0; }
inline int      iBarShift(const string &, int, datetime, bool = false) { return 0; }
inline datetime iTime(const string &, int, int) { return 0; }
inline double   iOpen(const string &, int, int) { return 0; }
inline double   iHigh(const string &, int, int) { return 0; }
inline double   iLow(const string &, int, int) { return 0; }
inline double   iClose(const string &, int, int) { return 0; }
inline long     iVolume(const string &, int, int) { return 0; }
inline long     iTickVolume(const string &, int, int) { return 0; }
inline long     iRealVolume(const string &, int, int) { return 0; }
inline int      iSpread(const string &, int, int) { return 0; }
inline int      iHighest(const string &, int, int = MODE_HIGH, int = WHOLE_ARRAY, int = 0) { return 0; }
inline int      iLowest(const string &, int, int = MODE_LOW, int = WHOLE_ARRAY, int = 0) { return 0; }
inline long     SeriesInfoInteger(const string &, int, int) { return 0; }
inline bool     SeriesInfoInteger(const string &, int, int, long &) { return true; }
// Copy*(symbol, tf, start_pos|start_time, count|stop_time, array): the three
// MQL5 overloads all take two integral values, so one (long,long) signature
// covers (int,int), (datetime,int) and (datetime,datetime) without ambiguity.
template<MQL_ARR_OF(A, MqlRates)> inline int CopyRates(const string &, int, long, long, A &) { return 0; }
template<MQL_ARR_OF(A, datetime)> inline int CopyTime(const string &, int, long, long, A &) { return 0; }
template<MQL_ARR_OF(A, double)>   inline int CopyOpen(const string &, int, long, long, A &) { return 0; }
template<MQL_ARR_OF(A, double)>   inline int CopyHigh(const string &, int, long, long, A &) { return 0; }
template<MQL_ARR_OF(A, double)>   inline int CopyLow(const string &, int, long, long, A &) { return 0; }
template<MQL_ARR_OF(A, double)>   inline int CopyClose(const string &, int, long, long, A &) { return 0; }
template<MQL_ARR_OF(A, long)>     inline int CopyTickVolume(const string &, int, long, long, A &) { return 0; }
template<MQL_ARR_OF(A, long)>     inline int CopyRealVolume(const string &, int, long, long, A &) { return 0; }
template<MQL_ARR_OF(A, int)>      inline int CopySpread(const string &, int, long, long, A &) { return 0; }
template<MQL_ARR_OF(A, MqlTick)>  inline int CopyTicks(const string &, A &, uint = COPY_TICKS_ALL, ulong = 0, uint = 0) { return 0; }
template<MQL_ARR_OF(A, MqlTick)>  inline int CopyTicksRange(const string &, A &, uint = COPY_TICKS_ALL, ulong = 0, ulong = 0) { return 0; }

//==================================================================== symbols / market
inline bool   SymbolInfoTick(const string &, MqlTick &) { return true; }
inline double SymbolInfoDouble(const string &, int) { return 0; }
inline bool   SymbolInfoDouble(const string &, int, double &) { return true; }
inline long   SymbolInfoInteger(const string &, int) { return 0; }
inline bool   SymbolInfoInteger(const string &, int, long &) { return true; }
inline string SymbolInfoString(const string &, int) { return ""; }
inline bool   SymbolInfoString(const string &, int, string &) { return true; }
inline bool   SymbolInfoMarginRate(const string &, int, double &, double &) { return true; }
inline bool   SymbolInfoSessionQuote(const string &, int, uint, datetime &, datetime &) { return true; }
inline bool   SymbolInfoSessionTrade(const string &, int, uint, datetime &, datetime &) { return true; }
inline bool   SymbolSelect(const string &, bool) { return true; }
inline bool   SymbolExist(const string &, bool &) { return true; }
inline int    SymbolsTotal(bool) { return 0; }
inline string SymbolName(int, bool) { return ""; }
inline bool   SymbolIsSynchronized(const string &) { return true; }
inline bool   MarketBookAdd(const string &) { return true; }
inline bool   MarketBookRelease(const string &) { return true; }
template<MQL_ARR_OF(A, MqlBookInfo)> inline bool MarketBookGet(const string &, A &) { return true; }

//==================================================================== indicators
template<class... P> inline int iCustom(const string &, int, const string &, const P &...) { return 0; }
inline int iAC(const string &, int) { return 0; }
inline int iAD(const string &, int, int) { return 0; }
inline int iADX(const string &, int, int) { return 0; }
inline int iADXWilder(const string &, int, int) { return 0; }
inline int iAlligator(const string &, int, int, int, int, int, int, int, int, int) { return 0; }
inline int iAMA(const string &, int, int, int, int, int, int) { return 0; }
inline int iAO(const string &, int) { return 0; }
inline int iATR(const string &, int, int) { return 0; }
inline int iBearsPower(const string &, int, int) { return 0; }
inline int iBands(const string &, int, int, int, double, int) { return 0; }
inline int iBullsPower(const string &, int, int) { return 0; }
inline int iCCI(const string &, int, int, int) { return 0; }
inline int iChaikin(const string &, int, int, int, int, int) { return 0; }
inline int iDEMA(const string &, int, int, int, int) { return 0; }
inline int iDeMarker(const string &, int, int) { return 0; }
inline int iEnvelopes(const string &, int, int, int, int, int, double) { return 0; }
inline int iForce(const string &, int, int, int, int) { return 0; }
inline int iFractals(const string &, int) { return 0; }
inline int iFrAMA(const string &, int, int, int, int) { return 0; }
inline int iGator(const string &, int, int, int, int, int, int, int, int, int) { return 0; }
inline int iIchimoku(const string &, int, int, int, int) { return 0; }
inline int iBWMFI(const string &, int, int) { return 0; }
inline int iMomentum(const string &, int, int, int) { return 0; }
inline int iMFI(const string &, int, int, int) { return 0; }
inline int iMA(const string &, int, int, int, int, int) { return 0; }
inline int iOsMA(const string &, int, int, int, int, int) { return 0; }
inline int iMACD(const string &, int, int, int, int, int) { return 0; }
inline int iOBV(const string &, int, int) { return 0; }
inline int iSAR(const string &, int, double, double) { return 0; }
inline int iRSI(const string &, int, int, int) { return 0; }
inline int iRVI(const string &, int, int) { return 0; }
inline int iStdDev(const string &, int, int, int, int, int) { return 0; }
inline int iStochastic(const string &, int, int, int, int, int, int) { return 0; }
inline int iTEMA(const string &, int, int, int, int) { return 0; }
inline int iTriX(const string &, int, int, int) { return 0; }
inline int iWPR(const string &, int, int) { return 0; }
inline int iVIDyA(const string &, int, int, int, int, int) { return 0; }
inline int iVolumes(const string &, int, int) { return 0; }
inline int  IndicatorCreate(const string &, int, int) { return 0; }
template<MQL_ARR_OF(A, MqlParam)> inline int IndicatorCreate(const string &, int, int, int, const A &) { return 0; }
template<class T, MQL_ARR_OF(A, MqlParam)> inline int IndicatorParameters(int, T &, A &) { return 0; }
inline bool IndicatorRelease(int) { return true; }
inline int  BarsCalculated(int) { return 0; }
template<MQL_ARR_OF(A, double)> inline int CopyBuffer(int, int, long, long, A &) { return 0; }
// custom-indicator side
template<MQL_ARR(A)> inline bool SetIndexBuffer(int, A &, int = INDICATOR_DATA) { return true; }
inline bool IndicatorSetDouble(int, double) { return true; }
inline bool IndicatorSetDouble(int, int, double) { return true; }
inline bool IndicatorSetInteger(int, long) { return true; }
inline bool IndicatorSetInteger(int, int, long) { return true; }
inline bool IndicatorSetString(int, const string &) { return true; }
inline bool IndicatorSetString(int, int, const string &) { return true; }
inline bool PlotIndexSetDouble(int, int, double) { return true; }
inline bool PlotIndexSetInteger(int, int, long) { return true; }
inline bool PlotIndexSetInteger(int, int, int, long) { return true; }
inline bool PlotIndexSetString(int, int, const string &) { return true; }
inline long PlotIndexGetInteger(int, int, int = 0) { return 0; }

//==================================================================== chart objects
inline int    ObjectsTotal(long, int = -1, int = -1) { return 0; }
inline string ObjectName(long, int, int = -1, int = -1) { return ""; }
inline int    ObjectFind(long, const string &) { return -1; }
inline bool   ObjectCreate(long, const string &, int, int, datetime, double) { return true; }
template<class... A> inline bool ObjectCreate(long, const string &, int, int, datetime, double, datetime, double, const A &...) { return true; }
inline bool   ObjectDelete(long, const string &) { return true; }
inline int    ObjectsDeleteAll(long, int = -1, int = -1) { return 0; }
inline int    ObjectsDeleteAll(long, const string &, int = -1, int = -1) { return 0; }
inline bool   ObjectMove(long, const string &, int, datetime, double) { return true; }
inline long   ObjectGetInteger(long, const string &, int, int = 0) { return 0; }
inline bool   ObjectGetInteger(long, const string &, int, int, long &) { return true; }
inline double ObjectGetDouble(long, const string &, int, int = 0) { return 0; }
inline bool   ObjectGetDouble(long, const string &, int, int, double &) { return true; }
inline string ObjectGetString(long, const string &, int, int = 0) { return ""; }
inline bool   ObjectGetString(long, const string &, int, int, string &) { return true; }
inline bool   ObjectSetInteger(long, const string &, int, long) { return true; }
inline bool   ObjectSetInteger(long, const string &, int, int, long) { return true; }
inline bool   ObjectSetDouble(long, const string &, int, double) { return true; }
inline bool   ObjectSetDouble(long, const string &, int, int, double) { return true; }
inline bool   ObjectSetString(long, const string &, int, const string &) { return true; }
inline bool   ObjectSetString(long, const string &, int, int, const string &) { return true; }
inline double   ObjectGetValueByTime(long, const string &, datetime, int = 0) { return 0; }
inline datetime ObjectGetTimeByValue(long, const string &, double, int = 0) { return 0; }
inline double   ObjectGetValueByShift(const string &, int) { return 0; }       // MQL4 legacy (asked for)
inline int      ObjectGetShiftByValue(const string &, double) { return 0; }    // MQL4 legacy (asked for)
inline bool   TextSetFont(const string &, int, uint = 0, int = 0) { return true; }
template<MQL_ARR_OF(A, uint)> inline bool TextOut(const string &, int, int, uint, A &, uint, uint, uint, int = COLOR_FORMAT_XRGB_NOALPHA) { return true; }
inline bool   TextGetSize(const string &, uint &, uint &) { return true; }
template<MQL_ARR_OF(A, uint)> inline bool ResourceCreate(const string &, const A &, uint, uint, uint, uint, uint, int) { return true; }
inline bool   ResourceCreate(const string &, const string &) { return true; }
inline bool   ResourceFree(const string &) { return true; }
template<MQL_ARR_OF(A, uint)> inline bool ResourceReadImage(const string &, A &, uint &, uint &) { return true; }
inline bool   ResourceSave(const string &, const string &) { return true; }

//==================================================================== chart
inline long     ChartID() { return 0; }
inline long     ChartGetInteger(long, int, int = 0) { return 0; }
inline bool     ChartGetInteger(long, int, int, long &) { return true; }
inline double   ChartGetDouble(long, int, int = 0) { return 0; }
inline bool     ChartGetDouble(long, int, int, double &) { return true; }
inline string   ChartGetString(long, int) { return ""; }
inline bool     ChartGetString(long, int, string &) { return true; }
inline bool     ChartSetInteger(long, int, long) { return true; }
inline bool     ChartSetInteger(long, int, int, long) { return true; }
inline bool     ChartSetDouble(long, int, double) { return true; }
inline bool     ChartSetString(long, int, const string &) { return true; }
inline void     ChartRedraw(long = 0) {}
inline int      ChartWindowFind() { return 0; }
inline int      ChartWindowFind(long, const string &) { return 0; }
inline ENUM_TIMEFRAMES ChartPeriod(long = 0) { return PERIOD_CURRENT; }
inline string   ChartSymbol(long = 0) { return ""; }
inline double   ChartPriceOnDropped() { return 0; }
inline datetime ChartTimeOnDropped() { return 0; }
inline int      ChartWindowOnDropped() { return 0; }
inline int      ChartXOnDropped() { return 0; }
inline int      ChartYOnDropped() { return 0; }
inline long     ChartOpen(const string &, int) { return 0; }
inline bool     ChartClose(long = 0) { return true; }
inline long     ChartFirst() { return 0; }
inline long     ChartNext(long) { return -1; }
inline bool     ChartSetSymbolPeriod(long, const string &, int) { return true; }
inline bool     ChartNavigate(long, int, int = 0) { return true; }
inline bool     ChartApplyTemplate(long, const string &) { return true; }
inline bool     ChartSaveTemplate(long, const string &) { return true; }
inline bool     ChartScreenShot(long, const string &, int, int, int = -1) { return true; }
inline bool     ChartIndicatorAdd(long, int, int) { return true; }
inline bool     ChartIndicatorDelete(long, int, const string &) { return true; }
inline int      ChartIndicatorGet(long, int, const string &) { return 0; }
inline string   ChartIndicatorName(long, int, int) { return ""; }
inline int      ChartIndicatorsTotal(long, int) { return 0; }
inline bool     ChartTimePriceToXY(long, int, datetime, double, int &, int &) { return true; }
inline bool     ChartXYToTimePrice(long, int, int, int &, datetime &, double &) { return true; }

//==================================================================== trading
inline bool   OrderSend(const MqlTradeRequest &, MqlTradeResult &) { return true; }
inline bool   OrderSendAsync(const MqlTradeRequest &, MqlTradeResult &) { return true; }
inline bool   OrderCheck(const MqlTradeRequest &, MqlTradeCheckResult &) { return true; }
inline bool   OrderCalcMargin(int, const string &, double, double, double &) { return true; }
inline bool   OrderCalcProfit(int, const string &, double, double, double, double &) { return true; }
inline int    PositionsTotal() { return 0; }
inline ulong  PositionGetTicket(int) { return 0; }
inline string PositionGetSymbol(int) { return ""; }
inline bool   PositionSelect(const string &) { return true; }
inline bool   PositionSelectByTicket(ulong) { return true; }
inline long   PositionGetInteger(int) { return 0; }
inline bool   PositionGetInteger(int, long &) { return true; }
inline double PositionGetDouble(int) { return 0; }
inline bool   PositionGetDouble(int, double &) { return true; }
inline string PositionGetString(int) { return ""; }
inline bool   PositionGetString(int, string &) { return true; }
inline int    OrdersTotal() { return 0; }
inline ulong  OrderGetTicket(int) { return 0; }
inline bool   OrderSelect(ulong) { return true; }
inline long   OrderGetInteger(int) { return 0; }
inline bool   OrderGetInteger(int, long &) { return true; }
inline double OrderGetDouble(int) { return 0; }
inline bool   OrderGetDouble(int, double &) { return true; }
inline string OrderGetString(int) { return ""; }
inline bool   OrderGetString(int, string &) { return true; }
inline bool   HistorySelect(datetime, datetime) { return true; }
inline bool   HistorySelectByPosition(long) { return true; }
inline bool   HistoryOrderSelect(ulong) { return true; }
inline int    HistoryOrdersTotal() { return 0; }
inline ulong  HistoryOrderGetTicket(int) { return 0; }
inline long   HistoryOrderGetInteger(ulong, int) { return 0; }
inline bool   HistoryOrderGetInteger(ulong, int, long &) { return true; }
inline double HistoryOrderGetDouble(ulong, int) { return 0; }
inline bool   HistoryOrderGetDouble(ulong, int, double &) { return true; }
inline string HistoryOrderGetString(ulong, int) { return ""; }
inline bool   HistoryOrderGetString(ulong, int, string &) { return true; }
inline bool   HistoryDealSelect(ulong) { return true; }
inline int    HistoryDealsTotal() { return 0; }
inline ulong  HistoryDealGetTicket(int) { return 0; }
inline long   HistoryDealGetInteger(ulong, int) { return 0; }
inline bool   HistoryDealGetInteger(ulong, int, long &) { return true; }
inline double HistoryDealGetDouble(ulong, int) { return 0; }
inline bool   HistoryDealGetDouble(ulong, int, double &) { return true; }
inline string HistoryDealGetString(ulong, int) { return ""; }
inline bool   HistoryDealGetString(ulong, int, string &) { return true; }

//==================================================================== account / terminal / tester
inline double AccountInfoDouble(int) { return 0; }
inline long   AccountInfoInteger(int) { return 0; }
inline string AccountInfoString(int) { return ""; }
inline int    TerminalInfoInteger(int) { return 0; }
inline double TerminalInfoDouble(int) { return 0; }
inline string TerminalInfoString(int) { return ""; }
inline int    MQLInfoInteger(int) { return 0; }
inline string MQLInfoString(int) { return ""; }
inline bool   MQLInfoIntegerSet(int, int) { return true; }
inline bool   TerminalInfoIntegerSet(int, int) { return true; }
inline void   TesterStop() {}
inline void   TesterHideIndicators(bool) {}
inline bool   TesterDeposit(double) { return true; }
inline bool   TesterWithdrawal(double) { return true; }
inline double TesterStatistics(int) { return 0; }
inline bool   FrameAdd(const string &, long, double, const string &) { return true; }
template<MQL_ARR(A)> inline bool FrameAdd(const string &, long, double, const A &) { return true; }
inline bool   FrameNext(ulong &, string &, long &, double &) { return false; }
template<MQL_ARR(A)> inline bool FrameNext(ulong &, string &, long &, double &, A &) { return false; }
inline bool   FrameFirst() { return true; }
inline bool   FrameFilter(const string &, long) { return true; }
inline bool   FrameInputs(ulong, MqlArray<string> &, uint &) { return true; }
inline bool   ParameterGetRange(const string &, bool &, long &, long &, long &, long &) { return true; }
inline bool   ParameterGetRange(const string &, bool &, double &, double &, double &, double &) { return true; }
inline bool   ParameterSetRange(const string &, bool, long, long, long, long) { return true; }
inline bool   ParameterSetRange(const string &, bool, double, double, double, double) { return true; }

//==================================================================== calendar (minimal)
template<MQL_ARR_OF(A, MqlCalendarValue)> inline int CalendarValueHistory(A &, datetime, datetime = 0, const string & = NULL, const string & = NULL) { return 0; }
template<MQL_ARR_OF(A, MqlCalendarValue)> inline int CalendarValueHistoryByEvent(ulong, A &, datetime, datetime = 0) { return 0; }
template<MQL_ARR_OF(A, MqlCalendarValue)> inline int CalendarValueLast(ulong &, A &, const string & = NULL, const string & = NULL) { return 0; }
template<MQL_ARR_OF(A, MqlCalendarValue)> inline int CalendarValueLastByEvent(ulong, ulong &, A &) { return 0; }
template<MQL_ARR_OF(A, MqlCalendarEvent)> inline int CalendarEventByCountry(const string &, A &) { return 0; }
template<MQL_ARR_OF(A, MqlCalendarEvent)> inline int CalendarEventByCurrency(const string &, A &) { return 0; }
template<MQL_ARR_OF(A, MqlCalendarCountry)> inline int CalendarCountries(A &) { return 0; }
inline bool CalendarCountryById(ulong, MqlCalendarCountry &) { return true; }
inline bool CalendarEventById(ulong, MqlCalendarEvent &) { return true; }
inline bool CalendarValueById(ulong, MqlCalendarValue &) { return true; }

//==================================================================== network / crypt (minimal)
inline int  WebRequest(const string &, const string &, const string &, int, const MqlArray<char> &, MqlArray<char> &, string &) { return 0; }
inline int  WebRequest(const string &, const string &, const string &, const string &, int, const MqlArray<char> &, int, MqlArray<char> &, string &) { return 0; }
inline int  SocketCreate(uint = 0) { return 0; }
inline bool SocketClose(int) { return true; }
inline bool SocketConnect(int, const string &, uint, uint) { return true; }
inline bool SocketIsConnected(int) { return true; }
inline uint SocketIsReadable(int) { return 0; }
inline bool SocketIsWritable(int) { return true; }
inline bool SocketTimeouts(int, uint, uint) { return true; }
template<MQL_ARR(A)> inline int SocketRead(int, A &, uint, uint) { return 0; }
template<MQL_ARR(A)> inline int SocketSend(int, const A &, uint) { return 0; }
inline bool SocketTlsHandshake(int, const string &) { return true; }
template<MQL_ARR(A)> inline int SocketTlsRead(int, A &, uint) { return 0; }
template<MQL_ARR(A)> inline int SocketTlsReadAvailable(int, A &, uint) { return 0; }
template<MQL_ARR(A)> inline int SocketTlsSend(int, const A &, uint) { return 0; }
template<MQL_ARR(A), MQL_ARR(B), MQL_ARR(C)> inline int CryptEncode(int, const A &, const B &, C &) { return 0; }
template<MQL_ARR(A), MQL_ARR(B), MQL_ARR(C)> inline int CryptDecode(int, const A &, const B &, C &) { return 0; }
