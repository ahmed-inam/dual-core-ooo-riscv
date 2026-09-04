// vt_ilp.c -- ILP-RICH: 8 INDEPENDENT accumulator chains (each of a..h depends
int main(void) {
  volatile unsigned trip = 20000u;
  unsigned n = trip;
  unsigned a=1,b=2,c=3,d=4,e=5,f=6,g=7,h=8;
  for (unsigned i = 0; i < n; i++) {
    a += i*3u;  b += i*5u;  c += i*7u;  d += i*9u;
    e += i*11u; f += i*13u; g += i*15u; h += i*17u;
  }
  return (a+b+c+d+e+f+g+h) == 3114298148u ? 0 : 1;
}
