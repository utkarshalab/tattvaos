#include <assert.h>
#include <stdint.h>
#include <stdio.h>

struct timer_entry {
    uint64_t expires;
    void (*fn)(void *);
    void *arg;
    struct timer_entry *next;
    struct timer_entry *prev;
    uint8_t active;
    uint8_t level;
    uint16_t pad;
    uint32_t reserved;
};

extern void timer_wheel_init(void *wheel);
extern int timer_wheel_add(struct timer_entry *, uint64_t, void (*)(void *), void *);
extern int timer_wheel_del(struct timer_entry *);
extern uint64_t timer_wheel_tick(void *wheel);
extern uint64_t timer_wheel_get_tick(void);

static void count(void *arg) { ++*(unsigned *)arg; }

int main(void) {
    struct timer_entry first = {0}, second = {0}, cascaded = {0};
    struct timer_entry older = {0}, newer = {0};
    unsigned fired = 0;

    timer_wheel_init(0);
    assert(timer_wheel_get_tick() == 0);
    assert(timer_wheel_add(&first, 1, count, &fired) == 0);
    assert(timer_wheel_add(&second, 2, count, &fired) == 0);
    assert(timer_wheel_del(&second) == 0);
    assert(timer_wheel_del(&second) == -1);
    assert(timer_wheel_tick(0) == 1 && fired == 1);
    assert(timer_wheel_tick(0) == 0 && fired == 1);

    assert(timer_wheel_add(&cascaded, 300, count, &fired) == 0);
    for (unsigned i = 0; i < 299; ++i)
        timer_wheel_tick(0);
    assert(fired == 1);
    assert(timer_wheel_tick(0) == 1 && fired == 2);
    assert(timer_wheel_get_tick() == 302);

    timer_wheel_init(0);
    assert(timer_wheel_add(&older, 1, count, &fired) == 0);
    assert(timer_wheel_add(&newer, 1, count, &fired) == 0);
    assert(timer_wheel_del(&older) == 0);
    assert(timer_wheel_tick(0) == 1 && fired == 3);

    puts("timer wheel: PASS");
    return 0;
}
