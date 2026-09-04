// RESCOPED FROM MEASUREMENT, TWICE, AND THEN CORRECTED ONCE MORE FROM ITS OWN
volatile unsigned buf[2048];
volatile unsigned divisor = 0x7ffffffdu;   /* runtime, so the divu is real */

#define DEPTH     12      /* > RAS_DEPTH = 8: the stack overflows and unwinds */
#define CHAIN      6      /* dependent misses: the head stall */
#define LD_BURST  12      /* > LQ_N = 8 */
#define ST_BURST  10      /* > SQ_N = 8, concurrent with the loads */
#define SPIN      14      /* LFSR branches dispatched behind the stalled head */
#define STRIDE    64      /* 64 words = 256 B: a new line every time */
#define ROUNDS    16
#define SLICE     1024
#define MASK      (SLICE - 1u)

static __attribute__((noinline))
unsigned descend(unsigned d, unsigned base, unsigned lfsr)
{
    unsigned acc = 0, s = lfsr, i;

    for (i = 0; i < CHAIN; i++)
        s = buf[base + ((s * STRIDE + i * STRIDE) & MASK)];

    for (i = 0; i < LD_BURST; i++) {
        acc += buf[base + ((i * STRIDE) & MASK)];
        if (i < ST_BURST)
            buf[base + ((i * STRIDE + 8u) & MASK)] = acc + i;
    }

    for (i = 0; i < SPIN; i++) {
        s = (s >> 1) ^ ((0u - (s & 1u)) & 0xb4bcd35cu);
        if (s & 0x8000u) acc += 7u; else acc ^= 0x33u;
    }

    {
        unsigned late0, dv = divisor;
        __asm__ volatile ("divu %0, %1, %2" : "=r"(late0) : "r"(acc & 0xffffu), "r"(dv));
        buf[base + late0 + 16u] = acc;
        acc += buf[base + 16u];
    }

    if (d)
        acc += descend(d - 1u, base, s);

    __asm__ volatile ("fence rw,rw" ::: "memory");
    for (i = 0; i < 8u; i++)
        acc += buf[base + ((i * STRIDE + 32u) & MASK)];
    s = (s >> 1) ^ ((0u - (s & 1u)) & 0xb4bcd35cu);
    if (s & 0x40u) acc += 11u;

    return acc;
}

int main(int hartid)
{
    unsigned base = (unsigned)hartid * SLICE;
    unsigned acc = 0, r;

    for (r = 0; r < SLICE; r += 4)
        buf[base + r] = r + (unsigned)hartid + 1u;

    for (r = 0; r < ROUNDS; r++)
        acc += descend(DEPTH, base, acc + r + (unsigned)hartid + 1u);

    return (acc == 0u) ? 1 : 0;
}
