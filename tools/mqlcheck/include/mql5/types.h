// mqlcheck: MQL5 core types faked for g++ -fsyntax-only.
// Deliberately avoids <string>/<cmath>/<cstdio> so no POSIX/libc global names
// (open, close, y0, y1, time, index, ...) collide with user identifiers.
#pragma once
#include <initializer_list>
#include <type_traits>

#ifndef NULL
#define NULL __null
#endif
#define __MQL5__ 1
#define __MQLBUILD__ 4000
#define __MQL5BUILD__ 4000
#ifndef __FUNCSIG__
#define __FUNCSIG__ __PRETTY_FUNCTION__
#endif
#define __DATETIME__ __DATE__
#define __PATH__ __FILE__

typedef unsigned char      uchar;
typedef unsigned short     ushort;
typedef unsigned int       uint;
typedef unsigned long      ulong;     // 64-bit on x86-64 Linux, like MQL5 ulong
typedef long               datetime;  // 64-bit, like MQL5 datetime
typedef unsigned int       color;

//---------------------------------------------------------------- string
class string
  {
   char *p_;
   int   n_;
   static int slen(const char *s) { int n = 0; if(s) while(s[n]) n++; return n; }
   void  assign(const char *s, int n)
     {
      char *q = new char[n + 1];
      for(int i = 0; i < n; i++) q[i] = s[i];
      q[n] = 0;
      delete[] p_; p_ = q; n_ = n;
     }
public:
   string() : p_(nullptr), n_(0) { assign("", 0); }
   string(const char *s) : p_(nullptr), n_(0) { assign(s ? s : "", slen(s)); }   // implicit on purpose
   string(const string &o) : p_(nullptr), n_(0) { assign(o.p_, o.n_); }
   string(string &&o) noexcept : p_(o.p_), n_(o.n_) { o.p_ = nullptr; o.n_ = 0; }
   ~string() { delete[] p_; }
   string &operator=(const string &o) { if(this != &o) assign(o.p_, o.n_); return *this; }
   string &operator=(string &&o) noexcept { if(this != &o) { delete[] p_; p_ = o.p_; n_ = o.n_; o.p_ = nullptr; o.n_ = 0; } return *this; }
   string &operator=(const char *s) { assign(s ? s : "", slen(s)); return *this; }

   const char *c_str() const { return p_ ? p_ : ""; }
   int         Len()   const { return n_; }
   ushort      operator[](int i) const { return (i >= 0 && i < n_) ? (ushort)(uchar)p_[i] : 0; }

   string &operator+=(const string &o) { return append(o.c_str(), o.n_); }
   string &operator+=(const char *s)   { return append(s ? s : "", slen(s)); }
   string &append(const char *s, int n)
     {
      char *q = new char[n_ + n + 1];
      for(int i = 0; i < n_; i++) q[i] = p_[i];
      for(int i = 0; i < n; i++) q[n_ + i] = s[i];
      q[n_ + n] = 0;
      delete[] p_; p_ = q; n_ += n;
      return *this;
     }
   static int cmp(const char *a, const char *b)
     {
      while(*a && *a == *b) { a++; b++; }
      return (int)(uchar)*a - (int)(uchar)*b;
     }
   friend string operator+(const string &a, const string &b) { string r(a); r += b; return r; }
   friend string operator+(const string &a, const char *b)   { string r(a); r += b; return r; }
   friend string operator+(const char *a, const string &b)   { string r(a); r += b; return r; }

   friend bool operator==(const string &a, const string &b) { return cmp(a.c_str(), b.c_str()) == 0; }
   friend bool operator==(const string &a, const char *b)   { return cmp(a.c_str(), b ? b : "") == 0; }
   friend bool operator==(const char *a, const string &b)   { return cmp(a ? a : "", b.c_str()) == 0; }
   friend bool operator!=(const string &a, const string &b) { return !(a == b); }
   friend bool operator!=(const string &a, const char *b)   { return !(a == b); }
   friend bool operator!=(const char *a, const string &b)   { return !(a == b); }
   friend bool operator< (const string &a, const string &b) { return cmp(a.c_str(), b.c_str()) <  0; }
   friend bool operator> (const string &a, const string &b) { return cmp(a.c_str(), b.c_str()) >  0; }
   friend bool operator<=(const string &a, const string &b) { return cmp(a.c_str(), b.c_str()) <= 0; }
   friend bool operator>=(const string &a, const string &b) { return cmp(a.c_str(), b.c_str()) >= 0; }
  };

// MQL5 compiles "str + 5" with the warning "implicit conversion from 'number'
// to 'string'". Mirror that: allowed, but flagged as deprecated.
template<class T, typename std::enable_if<std::is_arithmetic<T>::value || std::is_enum<T>::value, int>::type = 0>
[[deprecated("MQL5: implicit conversion from 'number' to 'string' - use (string) cast")]]
inline string operator+(const string &a, T) { return a; }
template<class T, typename std::enable_if<std::is_arithmetic<T>::value || std::is_enum<T>::value, int>::type = 0>
[[deprecated("MQL5: implicit conversion from 'number' to 'string' - use (string) cast")]]
inline string operator+(T, const string &b) { return b; }
template<class T, typename std::enable_if<std::is_arithmetic<T>::value || std::is_enum<T>::value, int>::type = 0>
[[deprecated("MQL5: implicit conversion from 'number' to 'string' - use (string) cast")]]
inline string &operator+=(string &a, T) { return a; }

//---------------------------------------------------------------- (string) cast
// The pre-processor rewrites "(string)x" to "(MqlStrCast)x".
struct MqlStrCast : public string
  {
   MqlStrCast(const string &s) : string(s) {}
   MqlStrCast(const char *s) : string(s) {}
   template<class T, typename std::enable_if<std::is_arithmetic<T>::value || std::is_enum<T>::value, int>::type = 0>
   MqlStrCast(T) : string("0") {}
  };

//---------------------------------------------------------------- arrays
template<class T> class MqlArray
  {
   T   *d_;
   int  n_;
   mutable bool series_;
public:
   typedef T value_type;
   MqlArray() : d_(nullptr), n_(0), series_(false) {}
   MqlArray(std::initializer_list<T> il) : d_(nullptr), n_(0), series_(false)
     {
      Resize((int)il.size());
      int i = 0;
      for(const T &v : il) d_[i++] = v;
     }
   MqlArray(const MqlArray &o) : d_(nullptr), n_(0), series_(o.series_)
     {
      Resize(o.n_);
      for(int i = 0; i < n_; i++) d_[i] = o.d_[i];
     }
   ~MqlArray() { delete[] d_; }
   MqlArray &operator=(const MqlArray &o)
     {
      if(this != &o) { Resize(o.n_); for(int i = 0; i < n_; i++) d_[i] = o.d_[i]; }
      return *this;
     }
   T       &operator[](long i)       { return d_[i]; }
   const T &operator[](long i) const { return d_[i]; }
   int   Size() const { return n_; }
   void  Resize(int n)
     {
      if(n < 0) n = 0;
      T *q = n ? new T[n] : nullptr;
      int keep = n < n_ ? n : n_;
      for(int i = 0; i < keep; i++) q[i] = d_[i];
      delete[] d_; d_ = q; n_ = n;
     }
   void  Free() { Resize(0); }
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
   ~MqlArray2() { delete[] d_; }
   Row       &operator[](long i)       { return d_[i]; }
   const Row &operator[](long i) const { return d_[i]; }
   int  Size() const { return n_ * (int)N; }
   int  Rows() const { return n_; }
   void Resize(int n)
     {
      if(n < 0) n = 0;
      Row *q = n ? new Row[n] : nullptr;
      int keep = n < n_ ? n : n_;
      for(int i = 0; i < keep; i++) for(unsigned long j = 0; j < N; j++) q[i][j] = d_[i][j];
      delete[] d_; d_ = q; n_ = n;
     }
   void Free() { Resize(0); }
   void SetAsSeries(bool s) const { series_ = s; }
   bool IsSeries() const { return series_; }
  };

template<class A> struct MqlIsArray : std::false_type {};
template<class T> struct MqlIsArray<MqlArray<T>> : std::true_type {};
template<class T, unsigned long N> struct MqlIsArray<MqlArray2<T, N>> : std::true_type {};
template<class T, unsigned long N> struct MqlIsArray<T[N]> : std::true_type {};
template<class T, unsigned long N, unsigned long M> struct MqlIsArray<T[N][M]> : std::true_type {};
template<class T, unsigned long N, unsigned long M, unsigned long K> struct MqlIsArray<T[N][M][K]> : std::true_type {};
#define MQL_ARR(A) class A, typename std::enable_if<MqlIsArray<A>::value, int>::type = 0

//---------------------------------------------------------------- structs
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
   int    type;      // ENUM_BOOK_TYPE
   double price;
   long   volume;
   double volume_real;
  };

struct MqlParam
  {
   int    type;      // ENUM_DATATYPE
   long   integer_value;
   double double_value;
   string string_value;
  };
