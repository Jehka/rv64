# RV64 Single-Cycle Processor + AI Design-Space Analysis

A 64-bit single-cycle RISC-V processor (RV64I subset, 30 instructions) in Verilog. It is verified in Icarus Verilog and Vivado XSim, and implemented on a Zynq-7020 (ZedBoard) across an 18-run design-space sweep. Machine-learning models trained on the sweep predict Fmax, power and area for operating points that were never run.

![Verilog](https://img.shields.io/badge/HDL-Verilog--2005-blue)
![Vivado](https://img.shields.io/badge/Vivado-2025.2-orange)
![Device](https://img.shields.io/badge/device-xc7z020clg484--1-lightgrey)
![Tests](https://img.shields.io/badge/self--check-31%2F31%20pass-brightgreen)

**Full design report:** [docs/REPORT.md](docs/REPORT.md) · [PDF](docs/REPORT.pdf)

---

## Results at a glance

| | |
|---|---|
| ISA | RV64I subset: arithmetic, logical, 64-bit shifts, `ld`/`sd`, 6 branches, `jal`/`jalr`, `lui` |
| Verification | 36-instruction program, **31/31 checks pass** in Icarus and XSim, 49 cycles, CPI = 1 |
| Timing | closes at **50 MHz** with every directive; best measured period **15.88 ns (63.0 MHz)** |
| Recommended point | `AreaOptimized_high` @ 16.5 ns (**60.6 MHz**, 0.200 W, 3.30 nJ/instruction), model-predicted |
| Area @ 50 MHz | 3067 LUTs (432 as LUTRAM), 2048 FFs, 0 BRAM, 0 DSP |
| Power model | P = P<sub>static</sub> + k·f, R² ≥ 0.994; `AreaOptimized_high` has a 15 % lower dynamic slope |
| Model accuracy (leave-one-out) | Fmax ±0.76 MHz (1.3 %) · power ±2.3 mW (1.0 %) · LUTs ±5.5 (0.2 %) |

The key finding is that the critical path in all 18 runs is the full fetch → decode → execute → memory → writeback loop. It is **74–84 % routing**, and the 64-bit carry chain is not the limiter ([report §5.3](docs/REPORT.md#53-the-critical-path)).

---

## Architecture

```
 pc_unit ─▶ imem (256×32) ─▶ control ─▶ datapath control signals
                │
                ├─▶ regfile_64 (32×64, 2R/1W) ─▶ alu_64 ─▶ dmem (256×64)
                └─▶ imm_gen (I/S/B/U/J)  ─────────┘            │
                          ▲                                    │
                          └──── writeback: ALU | MEM | PC+4 | imm
```

| Module | Role |
|---|---|
| [`rtl/alu_64.v`](rtl/alu_64.v) | 64-bit ALU: add, sub, and, or, xor, slt, sltu, sll, srl, sra |
| [`rtl/regfile_64.v`](rtl/regfile_64.v) | 32 × 64 register file, 2 async reads, 1 sync write, `x0` = 0 |
| [`rtl/pc_unit.v`](rtl/pc_unit.v) | PC register and next-PC select (PC+4 / branch / `jal` / `jalr`) |
| [`rtl/imem.v`](rtl/imem.v) | 256 × 32 instruction memory with a program-loader port ([why](docs/REPORT.md#3-four-things-worth-knowing-for-the-viva)) |
| [`rtl/control.v`](rtl/control.v) | main decoder + ALU decoder |
| [`rtl/imm_gen.v`](rtl/imm_gen.v) | immediate generation and sign extension |
| [`rtl/branch_unit.v`](rtl/branch_unit.v) | beq/bne/blt/bge/bltu/bgeu comparator |
| [`rtl/dmem.v`](rtl/dmem.v) | 256 × 64 data memory |
| [`rtl/rv64_top.v`](rtl/rv64_top.v) | datapath integration |

Supported instructions: `add sub and or xor slt sltu sll srl sra` · `addi slti sltiu andi ori xori slli srli srai` · `ld sd` · `beq bne blt bge bltu bgeu` · `jal jalr` · `lui`

---

## Quick start

```bash
make sim          # Icarus Verilog, self-checking -> sim/icarus.log, sim/rv64.vcd
make wave         # GTKWave
make xsim         # Vivado XSim (batch)
```

Expected tail of the output ([full log](sim/xsim.log)):

```
Halted at PC=000000000000008c after 49 cycles
...
*** ALL TESTS PASSED ***  (0 errors)
```

To change the test program, edit [`sw/assemble.py`](sw/assemble.py) and run `make asm`.

## Reproducing the analysis

```bash
make venv          # Python env: pandas, numpy, scikit-learn, matplotlib, tabulate
make sweep-quick   # 2-run smoke test (~5 min)
make sweep         # 18 runs: 6 clock targets x 3 synthesis directives
make analyze       # models + plots -> sweep/analysis_report.md, sweep/plots/
```

[`sweep.tcl`](sweep.tcl) runs out-of-context synth → place → phys_opt → route for each point and records timing, utilisation and power ([results.csv](sweep/results.csv), [per-run reports](sweep/reports/)). [`analyze.py`](analyze.py) then:

- trains ridge, random-forest and gradient-boosting regressors and selects the best by leave-one-out cross-validation;
- fits a physics-informed power model;
- ranks knobs by permutation importance;
- predicts the full design space and recommends operating points ([analysis report](sweep/analysis_report.md)).

<p>
<img src="sweep/plots/fmax_vs_target.png" width="49%">
<img src="sweep/plots/power_vs_freq.png" width="49%">
</p>

---

## Repository layout

```
rtl/        processor RTL (9 modules)
tb/         self-checking testbench
sw/         RV64I test-program assembler
sim/        simulation logs (Icarus, XSim) + VCD
sweep/      design-space sweep: results, models, plots, Vivado reports
docs/       design report (MD + PDF) and figures
run_sim.tcl Vivado XSim project + behavioral simulation
sweep.tcl   Vivado implementation sweep
analyze.py  AI design-parameter analysis
```

---

## Context and related work

This was built for **PBL-2, FPGA and SoC Design (Semester VII, B.Tech ECE, UPES)**. It is designed as a stepping stone rather than a one-off assignment:

- **Previous:** [AI-assisted 64×16 memory system](https://github.com/Jehka/ai_memory_pbl1) (PBL-1). It is a stride prefetcher with an online-trained hardware perceptron gate on the same device and flow. This project builds the compute side that such a memory serves.
- **Next:** the 5-stage pipelined RISC-V core in the **MINERVA SoC** project. It starts from this datapath and cuts it at the stage boundaries measured in [§5.3](docs/REPORT.md#53-the-critical-path), with registered memory outputs so they map to block RAM ([§5.5](docs/REPORT.md#55-area)).
- **Related, AI for EDA:** [RTLForge](https://github.com/Jehka/rtlforge) is an agentic pipeline that generates, verifies and repairs Verilog RTL. The sweep-and-surrogate-model approach here is the same idea applied to implementation rather than generation.

## Limitations

RV64I subset, not the full ISA (no byte/half/word memory ops, no `*W` ops, no `auipc`). Power is Vivado's vectorless estimate. The 16.5 ns recommendation is a model prediction pending a confirmation run. The design is out-of-context only, with no board bring-up. Details are in [report §5.7](docs/REPORT.md#57-limitations).

---

**Jehkaran Singh** · [github.com/Jehka](https://github.com/Jehka) · MIT License
