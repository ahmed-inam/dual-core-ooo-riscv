// rare cross-path interactions get many chances: aliasing conditional
typedef unsigned int u32;
typedef unsigned char u8;
static volatile u32 SEED = 0x1BADB002u;
static u32 rng(u32 *s){ u32 x=*s; x^=x<<13; x^=x>>17; x^=x<<5; *s=x; return x; }

static u32 fib(u32 n){ return n<2u ? n : fib(n-1u)+fib(n-2u); }

static u32 hash_sort(volatile u32 *a, u32 n, u32 *s){
  for (u32 i=0;i<n;i++) a[i] = rng(s);
  for (u32 i=1;i<n;i++){
    u32 key = a[i]; u32 j = i;
    while (j>0u && a[j-1u] > key){ a[j] = a[j-1u]; j--; }  /* alias ld/st + branch */
    a[j] = key;
  }
  u32 h = 2166136261u;
  for (u32 i=0;i<n;i++){ h ^= a[i]; h *= 16777619u; }      /* FNV, real mul */
  return h;
}

int main(void){
  u32 s = SEED, acc = 0;
  volatile u32 arr[48];
  volatile u8  bytes[96];

  for (u32 round=0; round<80u; round++){
    acc ^= hash_sort(arr, 48u, &s);

    for (u32 i=0;i<96u;i++) bytes[i] = (u8)rng(&s);
    for (u32 i=0;i+1u<96u;i++)
      if (bytes[i] > bytes[i+1]){ u8 t=bytes[i]; bytes[i]=bytes[i+1]; bytes[i+1]=t; }
    for (u32 i=0;i<96u;i++) acc = acc*33u + bytes[i];

    u32 x = rng(&s);
    u32 dv = (x & 3u) ? (x|1u) : 0u;
    u32 q,r; __asm__ volatile("divu %0,%1,%2":"=r"(q):"r"(x),"r"(dv));
             __asm__ volatile("remu %0,%1,%2":"=r"(r):"r"(x),"r"(dv));
    acc ^= q ^ (r*2654435761u);

    if ((round & 15u) == 0u) acc += fib(18u);
  }

  if (acc == 0xFFFFFFFFu) return 1;
  return 0;
}
