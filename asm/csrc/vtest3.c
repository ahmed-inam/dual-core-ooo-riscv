// Pointer-chased loads, aliasing stores/loads, store->load forwarding at
typedef unsigned int u32;

static volatile u32 SEED = 2463534242u;
static u32 rng(u32 *s){ u32 x=*s; x^=x<<13; x^=x>>17; x^=x<<5; *s=x; return x; }

int main(void){
  u32 s = SEED;
  volatile u32 buf[64];

  for (u32 i=0;i<64u;i++) buf[i] = rng(&s);

  for (u32 p=0;p<64u;p++)
    for (u32 i=0;i+1u<64u;i++)
      if (buf[i] > buf[i+1]){
        u32 t = buf[i]; buf[i] = buf[i+1]; buf[i+1] = t;   /* ld,ld,st,st */
      }

  u32 ok = 1u;
  for (u32 i=0;i+1u<64u;i++) if (buf[i] > buf[i+1]) ok = 0u;
  if (!ok) return 1;

  u32 acc = 0;
  for (u32 i=0;i<128u;i++){
    u32 j  = rng(&s) & 63u;
    u32 k  = rng(&s) & 63u;
    buf[j] = buf[j] + buf[k];       /* ld buf[j], ld buf[k], st buf[j] */
    acc   ^= buf[(j+k)&63u];        /* ld possibly-just-written slot */
  }

  u32 idx = 0;
  for (u32 i=0;i<256u;i++) idx = buf[idx & 63u] & 63u;
  acc ^= idx;

  if (acc == 0xABCDEF01u) return 2;   /* keep acc live */
  return 0;
}
