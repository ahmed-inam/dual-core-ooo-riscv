// Golden survey (house rule, applied BEFORE writing): culsans

#define ITERS      64          /* increments per hart */
#define NUM_HARTS  2           /* keep in step with platform_cfg_pkg */
#define BUF_WORDS  16          /* small on purpose: forces line-level conflict */
#define RAND_OPS   96
#define WAIT_MAX   (1u << 20)  /* spins allowed for the other hart to finish */

volatile unsigned counter;
volatile unsigned shared_buf[BUF_WORDS];

static inline void atomic_inc(volatile unsigned *p)
{
    unsigned tmp, fail;
    __asm__ volatile(
        "1: lr.w  %0, (%2)\n"
        "   addi  %0, %0, 1\n"
        "   sc.w  %1, %0, (%2)\n"
        "   bnez  %1, 1b\n"
        : "=&r"(tmp), "=&r"(fail)
        : "r"(p)
        : "memory");
}

static inline unsigned xs(unsigned *s)
{
    unsigned x = *s;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    *s = x;
    return x;
}

int main(int hartid)
{
    unsigned seed = 0x1234567u + (unsigned)hartid * 0x9E3779B9u;
    unsigned acc  = 0;

    for (int i = 0; i < RAND_OPS; i++) {
        unsigned r   = xs(&seed);
        unsigned idx = r % BUF_WORDS;
        if (r & 0x10000u)
            shared_buf[idx] = r ^ (unsigned)hartid;   /* write: GetM + snoops */
        else
            acc += shared_buf[idx];                   /* read: GetS + sharing  */
        if ((i & 1) == 0)
            atomic_inc(&counter);                     /* contended LR/SC       */
    }

    for (int i = 0; i < ITERS - (RAND_OPS / 2); i++)
        atomic_inc(&counter);

    __asm__ volatile ("fence rw,rw" ::: "memory");
    if (acc == 0xFFFFFFFFu) return 1;      /* never taken; keeps acc live */

    /* The verdict is the FINAL count, not this hart's view of it: wait for the
       other hart, so that finishing first is not reported as a lost update. */
    for (unsigned w = 0; w < WAIT_MAX && counter != ITERS * NUM_HARTS; w++)
        ;
    return (int)counter;
}
