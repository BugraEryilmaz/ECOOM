.DEFAULT_GOAL := all
BUILD_DIR=build
BINARY_NAME=ecoom
BSC_FLAGS=--aggressive-conditions --show-schedule -remove-dollar -p +:src/cache:src/core -vdir $(BUILD_DIR) -bdir $(BUILD_DIR) -simdir $(BUILD_DIR) -info-dir $(BUILD_DIR) -o 

.PHONY: clean all verilog $(BINARY_NAME)

$(BINARY_NAME):
	mkdir -p $(BUILD_DIR)
	bsc $(BSC_FLAGS) $@ -sim -g mk$@ -u $@.bsv
	bsc $(BSC_FLAGS) $@ -sim -e mk$@

verilog:
	mkdir -p $(BUILD_DIR)
	bsc $(BSC_FLAGS) $(BINARY_NAME) -verilog -g mk$(BINARY_NAME)Sized -u ./src/core/$(BINARY_NAME).bsv

clean:
	find . -name "*.so" -type f -delete
	find . -name "*.sched" -type f -delete
	find . -name "*.bo" -type f -delete
	find . -name "*.ba" -type f -delete

all: clean verilog $(BINARY_NAME)
