// Dual-hart smoke test: both harts run and report through tohost.
int main(int hartid)
{
    volatile unsigned acc = 0;
    unsigned base = (unsigned)hartid * 100u;
    for (unsigned i = 1; i <= 10; i++) acc += base + i;
    unsigned expect = base * 10u + 55u;
    return (acc == expect) ? 0 : (hartid + 1);
}
