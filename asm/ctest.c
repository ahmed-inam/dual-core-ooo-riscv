// Self-checking: every phase verifies its own result by an independent

typedef unsigned int u32;

#define FAIL(n) return (n)

void *memcpy(void *d, const void *s, unsigned n) {
  char *dp = d; const char *sp = s;
  while (n--) *dp++ = *sp++;
  return d;
}
void *memset(void *d, int c, unsigned n) {
  char *dp = d;
  while (n--) *dp++ = (char)c;
  return d;
}

static u32 soft_mul(u32 a, u32 b) {
  u32 r = 0;
  while (b) {
    if (b & 1u) r += a;
    a <<= 1;
    b >>= 1;
  }
  return r;
}
static u32 soft_divu(u32 a, u32 b, u32 *rem) {
  u32 q = 0, r = 0;
  if (b == 0) { *rem = a; return 0xFFFFFFFFu; }
  for (int i = 31; i >= 0; i--) {
    r = (r << 1) | ((a >> i) & 1u);
    if (r >= b) { r -= b; q |= (1u << i); }
  }
  *rem = r;
  return q;
}

static u32 fib_rec(u32 n) {
  return (n < 2) ? n : fib_rec(n - 1) + fib_rec(n - 2);
}

static u32 fib_iter(u32 n) {
  u32 a = 0, b = 1;
  while (n--) { u32 t = a + b; a = b; b = t; }
  return a;
}

static void qsort_u32(u32 *a, int lo, int hi) {
  if (lo >= hi) return;
  u32 p = a[(lo + hi) >> 1];
  int i = lo, j = hi;
  while (i <= j) {
    while (a[i] < p) i++;
    while (a[j] > p) j--;
    if (i <= j) { u32 t = a[i]; a[i] = a[j]; a[j] = t; i++; j--; }
  }
  qsort_u32(a, lo, j);
  qsort_u32(a, i, hi);
}

struct node { u32 val; struct node *next; };

int main(void) {
  if (fib_rec(15) != 610) FAIL(1);
  if (fib_rec(15) != fib_iter(15)) FAIL(2);

  static u32 arr[64];
  u32 seed = 0xdeadbeefu, sum_before = 0;
  for (int i = 0; i < 64; i++) {
    seed = seed * 1664525u + 1013904223u;      /* __mulsi3 */
    arr[i] = seed;
    sum_before += seed;
  }
  qsort_u32(arr, 0, 63);
  u32 sum_after = 0;
  for (int i = 0; i < 64; i++) {
    if (i && arr[i - 1] > arr[i]) FAIL(3);     /* sortedness   */
    sum_after += arr[i];
  }
  if (sum_after != sum_before) FAIL(4);        /* permutation  */

  char s[16];
  for (int i = 0; i < 12; i++) s[i] = (char)('a' + i);
  s[12] = 0;
  for (int i = 0, j = 11; i < j; i++, j--) { char t = s[i]; s[i] = s[j]; s[j] = t; }
  const char *exp = "lkjihgfedcba";
  for (int i = 0; i < 13; i++) if (s[i] != exp[i]) FAIL(5);

  static struct node pool[16];
  struct node *head = 0;
  u32 lsum = 0;
  for (int i = 0; i < 16; i++) {
    pool[i].val = arr[i << 2];                 /* stride through sorted data */
    pool[i].next = head;
    head = &pool[i];
    lsum += pool[i].val;
  }
  u32 wsum = 0;
  for (struct node *p = head; p; p = p->next) wsum += p->val;
  if (wsum != lsum) FAIL(6);

  for (u32 a = 0xfffffff0u; a > 0xffffff00u; a -= 13) {
    u32 b = (a & 0xffu) | 1u;                  /* odd, nonzero */
    u32 q = a / b, r = a % b;                  /* __udivsi3 / __umodsi3 */
    if (q * b + r != a || r >= b) FAIL(7);
  }

  u32 h1 = 2166136261u;
  for (int i = 0; i < 64; i++) {
    u32 v = arr[i];
    for (int k = 0; k < 4; k++) { h1 ^= v & 0xffu; h1 *= 16777619u; v >>= 8; }
  }
  u32 h2 = 2166136261u;
  const unsigned char *bytes = (const unsigned char *)arr;
  for (int i = 0; i < 256; i++) { h2 ^= bytes[i]; h2 *= 16777619u; }
  if (h1 != h2) FAIL(8);                       /* word-walk == byte-walk */

  {
    u32 s = 0xC0FFEE01u, r_soft, r_hw;
    for (int i = 0; i < 64; i++) {
      s = s * 1664525u + 1013904223u;          /* hw mul inside the LCG too */
      u32 x = s ^ (s >> 13);
      u32 y = (s >> 7) | 1u;                   /* nonzero divisor */
      if (x * y != soft_mul(x, y)) FAIL(9);    /* hw mul vs shift-add   */
      r_hw = x / y;
      if (r_hw != soft_divu(x, y, &r_soft)) FAIL(10);
      if (x % y != r_soft) FAIL(11);           /* hw rem vs soft rem    */
    }
    {
      u32 rr, q_hw, r_hw2;
      volatile u32 ca = 0xFFFFFFFFu, cb = 0xFFFFFFFFu;  /* defeat folding */
      if ((ca * cb) != soft_mul(0xFFFFFFFFu, 0xFFFFFFFFu)) FAIL(12);
      __asm__ volatile ("divu %0, %1, %2" : "=r"(q_hw)  : "r"(5u), "r"(0u));
      __asm__ volatile ("remu %0, %1, %2" : "=r"(r_hw2) : "r"(5u), "r"(0u));
      if (q_hw  != soft_divu(5u, 0, &rr)) FAIL(13);
      if (r_hw2 != rr) FAIL(14);
    }
  }

  return 0;
}
