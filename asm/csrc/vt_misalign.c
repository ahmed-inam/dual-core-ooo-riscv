// WHY THIS EXISTS (S5-I / B1): the OoO core raises misalign traps on its OWN
typedef unsigned int u32;

volatile u32 t_cause, t_tval, t_epc, t_count;

volatile u32 gbuf[4]  = { 0x11111111u, 0x22222222u, 0x33333333u, 0x44444444u };
volatile u32 gtarget  = 0xDEADBEEFu;
volatile u32 sink;

__attribute__((naked, aligned(4))) void trap_entry(void){
  __asm__ volatile(
    "csrr t0, mcause      \n"
    "la   t1, t_cause     \n  sw t0, 0(t1) \n"
    "csrr t0, mtval       \n"
    "la   t1, t_tval      \n  sw t0, 0(t1) \n"
    "csrr t0, mepc        \n"
    "la   t1, t_epc       \n  sw t0, 0(t1) \n"
    "la   t1, t_count     \n  lw t0, 0(t1) \n  addi t0, t0, 1 \n  sw t0, 0(t1) \n"
    "csrr t0, mepc        \n  addi t0, t0, 4 \n  csrw mepc, t0 \n"
    "mret                 \n"
  );
}

int main(void){
  __asm__ volatile("la t0, trap_entry \n csrw mtvec, t0" ::: "t0");

  t_count = 0; t_cause = 99; t_tval = 0;
  u32 laddr = (u32)(unsigned long)&gbuf[0] + 2u;          /* lw needs [1:0]==00 */
  __asm__ volatile("lw t2, 0(%0)" :: "r"(laddr) : "t2","t0","t1","memory");
  if (t_count != 1u)     return 1;
  if (t_cause != 4u)     return 2;
  if (t_tval  != laddr)  return 3;

  gtarget = 0xDEADBEEFu;
  t_count = 0; t_cause = 99; t_tval = 0;
  u32 saddr = (u32)(unsigned long)&gtarget + 1u;
  __asm__ volatile("sw %1, 0(%0)" :: "r"(saddr), "r"(0x12345678u) : "t0","t1","memory");
  if (t_count != 1u)         return 4;
  if (t_cause != 6u)         return 5;
  if (t_tval  != saddr)      return 6;
  if (gtarget != 0xDEADBEEFu) return 7;                   /* must be suppressed */

  t_count = 0; t_cause = 99; t_tval = 0xFFu;
  u32 jt = (u32)(unsigned long)&&back + 2u;               /* target [1]==1 -> misaligned */
  __asm__ volatile("jalr ra, 0(%0)" :: "r"(jt) : "ra","t0","t1","memory");
back: ;
  if (t_count != 1u)  return 8;
  if (t_cause != 0u)  return 9;
  if (t_tval  != jt)  return 10;                         /* mtval holds the misaligned target */

  t_count = 0;
  u32 acc = 0u, s = 0x12345u;
  for (u32 i = 0; i < 16u; i++){
    s ^= s << 13; s ^= s >> 17; s ^= s << 5;              /* xorshift */
    if (s & 1u) acc += i; else acc ^= i;                  /* in-flight branches */
    if (s & 2u) acc *= 3u; else acc += 1u;
    u32 a = (u32)(unsigned long)&gbuf[i & 3u] + 2u;       /* misaligned, correct path */
    __asm__ volatile("lw t2, 0(%0)" :: "r"(a) : "t2","t0","t1","memory");
  }
  sink = acc;                                             /* keep acc live */
  if (t_count != 16u) return 11;                          /* one trap/iter, exact */

  t_count = 0;
  volatile u32 never = 0u;
  for (u32 i = 0; i < 16u; i++){
    if (never){                                           /* never taken */
      u32 a = (u32)(unsigned long)&gbuf[0] + 1u;
      __asm__ volatile("lw t2, 0(%0)" :: "r"(a) : "t2","t0","t1","memory");
    }
  }
  if (t_count != 0u) return 12;                           /* no wrong-path trap may commit */

  return 0;                                               /* PASS */
}
