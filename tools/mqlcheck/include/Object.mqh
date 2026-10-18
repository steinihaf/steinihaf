// mqlcheck stand-in for <Object.mqh> (CObject, base of the Standard Library)
#pragma once
#pragma GCC system_header
class CObject
  {
   CObject *m_prev;
   CObject *m_next;
public:
   CObject() : m_prev(nullptr), m_next(nullptr) {}
   virtual ~CObject() {}
   CObject *Prev() const { return m_prev; }
   void     Prev(CObject *o) { m_prev = o; }
   CObject *Next() const { return m_next; }
   void     Next(CObject *o) { m_next = o; }
   virtual bool Save(const int) { return true; }
   virtual bool Load(const int) { return true; }
   virtual int  Type() const { return 0; }
   virtual int  Compare(const CObject *, const int = 0) const { return 0; }
  };
