/*++
Copyright (c) 2019 Microsoft Corporation

Module Name:

    dd_pdd.cpp

Abstract:

    Poly DD package 

Author:

    Nikolaj Bjorner (nbjorner) 2019-12-24
    Lev Nachmanson (levnach) 2019-12-24

Revision History:

--*/
#include "math/dd/dd_pdd.h"
#include "math/interval/dep_intervals.h"

namespace dd {
typedef dep_intervals::interval interval;
typedef dep_intervals::with_deps_t w_dep;
// calculates the interval of a pdd expression based on the given intervals of the variables
class pdd_interval {
    dep_intervals& m_dep_intervals;
    std::function<void (unsigned, bool, scoped_dep_interval&)> m_var2interval;

    // retrieve intervals after distributing multiplication over addition.
    template <w_dep wd>
    void get_interval_distributed(pdd const& p, scoped_dep_interval& i, scoped_dep_interval& ret) {
        bool deps = wd == w_dep::with_deps;
        if (p.is_val()) {
            if (deps)
                m_dep_intervals.mul<dep_intervals::with_deps>(p.val(), i, ret);
            else
                m_dep_intervals.mul<dep_intervals::without_deps>(p.val(), i, ret);
            return;
        }
        scoped_dep_interval hi(m()), lo(m()), t(m()), a(m());
        get_interval_distributed<wd>(p.lo(), i, lo);
        m_var2interval(p.var(), deps, a);
        if (deps) {
            m_dep_intervals.mul<dep_intervals::with_deps>(a, i, t);
            get_interval_distributed<wd>(p.hi(), t, hi);
            m_dep_intervals.add<dep_intervals::with_deps>(hi, lo, ret);
        }
        else {
            m_dep_intervals.mul<dep_intervals::without_deps>(a, i, t);
            get_interval_distributed<wd>(p.hi(), t, hi);
            m_dep_intervals.add<dep_intervals::without_deps>(hi, lo, ret);
        }
    }

public:
    
    pdd_interval(dep_intervals& d): m_dep_intervals(d) {}

    dep_intervals& m() { return m_dep_intervals; }

    std::function<void (unsigned, bool, scoped_dep_interval&)>& var2interval() { return m_var2interval; } // setter
    const std::function<void (unsigned, bool, scoped_dep_interval&)>& var2interval() const { return m_var2interval; } // getter

    template <w_dep wd>
    void get_interval(pdd const& p, scoped_dep_interval& ret) {
        if (p.is_val()) {
            m_dep_intervals.set_interval_for_scalar(ret, p.val());
            return;
        }
        bool deps = wd == w_dep::with_deps;
        scoped_dep_interval hi(m()), lo(m()), t(m()), a(m());
        m_var2interval(p.var(), deps, a);
        get_interval<wd>(p.hi(), hi);
        get_interval<wd>(p.lo(), lo);
        if (deps) {
            m_dep_intervals.mul<dep_intervals::with_deps>(hi, a, t);
            m_dep_intervals.add<dep_intervals::with_deps>(t, lo, ret);
        } else {
            m_dep_intervals.mul(hi, a, t);
            m_dep_intervals.add(t, lo, ret);
        }
    }

    template <w_dep wd>
    void get_interval_distributed(pdd const& p, scoped_dep_interval& ret) {
        scoped_dep_interval i(m());
        m_dep_intervals.set_interval_for_scalar(i, rational::one());        
        get_interval_distributed<wd>(p, i, ret);
    }
};
}
