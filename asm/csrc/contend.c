// PURPOSE: measure merge_dcoh (the cross-hart master0 arbiter) under SUSTAINED
volatile unsigned buf[1024];

#define ROUNDS   16
#define WORDS    256          /* 1 KB per hart = exactly the whole D-cache */
#define STRIDE   4            /* 4 words = 16 B = one line */

int main(int hartid)
{
    unsigned base = (unsigned)hartid * 512u;   /* disjoint 2 KB apart */
    unsigned acc  = 0;

    for (int r = 0; r < ROUNDS; r++) {
        for (unsigned i = 0; i < WORDS; i += STRIDE)
            buf[base + i] += (unsigned)hartid + 1u;

        for (unsigned i = 0; i < WORDS; i += STRIDE)
            acc += buf[base + i];

        __asm__ volatile ("fence rw,rw" ::: "memory");
    }

    return (acc == 0u) ? 1 : 0;
}
