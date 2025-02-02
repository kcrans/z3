/*++
Copyright (c) 2011 Microsoft Corporation

Module Name:

    smt_decl_collector.cpp

Abstract:

    Collect uninterpreted func_delcs and sorts.
    This class was originally in ast_smt_pp.h

Author:

    Leonardo (leonardo) 2011-10-04

Revision History:

--*/
#include "ast/decl_collector.h"
#include "ast/ast_pp.h"
#include "ast/recfun_decl_plugin.h"

void decl_collector::visit_sort(sort * n) {
    SASSERT(!m_visited.is_marked(n));
    family_id fid = n->get_family_id();
    if (m().is_uninterp(n))
        m_sorts.push_back(n);
    else if (fid == m_dt_fid) {
        m_sorts.push_back(n);
        for (func_decl * cnstr : *m_dt_util.get_datatype_constructors(n)) {
            m_todo.push_back(cnstr);
            ptr_vector<func_decl> const & cnstr_acc = *m_dt_util.get_constructor_accessors(cnstr);
            unsigned num_cas = cnstr_acc.size();
            for (unsigned j = 0; j < num_cas; j++) {
                m_todo.push_back(cnstr_acc.get(j));
            }
        }
    }
    for (unsigned i = n->get_num_parameters(); i-- > 0; ) {
        parameter const& p = n->get_parameter(i);
        if (p.is_ast()) m_todo.push_back(p.get_ast());
    }
}

bool decl_collector::is_bool(sort * s) {
    return m().is_bool(s);
}

void decl_collector::visit_func(func_decl * n) {
    if (!m_visited.is_marked(n)) {
        family_id fid = n->get_family_id();
        if (fid == null_family_id) 
            m_decls.push_back(n);
        else if (fid == m_rec_fid) {
            m_rec_decls.push_back(n);
            recfun::util u(m());
            m_todo.push_back(u.get_def(n).get_rhs());
        }
        m_visited.mark(n, true);
        m_trail.push_back(n);
    }
}

decl_collector::decl_collector(ast_manager & m):
    m_manager(m),
    m_trail(m),
    m_dt_util(m) {
    m_basic_fid = m_manager.get_basic_family_id();
    m_dt_fid = m_dt_util.get_family_id();
    recfun::util rec_util(m);
    m_rec_fid = rec_util.get_family_id();
}

void decl_collector::visit(ast* n) {
    if (m_visited.is_marked(n)) 
        return;
    datatype_util util(m());
    m_todo.push_back(n);
    while (!m_todo.empty()) {
        n = m_todo.back();
        m_todo.pop_back();
        if (!m_visited.is_marked(n)) {
            switch(n->get_kind()) {
            case AST_APP: {
                app * a = to_app(n);
                for (expr* arg : *a) {
                    m_todo.push_back(arg);
                }
                m_todo.push_back(a->get_decl());
                break;
            }
            case AST_QUANTIFIER: {
                quantifier * q = to_quantifier(n);
                unsigned num_decls = q->get_num_decls();
                for (unsigned i = 0; i < num_decls; ++i) {
                    m_todo.push_back(q->get_decl_sort(i));
                }
                m_todo.push_back(q->get_expr());
                for (unsigned i = 0; i < q->get_num_patterns(); ++i) {
                    m_todo.push_back(q->get_pattern(i));
                }
                break;
            }
            case AST_SORT: 
                visit_sort(to_sort(n));
                break;
            case AST_FUNC_DECL: {
                func_decl * d = to_func_decl(n);
                for (sort* srt : *d) {
                    m_todo.push_back(srt);
                }
                m_todo.push_back(d->get_range());
                visit_func(d);
                break;
            }
            case AST_VAR:
                break;
            default:
                UNREACHABLE();
            }
            m_visited.mark(n, true);
            m_trail.push_back(n);
        }
    }
}

void decl_collector::order_deps(unsigned n) {
    top_sort<sort> st;
    for (unsigned i = n; i < m_sorts.size(); ++i) {
        sort* s = m_sorts.get(i);
        st.insert(s, collect_deps(s));
    }
    st.topological_sort();
    m_sorts.shrink(n);
    for (sort* s : st.top_sorted()) {
        m_sorts.push_back(s);
    }
}

decl_collector::sort_set* decl_collector::collect_deps(sort* s) {
    sort_set* set = alloc(sort_set);
    collect_deps(s, *set);
    set->remove(s);
    return set;
}

void decl_collector::collect_deps(sort* s, sort_set& set) {
    if (set.contains(s)) return;
    set.insert(s);
    if (s->is_sort_of(m_dt_util.get_family_id(), DATATYPE_SORT)) {
        unsigned num_sorts = m_dt_util.get_datatype_num_parameter_sorts(s);
        for (unsigned i = 0; i < num_sorts; ++i) 
            set.insert(m_dt_util.get_datatype_parameter_sort(s, i));
        unsigned num_cnstr = m_dt_util.get_datatype_num_constructors(s);
        for (unsigned i = 0; i < num_cnstr; i++) {
            func_decl * cnstr = m_dt_util.get_datatype_constructors(s)->get(i);
            set.insert(cnstr->get_range());
            for (unsigned j = 0; j < cnstr->get_arity(); ++j) 
                set.insert(cnstr->get_domain(j));
        }
    }

    for (unsigned i = s->get_num_parameters(); i-- > 0; ) {
        parameter const& p = s->get_parameter(i);
        if (p.is_ast() && is_sort(p.get_ast())) 
            set.insert(to_sort(p.get_ast()));
    }
}

void decl_collector::push() {
    m_trail_lim.push_back(m_trail.size());
    m_sorts.push_scope();
    m_decls.push_scope();
    m_rec_decls.push_scope();
}

void decl_collector::pop(unsigned n) {
    SASSERT(n > 0);
    unsigned sz = m_trail_lim[m_trail_lim.size() - n];
    for (unsigned i = m_trail.size(); i-- > sz; ) 
        m_visited.mark(m_trail.get(i), false);
    m_trail.shrink(sz);
    m_trail_lim.shrink(m_trail_lim.size() - n);
    m_sorts.pop_scope(n);
    m_decls.pop_scope(n);
    m_rec_decls.pop_scope(n);
}

