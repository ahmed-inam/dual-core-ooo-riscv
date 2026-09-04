# Toolchain only. The project is mounted at /work at run time.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Not nproc: the limit is RAM per g++ (~1 GB each), not cores. 16 GB host -> JOBS=8.
ARG JOBS=4
ENV JOBS=${JOBS}

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      verilator \
      gcc-riscv64-unknown-elf \
      device-tree-compiler \
      build-essential g++ make autoconf automake libtool pkg-config \
      help2man flex bison libfl-dev zlib1g-dev \
      libboost-regex-dev libboost-system-dev \
      python3 python3-pip python3-venv \
      git ca-certificates curl wget xz-utils \
      bc time file less vim-tiny \
      ccache \
 && rm -rf /var/lib/apt/lists/*

RUN cd /tmp \
 && git clone --depth 1 --branch v5.050 -q https://github.com/verilator/verilator.git verilator-src \
 && cd verilator-src \
 && autoconf \
 && ./configure --prefix=/opt/verilator-5.050 \
 && make -j"${JOBS}" \
 && make install \
 && cd /tmp && rm -rf /tmp/verilator-src \
 && /opt/verilator-5.050/bin/verilator --version

RUN cd /opt \
 && git init -q uvm && cd uvm \
 && git remote add origin https://github.com/chipsalliance/uvm-verilator.git \
 && (git fetch --depth 1 -q origin 656f20d087370a7c742e00188d20bbf30fa95339 \
     && git checkout -q FETCH_HEAD \
     || { echo "!! pinned UVM SHA unreachable -- falling back to tip"; \
          git fetch --depth 1 -q origin HEAD && git checkout -q FETCH_HEAD; }) \
 && test -f /opt/uvm/src/uvm_pkg.sv \
 && test -f /opt/uvm/src/uvm_macros.svh \
 && test -f /opt/uvm/src/dpi/uvm_hdl_verilator.c \
 && git log -1 --format="uvm (vlt)  pinned at %h %ad %s" --date=short \
 && cd /opt \
 && git init -q uvm-accellera && cd uvm-accellera \
 && git remote add origin https://github.com/accellera-official/uvm-core.git \
 && (git fetch --depth 1 -q origin 78c06547a2a0a29b3dc9dcafae62b75b2ff61544 \
     && git checkout -q FETCH_HEAD \
     || echo "!! pinned Accellera SHA unreachable -- pure-upstream fallback unavailable") \
 && test -f /opt/uvm-accellera/src/uvm_pkg.sv \
 && git log -1 --format="uvm (accellera 2020.3.1) pinned at %h %ad" --date=short

ARG SPIKE_SHA=4ffd6ba860f4190ceac2716fa3c2cf139e85538f
RUN mkdir -p /opt/refs && cd /opt/refs \
 && git init -q riscv-isa-sim && cd riscv-isa-sim \
 && git remote add origin https://github.com/riscv-software-src/riscv-isa-sim.git \
 && git fetch --depth 1 -q origin "${SPIKE_SHA}" && git checkout -q FETCH_HEAD \
 && mkdir -p build && cd build \
 && ../configure --prefix=/opt/spike CXXFLAGS="-include cstdint" \
 && make -j"${JOBS}" \
 && make install \
 && rm -f /opt/spike/bin/xspike /opt/spike/bin/termios-xspike /opt/spike/bin/spike-log-parser \
 && strip /opt/spike/bin/* /opt/spike/lib/*.so* 2>/dev/null || true \
 && rm -rf /opt/refs/riscv-isa-sim/build \
 && /opt/spike/bin/spike --help > /tmp/sk.txt 2>&1 || true
RUN head -1 /tmp/sk.txt && rm -f /tmp/sk.txt \
 && test -x /opt/spike/bin/spike \
 && echo "spike installed OK"

COPY gates/clone_refs.sh /tmp/clone_refs.sh
RUN chmod +x /tmp/clone_refs.sh && /tmp/clone_refs.sh && rm -f /tmp/clone_refs.sh

RUN pip3 install --break-system-packages --no-cache-dir -q PyYAML bitstring \
 && python3 -c "import yaml, bitstring; print('python deps OK')"

COPY gates/ /opt/gates/
RUN chmod +x /opt/gates/*.sh /opt/gates/uvmv \
 && ln -sf /opt/gates/uvmv /usr/local/bin/uvmv \
 && cd /opt/gates \
 && (./run_gates.sh --build-only 2>&1 | tee /opt/gates/build_report.txt) || true

# Verilator routes compiles through ccache. Mount /ccache as a named volume: a
# no-change rebuild is 27 minutes without it and 23 seconds with it.
ENV OBJCACHE=ccache
ENV CCACHE_DIR=/ccache
ENV CCACHE_MAXSIZE=5G
RUN mkdir -p /ccache && chmod 777 /ccache

ENV PATH=/opt/verilator-5.050/bin:/opt/spike/bin:$PATH
ENV PIP_FIND_LINKS=/opt/pipcache
ENV UVM_HOME=/opt/uvm
ENV RISCV_REFS=/opt/refs

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends z3 \
 && z3 --version \
 && rm -rf /var/lib/apt/lists/*

ENV LD_LIBRARY_PATH=/opt/spike/lib

WORKDIR /work

CMD ["/bin/bash"]
