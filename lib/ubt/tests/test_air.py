"""The virtual radio made worse (sim/radio.py: loss, delay, noise) and the
stack coping: ERTM delivering everything in order over a lossy link,
delayed packets still in order, damaged frames caught by the FCS, the
same run twice giving the same result.

usage: python3 test_air.py path/to/ubt.so
"""
import ctypes as C
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from l2cap_env import Env, ERTM, BASIC  # noqa: E402

E = Env(sys.argv[1])
check, ca, cb, SA, SB = E.check, E.ca, E.cb, E.SA, E.SB
E.server(0x1101, ERTM, C.byref(SB.ops), None)
E.server(0x1001, BASIC, C.byref(SB.ops), None)
ka, kb = E.link()
ch = E.l2connect(ka, 0x1101, ERTM, C.byref(SA.ops), None)
E.settle()
check("an ERTM channel over a clean link", [e[1] for e in SA.events], [1])


def push(n, tag, rounds=400):
    SB.data.clear()
    for i in range(n):
        E.l2send(ch, bytes([tag, i]) * 20, 40)
    for _ in range(rounds):
        E.settle(2)
        E.now[0] += 500                                 # the retransmission timer runs
        if len(SB.data) >= n:
            break
    return [d[1][1] for d in SB.data]


# ---- loss -----------------------------------------------------------------------------------------------------
E.radio.seed(11)
ca.loss = cb.loss = 0.05
got = push(30, 1)
check("5% of the packets lost both ways: ERTM still delivers all 30, in order", got, list(range(30)))
check("and packets really were lost", E.radio.lost > 0, True)
ca.loss = cb.loss = 0.0

# ---- delay ------------------------------------------------------------------------------------------------------
ca.delay = 3
got = push(10, 2)
check("A's packets held back three rounds: all arrive, in order", got, list(range(10)))
ca.delay = 0

# ---- noise -------------------------------------------------------------------------------------------------------
E.radio.seed(12)
ca.noise = 0.03
dropped = C.c_uint32.in_dll(E.lib, "l2cap_dropped").value
got = push(30, 3)
check("a bit flipped in 3% of A's packets: the FCS catches each, ERTM resends, all arrive whole",
      (got, all(d[1] == bytes([3, d[1][1]]) * 20 for d in SB.data)), (list(range(30)), True))
check("damaged frames were seen and dropped", (E.radio.damaged > 0,
                                               C.c_uint32.in_dll(E.lib, "l2cap_dropped").value > dropped), (True, True))
ca.noise = 0.0

# ---- the same seed, the same air --------------------------------------------------------------------------------
def trial(seed):
    E.radio.seed(seed)
    E.radio.lost = 0
    ca.loss = 0.3
    out = []
    for i in range(50):
        E.radio.air(ca, cb, b"", bytes([i]))
    ca.loss = 0.0
    return E.radio.lost


check("the same seed loses the same packets", trial(5), trial(5))

# ---- a link too bad to use: ERTM gives up cleanly (MaxTransmit), it does not hang --------------------------------
E.radio.later.clear()
SA.events.clear()
ch = E.l2connect(ka, 0x1101, ERTM, C.byref(SA.ops), None)
E.settle()
E.radio.seed(11)
ca.loss = cb.loss = 0.6
push(30, 4, rounds=200)
ca.loss = cb.loss = 0.0
E.now[0] += 60000
E.settle()
check("60% lost both ways: the channel closed, not stuck", [e[1] for e in SA.events if e[0] == ch][-1:], [2])
E.radio.later.clear()
E.radio.queue.clear()

E.disconnect(ka, 0x13)
E.settle()
E.remove(E.a)
E.remove(E.b)
check("every block given back", sorted(E.live.values()), [])
print(f"test_air: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)
