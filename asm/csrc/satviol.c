// THE TARGET BINS, all in cov_core and all measured unhit across every program
typedef unsigned int u32;

#define CHASE_WORDS  2048           /* 8 KB per hart: 8x the D-cache */
#define SLICE        (CHASE_WORDS / 2)
#define ROUNDS       600
#define BURST        8              /* == SQ_N == LQ_N */

static volatile u32 chase[CHASE_WORDS];
static volatile u32 alias[2][8];
static volatile u32 sink[2][BURST];
static volatile u32 SEED = 0x1234567u;

static u32 rng(u32 *s){ u32 x=*s; x^=x<<13; x^=x>>17; x^=x<<5; *s=x; return x; }

int main(int hartid)
{
    u32 base = (u32)hartid * SLICE;
    u32 s = SEED + (u32)hartid, acc = 0, p = base, i, k;

    for (i = 0; i < SLICE; i++)
        chase[base + i] = base + ((i * 257u + 129u) % SLICE);

    for (i = 0; i < 8u; i++)  alias[hartid][i] = i;

    for (k = 0; k < ROUNDS; k++) {
        u32 si, li, v;

        p = chase[p]; p = chase[p]; p = chase[p]; p = chase[p];
        p = chase[p]; p = chase[p]; p = chase[p]; p = chase[p];

        for (i = 0; i < BURST; i++)
            sink[hartid][i] = acc + i + k;

        si = rng(&s) & 7u;
        li = (si + (rng(&s) & 1u)) & 7u;
        v  = rng(&s);
        alias[hartid][si] = alias[hartid][si] + v;
        acc ^= alias[hartid][li];

        acc += p;
    }

    return (acc == 0xFFFFFFFFu) ? 1 : 0;
}
