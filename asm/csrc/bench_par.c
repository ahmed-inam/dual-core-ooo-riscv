// bench_par.c -- [S6] THE PARALLEL BENCHMARK. One workload, two partitionings.

#define ARR_WORDS 1024
#define REPS      16          /* amortise hart0's serial array init (Amdahl) */
#define SLOT_PAD  16          /* 16 words = 64 B: slots in different lines */

#ifndef SERIAL_ONLY
#define SERIAL_ONLY 0
#endif

volatile unsigned arr[ARR_WORDS];
volatile unsigned partial[2 * SLOT_PAD];
volatile unsigned init_done[SLOT_PAD];
volatile unsigned half_done[SLOT_PAD];

static unsigned reduce(unsigned lo, unsigned hi)
{
    unsigned acc = 0;
    for (unsigned r = 0; r < REPS; r++)
        for (unsigned i = lo; i < hi; i++)
            acc += arr[i] ^ (i * 40503u);   /* NOT arr[i]'s own constant: */
    return acc;
}

int main(int hartid)
{
    unsigned lo, hi, acc;

    if (hartid == 0) {
        for (unsigned i = 0; i < ARR_WORDS; i++)
            arr[i] = i * 2654435761u;
        __asm__ volatile ("fence rw,rw" ::: "memory");
        init_done[0] = 1;
    } else {
        while (init_done[0] == 0) { }
        __asm__ volatile ("fence rw,rw" ::: "memory");
    }

#if SERIAL_ONLY
    if (hartid != 0) { partial[SLOT_PAD] = 0;
                       __asm__ volatile ("fence rw,rw" ::: "memory");
                       half_done[0] = 1; return 0; }
    lo = 0; hi = ARR_WORDS;
#else
    lo = (unsigned)hartid * (ARR_WORDS / 2);
    hi = lo + (ARR_WORDS / 2);
#endif

    acc = reduce(lo, hi);
    partial[(unsigned)hartid * SLOT_PAD] = acc;

    if (hartid != 0) {
        __asm__ volatile ("fence rw,rw" ::: "memory");
        half_done[0] = 1;
        return 0;
    }
    while (half_done[0] == 0) { }
    __asm__ volatile ("fence rw,rw" ::: "memory");
    return (int)(partial[0] + partial[SLOT_PAD]);
}
