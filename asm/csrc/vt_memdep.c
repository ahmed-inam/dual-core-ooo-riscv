// The LSQ speculates loads past unknown-address older stores; when the
typedef unsigned int u32;
static volatile u32 SEED = 0xDEADBEEFu;
static u32 rng(u32 *s){ u32 x=*s; x^=x<<13; x^=x>>17; x^=x<<5; *s=x; return x; }

int main(void){
  u32 s = SEED;
  volatile u32 a[32];
  for (u32 i=0;i<32u;i++) a[i] = i;

  u32 acc = 0;
  for (u32 k=0;k<400u;k++){
    u32 si = rng(&s) & 31u;
    u32 li = (si + (rng(&s) & 1u)) & 31u;   /* li == si half the time */
    u32 v  = rng(&s);
    a[si] = a[si] + v;        /* store to a[si] (address via runtime si) */
    acc  ^= a[li];            /* load a[li]: aliases a[si] ~half the time */
    a[(si+1u)&31u] = a[(si+1u)&31u] ^ (acc & 0xffu);
  }
  for (u32 i=0;i<32u;i++) acc = acc*16777619u + a[i];
  if (acc == 0xcafef00du) return 1;
  return 0;
}
