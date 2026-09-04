// The C++ half of ref_spike: the eight DPI-C functions, backed by Spike.
// The C++ half of ref_spike: the eight DPI-C functions, backed by Spike.

#include <svdpi.h>

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <memory>
#include <optional>
#include <tuple>

#include "cfg.h"
#include "sim.h"
#include "processor.h"
#include "mmu.h"
#include "devices.h"
#include "debug_module.h"

namespace {

struct hart_view_t {
  uint64_t pc      = 0;
  uint64_t insn    = 0;
  int      rd      = 0;
  uint64_t rd_val  = 0;
  bool     trapped = false;

  uint64_t pc_wdata = 0;

  bool     mem_r_valid = false;
  uint64_t mem_r_addr  = 0;
  uint32_t mem_r_len   = 0;
  uint64_t mem_r_data  = 0;
  bool     mem_r_data_ok = false;

  bool     mem_w_valid = false;
  uint64_t mem_w_addr  = 0;
  uint32_t mem_w_len   = 0;
  uint64_t mem_w_data  = 0;

  int      mem_extra   = 0;
};

sim_t*                    g_sim = nullptr;
cfg_t*                    g_cfg = nullptr;
std::vector<hart_view_t>  g_view;
size_t                    g_nharts = 0;

std::vector<std::pair<reg_t, abstract_mem_t*>> g_mems;

processor_t* core(int hart) {
  if (!g_sim || hart < 0 || (size_t)hart >= g_nharts) return nullptr;
  return g_sim->get_core((size_t)hart);
}

void capture_mem_access(processor_t* p, state_t* st, hart_view_t& v)
{
  (void)p;

  const uint64_t XMASK = 0xFFFFFFFFULL;

  for (const auto& e : st->log_mem_read) {
    if (!v.mem_r_valid) {
      v.mem_r_valid = true;
      v.mem_r_addr  = (uint64_t)std::get<0>(e) & XMASK;
      v.mem_r_len   = (uint32_t)std::get<2>(e);
    } else {
      v.mem_extra++;
    }
  }

  for (const auto& e : st->log_mem_write) {
    if (!v.mem_w_valid) {
      v.mem_w_valid = true;
      v.mem_w_addr  = (uint64_t)std::get<0>(e) & XMASK;
      v.mem_w_data  = (uint64_t)std::get<1>(e);
      v.mem_w_len   = (uint32_t)std::get<2>(e);
    } else {
      v.mem_extra++;
    }
  }

  if (v.mem_r_valid && g_sim) {
    const uint64_t word_addr = v.mem_r_addr & ~(uint64_t)3;
    simif_t* si = g_sim;
    char* host = si->addr_to_mem((reg_t)word_addr);
    if (host) {
      uint32_t w = 0;
      std::memcpy(&w, host, sizeof(w));
      v.mem_r_data    = (uint64_t)w;
      v.mem_r_data_ok = true;
    }
  }
}

} // namespace

extern "C" {

int spike_open(const char* image_path, const char* isa, int n_harts,
               unsigned long long reset_pc)
{
  if (g_sim) { std::fprintf(stderr, "spike_dpi: already open\n"); return 0; }
  if (!image_path || !*image_path) {
    std::fprintf(stderr, "spike_dpi: empty image path\n");
    return 0;
  }

  g_nharts = (size_t)n_harts;
  g_cfg    = new cfg_t();

  g_cfg->isa  = isa;
  g_cfg->priv = "M";                     // machine mode only, matching the DUT

  g_cfg->hartids.clear();
  for (int i = 0; i < n_harts; i++) g_cfg->hartids.push_back((size_t)i);
  g_cfg->explicit_hartids = true;

  g_cfg->start_pc.set_global((reg_t)reset_pc);

  g_cfg->mem_layout.clear();
  g_cfg->mem_layout.push_back(mem_cfg_t(0x80000000ULL, 0x10000000ULL));

  g_mems.clear();
  for (const auto& m : g_cfg->mem_layout)
    g_mems.push_back({m.get_base(), new mem_t(m.get_size())});

  {
    FILE* f = std::fopen(image_path, "rb");
    if (!f) { std::fprintf(stderr, "spike_dpi: cannot open '%s'\n", image_path); return 0; }
    unsigned char magic[4] = {0,0,0,0};
    size_t got = std::fread(magic, 1, 4, f);
    std::fclose(f);
    if (got != 4 || magic[0] != 0x7f || magic[1] != 'E' || magic[2] != 'L' || magic[3] != 'F') {
      std::fprintf(stderr,
        "spike_dpi: '%s' is not an ELF. The reference model needs the ELF "
        "(+ELF=), not the Verilog hex the memory model loads (+HEX=).\n", image_path);
      return 0;
    }
  }

  std::vector<std::string> args;
  args.push_back(std::string(image_path));   // htif loads args[0] as the program

  debug_module_config_t dm_config;

  try {
    g_sim = new sim_t(
      g_cfg,
      /*halted*/                false,
      g_mems,
      /*plugin_device_factories*/ std::vector<device_factory_sargs_t>(),
      /*dtb_discovery*/         false,
      args,
      dm_config,
      /*log_path*/              nullptr,
      /*dtb_enabled*/           false,
      /*dtb_file*/              nullptr,
      /*socket_enabled*/        false,
      /*cmd_file*/              nullptr,
      /*instruction_limit*/     std::nullopt);
  } catch (const std::exception& e) {
    std::fprintf(stderr, "spike_dpi: sim_t construction failed: %s\n", e.what());
    return 0;
  }

  try {
    g_sim->start();
  } catch (const std::exception& e) {
    std::fprintf(stderr, "spike_dpi: failed to load '%s': %s\n", image_path, e.what());
    delete g_sim; g_sim = nullptr;
    return 0;
  }

  g_sim->configure_log(/*enable_log*/ false, /*enable_commitlog*/ true);
  for (size_t i = 0; i < g_nharts; i++)
    g_sim->get_core(i)->enable_log_commits();

  g_view.assign(g_nharts, hart_view_t());
  return 1;
}

void spike_close()
{
  delete g_sim; g_sim = nullptr;
  delete g_cfg; g_cfg = nullptr;
  g_mems.clear();
  g_view.clear();
  g_nharts = 0;
}

int spike_step(int hart)
{
  processor_t* p = core(hart);
  if (!p) return 0;

  state_t* st = p->get_state();
  hart_view_t& v = g_view[(size_t)hart];

  const bool was_waiting = p->is_waiting_for_interrupt();

  v.pc      = st->pc;
  v.rd      = 0;
  v.rd_val  = 0;
  v.trapped = false;
  v.mem_r_valid = false; v.mem_r_addr = 0; v.mem_r_len = 0;
  v.mem_r_data  = 0;     v.mem_r_data_ok = false;
  v.mem_w_valid = false; v.mem_w_addr = 0; v.mem_w_len = 0; v.mem_w_data = 0;
  v.mem_extra   = 0;
  v.pc_wdata    = 0;

  try {
    insn_fetch_t fetch = p->get_mmu()->load_insn(st->pc);
    v.insn = (uint64_t)fetch.insn.bits() & 0xFFFFFFFFULL;
  } catch (...) {
    v.insn = 0;
  }

  st->log_reg_write.clear();
  st->log_mem_read.clear();
  st->log_mem_write.clear();

  const uint64_t pc_before = st->pc;
  try {
    p->step(1);
  } catch (const std::exception& e) {
    std::fprintf(stderr, "spike_dpi: hart %d threw at pc=%08llx: %s\n",
                 hart, (unsigned long long)pc_before, e.what());
    return 0;
  }

  if (was_waiting && p->is_waiting_for_interrupt()) return 0;

  v.trapped = (st->pc != pc_before) && (st->pc == st->mtvec->read());

  for (const auto& kv : st->log_reg_write) {
    const reg_t key  = kv.first;
    const int   type = (int)(key & 0xf);
    const int   num  = (int)(key >> 4);
    if (type == 0 && num != 0) {
      v.rd     = num;
      v.rd_val = (uint64_t)kv.second.v[0];
      break;
    }
  }

  capture_mem_access(p, st, v);

  v.pc_wdata = (uint64_t)st->pc;

  return 1;
}

unsigned long long spike_get_pc(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return (unsigned long long)g_view[(size_t)hart].pc;
}

unsigned long long spike_get_insn(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return (unsigned long long)g_view[(size_t)hart].insn;
}

int spike_get_rd(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return g_view[(size_t)hart].rd;
}

int spike_trapped(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return g_view[(size_t)hart].trapped ? 1 : 0;
}

unsigned long long spike_get_reg(int hart, int idx)
{
  processor_t* p = core(hart);
  if (!p || idx <= 0 || idx >= NXPR) return 0;
  return (unsigned long long)p->get_state()->XPR[idx];
}

unsigned long long spike_get_pc_wdata(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return (unsigned long long)g_view[(size_t)hart].pc_wdata;
}

int spike_mem_r_valid(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return g_view[(size_t)hart].mem_r_valid ? 1 : 0;
}

unsigned long long spike_mem_r_addr(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return (unsigned long long)g_view[(size_t)hart].mem_r_addr;
}

int spike_mem_r_len(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return (int)g_view[(size_t)hart].mem_r_len;
}

int spike_mem_r_data_ok(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return g_view[(size_t)hart].mem_r_data_ok ? 1 : 0;
}

unsigned long long spike_mem_r_data(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return (unsigned long long)g_view[(size_t)hart].mem_r_data;
}

int spike_mem_w_valid(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return g_view[(size_t)hart].mem_w_valid ? 1 : 0;
}

unsigned long long spike_mem_w_addr(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return (unsigned long long)g_view[(size_t)hart].mem_w_addr;
}

int spike_mem_w_len(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return (int)g_view[(size_t)hart].mem_w_len;
}

unsigned long long spike_mem_w_data(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return (unsigned long long)g_view[(size_t)hart].mem_w_data;
}

int spike_mem_extra(int hart)
{
  if (hart < 0 || (size_t)hart >= g_view.size()) return 0;
  return g_view[(size_t)hart].mem_extra;
}

void spike_set_mip(int hart, int msip, int mtip)
{
  processor_t* p = core(hart);
  if (!p) return;

  const reg_t mask = MIP_MSIP | MIP_MTIP;
  reg_t       set  = 0;
  if (msip) set |= MIP_MSIP;
  if (mtip) set |= MIP_MTIP;

  p->get_state()->mip->backdoor_write_with_mask(mask, set);
}

void spike_break_reservation(int hart)
{
  processor_t* p = core(hart);
  if (!p) return;
  p->get_mmu()->yield_load_reservation();
}

void spike_set_reg(int hart, int idx, unsigned long long value)
{
  processor_t* p = core(hart);
  if (!p || idx <= 0 || idx >= NXPR) return;
  p->get_state()->XPR.write((size_t)idx, (reg_t)value);
}

} // extern "C"
