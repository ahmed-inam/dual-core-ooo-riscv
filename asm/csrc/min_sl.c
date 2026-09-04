// Distills vt_memdep's failing inner loop to ~1/8 array, ~1/8 iterations so a
typedef unsigned int u32;
static volatile u32 SEED = 0xDEADBEEFu;
static u32 rng(u32 *s){ u32 x=*s; x^=x<<13; x^=x>>17; x^=x<<5; *s=x; return x; }

int main(void){
  volatile u32 a[8];
  for (u32 i=0;i<8u;i++) a[i]=i;
  u32 s = SEED, acc = 0;
  for (u32 k=0;k<48u;k++){
    u32 si = rng(&s) & 7u;
    u32 li = (si + (rng(&s) & 1u)) & 7u;             /* li==si ~half the time  */
    u32 v  = rng(&s);
    a[si] = a[si] + v;                               /* store to a[si]         */
    acc  ^= a[li];                                   /* load a[li]: aliases    */
    a[(si+1u)&7u] = a[(si+1u)&7u] ^ (acc & 0xffu);   /* trailing store -> SQ busy */
  }
  if (acc == 0xdeadbeefu) return 1;
  return 0;
}
