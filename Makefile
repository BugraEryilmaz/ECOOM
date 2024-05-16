.DEFAULT_GOAL := all
BUILD_DIR=build
OBJ_DIR=obj
INFO_DIR=info
INCLUDE_DIR=src/cache:src/core
BINARY_NAME=ecoom
BSC_FLAGS=--aggressive-conditions --show-schedule -sched-dot -remove-dollar -p +:$(INCLUDE_DIR) -vdir $(BUILD_DIR) -simdir $(BUILD_DIR)  -bdir $(OBJ_DIR) -info-dir $(INFO_DIR) -o 

.PHONY: clean all verilog $(BINARY_NAME)

$(BINARY_NAME):
	mkdir -p $(BUILD_DIR)
	bsc $(BSC_FLAGS) $@ -sim -g mk$@ -u $@.bsv
	bsc $(BSC_FLAGS) $@ -sim -e mk$@

verilog:
	mkdir -p $(BUILD_DIR)
	mkdir -p $(OBJ_DIR)
	mkdir -p $(INFO_DIR)
	bsc $(BSC_FLAGS) $(BINARY_NAME) -verilog -g mk$(BINARY_NAME)Sized -u ./src/core/$(BINARY_NAME).bsv

clean:
	find . -name "*.so" -type f -delete
	find . -name "*.sched" -type f -delete
	find . -name "*.dot" -type f -delete
	find . -name "*.bo" -type f -delete
	find . -name "*.ba" -type f -delete

all: clean verilog $(BINARY_NAME)
