#!/usr/bin/env python3
"""Syllable grammars as automata, for lib/ufont's Indic shaper and its model.

A grammar is a list of (pattern, syllable type) tried as a longest-match
scanner over the characters' syllable categories: at each place the longest
match of any pattern is the next syllable, a tie going to the pattern listed
first. Patterns are built from

    cat(*categories)      one character of any of these categories
    seq(a, b, ...)        a then b ...
    alt(a, b, ...)        a or b ...
    opt(a), star(a)       a or nothing; any number of a
    ANY                   any one character

and compiled to one DFA (dfa(grammar)): states, a transition per state and
category class, and each state's syllable type when a match may end there.

Development-machine tooling only; not part of any OS image.
"""


class Pat:
    """A pattern: a fragment of an NFA built on demand."""

    def __init__(self, build):
        self.build = build


def cat(*cats):
    def build(nfa, start, end):
        nfa.edge(start, frozenset(cats), end)
    return Pat(build)


ANY = Pat(lambda nfa, start, end: nfa.edge(start, None, end))


def seq(*ps):
    def build(nfa, start, end):
        cur = start
        for p in ps[:-1]:
            nxt = nfa.state()
            p.build(nfa, cur, nxt)
            cur = nxt
        if ps:
            ps[-1].build(nfa, cur, end)
        else:
            nfa.eps(cur, end)
    return Pat(build)


def alt(*ps):
    def build(nfa, start, end):
        for p in ps:
            p.build(nfa, start, end)
    return Pat(build)


def opt(p):
    def build(nfa, start, end):
        nfa.eps(start, end)
        p.build(nfa, start, end)
    return Pat(build)


def star(p):
    def build(nfa, start, end):
        mid = nfa.state()
        nfa.eps(start, mid)
        inner = nfa.state()
        p.build(nfa, mid, inner)
        nfa.eps(inner, mid)
        nfa.eps(mid, end)
    return Pat(build)


class NFA:
    def __init__(self):
        self.edges = []                     # per state: [(categories or None for any, target)]
        self.epsilon = []
        self.accept = {}                    # state -> rank

    def state(self):
        self.edges.append([])
        self.epsilon.append([])
        return len(self.edges) - 1

    def edge(self, a, cats, b):
        self.edges[a].append((cats, b))

    def eps(self, a, b):
        self.epsilon[a].append(b)

    def closure(self, states):
        todo, seen = list(states), set(states)
        while todo:
            s = todo.pop()
            for t in self.epsilon[s]:
                if t not in seen:
                    seen.add(t)
                    todo.append(t)
        return frozenset(seen)


def dfa(grammar, categories):
    """grammar: [(pattern, type)]; categories: every category value that occurs.

    -> (classes, trans, accept): classes maps a category to its class (categories
    not in the map are class 0, which only ANY matches); trans[state][class] is the
    next state or -1; accept[state] is the syllable type a match ending there has,
    or -1. State 0 is the start."""
    nfa = NFA()
    start = nfa.state()
    for rank, (p, _) in enumerate(grammar):
        s, e = nfa.state(), nfa.state()
        nfa.eps(start, s)
        p.build(nfa, s, e)
        nfa.accept[e] = rank
    # category classes: categories no pattern tells apart share a class
    sig = {}
    for c in [None] + sorted(categories):
        key = tuple(c is not None and cats is not None and c in cats or cats is None
                    for es in nfa.edges for cats, _ in es)
        sig.setdefault(key, []).append(c)
    groups = sorted(sig.values(), key=lambda g: (g[0] is not None, g))
    classes = {}
    for k, g in enumerate(groups):
        for c in g:
            if c is not None:
                classes[c] = k
    reps = [g[0] for g in groups]
    first = nfa.closure([start])
    states, index, trans, accept = [first], {first: 0}, [], []
    i = 0
    while i < len(states):
        cur = states[i]
        ranks = [nfa.accept[s] for s in cur if s in nfa.accept]
        accept.append(grammar[min(ranks)][1] if ranks and i else -1)
        row = []
        for rep in reps:
            nxt = set()
            for s in cur:
                for cats, t in nfa.edges[s]:
                    if cats is None or (rep is not None and rep in cats):
                        nxt.add(t)
            if not nxt:
                row.append(-1)
                continue
            nxt = nfa.closure(nxt)
            if nxt not in index:
                index[nxt] = len(states)
                states.append(nxt)
            row.append(index[nxt])
        trans.append(row)
        i += 1
    return classes, trans, accept


def scan(machine, cats):
    """Longest-match syllables of a category list -> [(start, end, type)]."""
    classes, trans, accept = machine
    out, p, n = [], 0, len(cats)
    while p < n:
        state, q, best = 0, p, None
        while q < n:
            state = trans[state][classes.get(cats[q], 0)]
            if state < 0:
                break
            q += 1
            if accept[state] >= 0:
                best = (q, accept[state])
        end, typ = best
        out.append((p, end, typ))
        p = end
    return out
