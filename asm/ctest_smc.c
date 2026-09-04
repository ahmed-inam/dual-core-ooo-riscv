// fence.i counter-proof.

typedef unsigned int u32;
typedef u32 (*fn_t)(u32);

static u32 code[2] = { 0x00150513u, 0x00008067u };

static inline u32 addi_a0_imm(u32 imm) { return (imm << 20) | 0x00050513u; }

static inline void wr(u32 addr, u32 v) { *(volatile u32 *)addr = v; }
static inline u32 rd_csr_cycle(void)   { u32 v; __asm__ volatile("csrr %0, mcycle"   : "=r"(v)); return v; }
static inline u32 rd_csr_instret(void) { u32 v; __asm__ volatile("csrr %0, minstret" : "=r"(v)); return v; }

int main(void) {
  volatile u32 imms[4] = { 2, 3, 5, 7 };
  volatile u32 x = 100;
  fn_t f = (fn_t)code;
  u32 passes = 0;

  (void)f(x);                                   /* warm the I-cache */

  for (int i = 0; i < 4; i++) {
    u32 imm = imms[i];
    code[0] = addi_a0_imm(imm);                 /* dirty in the D-cache   */
    __asm__ volatile("fence.i" ::: "memory");   /* the instruction on trial */
    if (f(x) == x + imm) passes++;              /* did the patch execute? */
  }

  u32 cyc = rd_csr_cycle(), ins = rd_csr_instret();
  wr(0x200, cyc);  wr(0x204, ins);
  for (u32 a = 0x208; a <= 0x224; a += 4) wr(a, 0);
  wr(0x228, 0x5AFE0000u + passes);              /* the verdict            */
  __asm__ volatile("fence" ::: "memory");       /* push results to memory */
  __asm__ volatile("li t3, 1" ::: "t3");        /* x28=1: tb_sys finish   */
  for (;;) ;
}
