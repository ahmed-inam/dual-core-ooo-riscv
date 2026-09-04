// Conditional-branch shapes, for the predictor and hazard coverage.
typedef unsigned int u32;
static volatile u32 SEED=2463534242u;
static u32 rng(u32*s){u32 x=*s;x^=x<<13;x^=x>>17;x^=x<<5;*s=x;return x;}
int main(void){
  u32 s=SEED; volatile u32 in[16], out[16];
  for(u32 i=0;i<16u;i++) in[i]=rng(&s);
  for(u32 i=0;i<16u;i++){ if(in[i]&1u) out[i]=in[i]*3u; else out[i]=in[i]>>1; }
  u32 acc=0; for(u32 i=0;i<16u;i++) acc^=out[i];
  return (acc==0xdeadu)?1:0;
}
