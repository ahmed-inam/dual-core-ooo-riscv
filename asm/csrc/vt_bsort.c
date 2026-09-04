// Bubble sort: a memory-and-branch mix with a checkable result.
typedef unsigned int u32;
static volatile u32 SEED = 2463534242u;
static u32 rng(u32 *s){ u32 x=*s; x^=x<<13; x^=x>>17; x^=x<<5; *s=x; return x; }
int main(void){
  u32 s=SEED; volatile u32 buf[16];
  for (u32 i=0;i<16u;i++) buf[i]=rng(&s);
  for (u32 p=0;p<16u;p++)
    for (u32 i=0;i+1u<16u;i++)
      if (buf[i]>buf[i+1]){ u32 t=buf[i]; buf[i]=buf[i+1]; buf[i+1]=t; }
  u32 ok=1u;
  for (u32 i=0;i+1u<16u;i++) if (buf[i]>buf[i+1]) ok=0u;
  return ok ? 0 : 1;
}
