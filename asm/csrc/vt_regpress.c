// Many simultaneously-live values force heavy rename churn: the freelist
typedef unsigned int u32;
static volatile u32 SEED = 777u;

static u32 ping(u32 n, u32 acc);
static u32 pong(u32 n, u32 acc){
  if (n == 0u) return acc;
  return ping(n-1u, acc*3u + 1u);
}
static u32 ping(u32 n, u32 acc){
  if (n == 0u) return acc;
  return pong(n-1u, acc*5u + 2u);
}

static u32 mix16(u32 x){
  u32 a=x,       b=x^0x11u, c=x+0x22u, d=x*3u;
  u32 e=x^0x44u, f=x+0x55u, g=x*7u,    h=x^0x77u;
  u32 i=x+0x88u, j=x*9u,    k=x^0xaau,  l=x+0xbbu;
  u32 m=x*13u,   n=x^0xddu, o=x+0xeeu,  p=x*17u;
  for (u32 t=0;t<8u;t++){
    a+=b; b^=c; c+=d; d^=e; e+=f; f^=g; g+=h; h^=i;
    i+=j; j^=k; k+=l; l^=m; m+=n; n^=o; o+=p; p^=a;
  }
  return a^b^c^d^e^f^g^h^i^j^k^l^m^n^o^p;
}

int main(void){
  u32 s = SEED;
  u32 acc = ping(64u, s);
  for (u32 r=0;r<64u;r++) acc = mix16(acc + r) ^ (acc*2654435761u);
  if (acc == 0x0u) return 1;
  return 0;
}
