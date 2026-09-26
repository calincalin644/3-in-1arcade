NAME := tt_um_breakout
YOSYS ?= yosys
NEXTPNR ?= nextpnr-ice40
ICEPACK ?= icepack
IVERILOG ?= iverilog
VVP ?= vvp
MPREMOTE ?= mpremote
PORT ?= /dev/ttyACM0

.PHONY: all test upload
all: build/$(NAME).bin
build:
	mkdir -p build
build/$(NAME).json: src/$(NAME).v fpga/top.v | build
	$(YOSYS) -Q -l build/synthesis.log -p 'read_verilog -sv $^; synth_ice40 -top top -json $@'
build/$(NAME).asc: build/$(NAME).json fpga/fabricfox.pcf
	$(NEXTPNR) --up5k --package sg48 --freq 25.2 --seed 10 --pcf fpga/fabricfox.pcf --json $< --asc $@ --log build/nextpnr.log
build/$(NAME).bin: build/$(NAME).asc
	$(ICEPACK) $< $@
test: | build
	$(IVERILOG) -g2012 -s unit -o build/unit test/unit.v src/$(NAME).v
	$(VVP) build/unit
	$(MAKE) -C test
upload: all
	$(MPREMOTE) connect $(PORT) fs cp build/$(NAME).bin :/bitstreams/$(NAME).bin
	$(MPREMOTE) connect $(PORT) run scripts/run_game.py
