# PBL-2 RV64 single-cycle processor
#   make sim          Icarus Verilog simulation (self-checking)  -> sim/icarus.log, sim/rv64.vcd
#   make xsim         Vivado XSim behavioral simulation           -> vivado/.../simulate.log
#   make wave         open the VCD in GTKWave
#   make asm          re-assemble the test program (sw/assemble.py -> program.hex)
#   make sweep-quick  2-run Vivado smoke test of the design-space sweep
#   make sweep        full 18-run sweep (6 clock targets x 3 synth directives) -> sweep/results.csv
#   make analyze      train the delay/power/area models, write sweep/analysis_report.md + plots
#   make clean        remove simulator / Vivado scratch output

PY := $(shell [ -x .venv/bin/python ] && echo .venv/bin/python || echo python3)
RTL := $(wildcard rtl/*.v)

.PHONY: sim xsim wave asm sweep sweep-quick analyze venv clean

sim: $(RTL) tb/tb_rv64.v program.hex
	@mkdir -p sim
	iverilog -g2012 -Wall -o sim/rv64.out tb/tb_rv64.v $(RTL)
	vvp -n sim/rv64.out | tee sim/icarus.log
	@mv -f rv64.vcd sim/rv64.vcd

xsim:
	vivado -mode batch -source run_sim.tcl -nojournal -log sim/xsim_vivado.log

wave:
	gtkwave sim/rv64.vcd

asm:
	cd sw && python3 assemble.py && cp program.hex ..

sweep-quick:
	vivado -mode batch -source sweep.tcl -nojournal -log sweep/vivado_sweep.log -tclargs quick

sweep:
	vivado -mode batch -source sweep.tcl -nojournal -log sweep/vivado_sweep.log

venv:
	python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

analyze:
	$(PY) analyze.py sweep/results.csv

clean:
	rm -rf sim/rv64.out rv64.vcd vivado .Xil *.jou *.log *.str xvlog.pb clockInfo.txt
