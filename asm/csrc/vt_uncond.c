// Unconditional jumps and calls, for the BTB and return stack.
typedef unsigned int u32;
static volatile u32 SEED=2463534242u;
static u32 rng(u32*s){u32 x=*s;x^=x<<13;x^=x>>17;x^=x<<5;*s=x;return x;}
int main(void){
  u32 s=SEED; volatile u32 buf[16];
  for(u32 i=0;i<16u;i++) buf[i]=rng(&s);
  for(u32 p=0;p<64u;p++)
    for(u32 i=0;i+1u<16u;i++){ u32 a=buf[i],b=buf[i+1]; buf[i]=b; buf[i+1]=a; } /* unconditional swap */
  return (buf[0]==0)?1:0;
}
