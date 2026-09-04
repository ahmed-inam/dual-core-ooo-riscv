// Byte/halfword loads and stores with conditional (mispredictable) stores
typedef unsigned int u32;
typedef unsigned char u8;
typedef unsigned short u16;

static volatile u32 SEED = 0x9E3779B9u;
static u32 rng(u32 *s){ u32 x=*s; x^=x<<13; x^=x>>17; x^=x<<5; *s=x; return x; }

int main(void){
  u32 s = SEED;
  volatile u8  b[64];
  volatile u16 h[32];

  for (u32 i=0;i<64u;i++) b[i] = (u8)rng(&s);

  for (u32 p=0;p<32u;p++)
    for (u32 i=0;i+1u<64u;i++)
      if (b[i] > b[i+1]){ u8 t=b[i]; b[i]=b[i+1]; b[i+1]=t; }

  for (u32 i=0;i<32u;i++){
    u16 packed = (u16)(((u16)b[2*i] << 8) | (u16)b[2*i+1]);  /* sb-built value */
    h[i] = packed;                                           /* sh store */
  }
  u32 acc = 0;
  for (u32 i=0;i<32u;i++){
    u16 v = h[i];                 /* lhu, likely forwarded from the sh above */
    acc = acc*65599u + v;         /* runtime mul */
    if (v & 0x0100u) acc ^= (u32)b[i & 63u];  /* extra byte load, data-dep */
  }

  volatile signed char sc[16];
  for (u32 i=0;i<16u;i++) sc[i] = (signed char)(rng(&s) | 0x80u); /* negative */
  int ssum = 0;
  for (u32 i=0;i<16u;i++) ssum += (int)sc[i];   /* lb sign extension */
  acc ^= (u32)ssum;

  if (acc == 0x1234abcdu) return 1;   /* keep acc live */
  return 0;
}
