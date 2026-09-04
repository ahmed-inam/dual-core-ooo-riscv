// Two harts sharing one line: the coherence workload.
volatile unsigned shared_payload;
volatile unsigned shared_flag;

int main(int hartid)
{
    if (hartid == 1) {
        shared_payload = 0xABCD1234u;
        shared_flag    = 1u;              /* no fence, on purpose */
        return 0;
    }
    for (unsigned i = 0; i < 2000000u; i++) {
        if (shared_flag == 1u)
            return (shared_payload == 0xABCD1234u) ? 0 : 2;
    }
    return 3;                              /* never saw the flag */
}
