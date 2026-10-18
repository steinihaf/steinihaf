// mqlcheck stand-in for <Object.mqh>
#pragma once
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
   virtual bool Save(int) { return true; }
   virtual bool Load(int) { return true; }
   virtual int  Type() const { return 0; }
   virtual int  Compare(const CObject *, const int = 0) const { return 0; }
  };
