// FULL WITH THE STORE QUEUE NEARLY EMPTY.
typedef unsigned int u32;

#define CHASE_WORDS 2048            /* 8 KB per hart: 8x the 1 KB D-cache */
#define SLICE       (CHASE_WORDS / 2)
#define PAD         40              /* > ROB_N - RENAME_W = 30 */
#define ROUNDS      400

static volatile u32 chase[CHASE_WORDS];
static volatile u32 pad_src[64];
static volatile u32 sink[2];

int main(int hartid)
{
    u32 base = (u32)hartid * SLICE;
    u32 p = base, acc = 0, i, k;
    u32 r[8];

    for (i = 0; i < SLICE; i++)
        chase[base + i] = base + ((i * 257u + 129u) % SLICE);
    for (i = 0; i < 64u; i++) pad_src[i] = i * 7u + 1u;

    for (k = 0; k < ROUNDS; k++) {

        p = chase[p]; p = chase[p]; p = chase[p]; p = chase[p];

        __asm__ volatile ("fence rw,rw" ::: "memory");

        for (i = 0; i < PAD; i++)
            acc += pad_src[i & 63u] ^ (i + k);

        sink[hartid] = k;

        r[0] = chase[base + ((k * 16u +   0u) % SLICE)];
        r[1] = chase[base + ((k * 16u +  64u) % SLICE)];
        r[2] = chase[base + ((k * 16u + 128u) % SLICE)];
        r[3] = chase[base + ((k * 16u + 192u) % SLICE)];
        r[4] = chase[base + ((k * 16u + 256u) % SLICE)];
        r[5] = chase[base + ((k * 16u + 320u) % SLICE)];
        r[6] = chase[base + ((k * 16u + 384u) % SLICE)];
        r[7] = chase[base + ((k * 16u + 448u) % SLICE)];
        acc += r[0] + r[1] + r[2] + r[3] + r[4] + r[5] + r[6] + r[7];
    }

    sink[hartid] = acc;
    return (acc == 0xFFFFFFFFu) ? 1 : 0;
}
