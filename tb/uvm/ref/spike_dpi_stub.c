#include <stdint.h>
int      spike_open(const char* i, const char* s, int n, uint64_t pc) { (void)i;(void)s;(void)n;(void)pc; return 0; }
void     spike_close(void) {}
int      spike_step(int h) { (void)h; return 0; }
uint64_t spike_get_pc(int h)  { (void)h; return 0; }
uint64_t spike_get_reg(int h, int i) { (void)h;(void)i; return 0; }
uint64_t spike_get_insn(int h){ (void)h; return 0; }
int      spike_get_rd(int h)  { (void)h; return 0; }
int      spike_trapped(int h) { (void)h; return 0; }
void     spike_set_mip(int h, int a, int b) { (void)h;(void)a;(void)b; }
