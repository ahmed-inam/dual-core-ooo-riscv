// volatile seeds defeat constant folding; multipliers are non-pow2 so gcc
typedef unsigned int u32;
typedef int i32;

static volatile u32 SEED_A = 1234567u;
static volatile i32 SEED_B = -98765;
static volatile u32 SEED_N = 20u;

static u32 fib(u32 n){ return (n < 2) ? n : fib(n-1) + fib(n-2); }

static u32 collatz_len(u32 n){
  u32 steps=0;
  while (n!=1u){ if(n&1u) n=3u*n+1u; else n=n/2u; if(++steps>1000u) break; }
  return steps;
}

int main(void){
  u32 acc = 0;

  u32 f = fib(SEED_N);              /* fib(20)=6765, but n is volatile */
  acc ^= f * 2654435761u;           /* Knuth hash: real 32x32 mul, keeps low32 */

  u32 a = SEED_A, i;
  for (i=0;i<64u;i++){
    u32 b = a*1103515245u + 12345u; /* LCG: 32x32 mul */
    u32 d = b / (a|1u);             /* divu, runtime divisor */
    u32 m = b % ((a>>3)|1u);        /* remu */
    acc += d ^ (m*31u) ^ (b>>7);
    a = b;
  }

  i32 x = SEED_B, y = 9876;
  i32 q = x / y;                    /* signed, negative dividend */
  i32 r = x % y;
  acc ^= (u32)q * 40503u;
  acc += (u32)r;

  u32 hi = (u32)(((unsigned long long)SEED_A * 2654435761ull) >> 32);
  acc ^= hi;

  u32 seq = SEED_A;
  for (i=0;i<200u;i++){
    seq = seq*1664525u + 1013904223u;   /* mul */
    if (seq & 0x10000u) acc += collatz_len((seq&0x3fu)|1u);
    else                acc ^= seq >> 3;
  }

  if (acc == 0xFFFFFFFFu) return 7;   /* keep acc live; ~never true */
  return 0;
}
