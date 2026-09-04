// div-by-zero (defined on RISC-V: q=-1, r=dividend -- NOT a trap, but a
typedef unsigned int u32;
typedef int i32;
static volatile u32 SEED = 0xB16B00B5u;
static u32 rng(u32 *s){ u32 x=*s; x^=x<<13; x^=x>>17; x^=x<<5; *s=x; return x; }

int main(void){
  u32 s = SEED, acc = 0;
  for (u32 k=0;k<256u;k++){
    u32 x = rng(&s);
    u32 divisor = (x & 7u) ? (x & 0xffffu) : 0u;
    u32 q, r;
    __asm__ volatile("divu %0,%1,%2":"=r"(q):"r"(x),"r"(divisor));
    __asm__ volatile("remu %0,%1,%2":"=r"(r):"r"(x),"r"(divisor));
    i32 sq, sr; i32 sx = (i32)x;
    i32 sd = (x & 15u) ? (i32)(x|1u) : -1;
    if ((x & 31u) == 0u) sx = (i32)0x80000000u;   /* force INT_MIN sometimes */
    __asm__ volatile("div %0,%1,%2":"=r"(sq):"r"(sx),"r"(sd));
    __asm__ volatile("rem %0,%1,%2":"=r"(sr):"r"(sx),"r"(sd));
    acc ^= q + r + (u32)sq + (u32)sr;
    if (x & 1u){ if (x & 2u){ if (x & 4u) acc += k; else acc ^= k; } else acc -= k; }
    else       { if (x & 8u) acc *= 3u; else acc += x>>3; }
  }
  if (acc == 0x0u) return 1;
  return 0;
}
