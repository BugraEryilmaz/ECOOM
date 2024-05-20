.DEFAULT_GOAL := all
SIM_DIR=sim
BUILD_DIR=build
OBJ_DIR=obj
INFO_DIR=info
INCLUDE_DIR=src/cache:src/core:src/utils:test
BINARY_NAME=top_pipelined
BSC_FLAGS=--aggressive-conditions +RTS -K32M -RTS --show-schedule -sched-dot -p +:$(INCLUDE_DIR) -vdir $(BUILD_DIR) -simdir $(BUILD_DIR)  -bdir $(OBJ_DIR) -info-dir $(INFO_DIR) -o 
BSC_FLAGS_TEST=--aggressive-conditions --show-schedule -sched-dot -p +:$(INCLUDE_DIR) -vdir $(BUILD_DIR) -simdir $(BUILD_DIR)  -bdir $(OBJ_DIR) -info-dir $(INFO_DIR) -o 

.PHONY: clean all verilog test $(BINARY_NAME)

$(BINARY_NAME):
	mkdir -p $(BUILD_DIR)
	mkdir -p $(OBJ_DIR)
	mkdir -p $(INFO_DIR)
	mkdir -p $(SIM_DIR)
	bsc $(BSC_FLAGS) $@ -sim -g mk$@ -u ./src/core/$@.bsv
	bsc $(BSC_FLAGS) $@ -sim -e mk$@

verilog:
	mkdir -p $(BUILD_DIR)
	mkdir -p $(OBJ_DIR)
	mkdir -p $(INFO_DIR)
	bsc -remove-dollar $(BSC_FLAGS)  $(BINARY_NAME) -verilog -g mk$(BINARY_NAME)Sized -u ./src/core/$(BINARY_NAME).bsv

test:
	mkdir -p $(BUILD_DIR)
	mkdir -p $(OBJ_DIR)
	mkdir -p $(INFO_DIR)
	mkdir -p $(SIM_DIR)
	bsc $(BSC_FLAGS_TEST) sim/$(BINARY_NAME) -sim -g mk$(BINARY_NAME)TB -u ./test/$(BINARY_NAME)TB.bsv
	bsc $(BSC_FLAGS_TEST) sim/$(BINARY_NAME) -sim -e mk$(BINARY_NAME)TB

clean:
	rm -rf info
	rm -rf obj
	rm -f *.log

all: clean $(BINARY_NAME)
