PROJECT := caffe

# config ------------------------------------------

#USE_CUDNN := 1
CPU_ONLY := 1
# CUSTOM_CXX := g++
CUDA_DIR := /usr/local/cuda
BUILD_DIR := build
DISTRIBUTE_DIR := distribute
# DEBUG := 1
TEST_GPUID := 0
Q ?= @

# BLAS choice:
# mkl for MKL
# open for OpenBlas (default)
# eigen for eigen (in submodules/eigen)
BLAS := open

# CUDA architecture setting: going with all of them.
# For CUDA < 6.0, comment the *_50 lines for compatibility.
CUDA_ARCH := -gencode arch=compute_20,code=sm_20 \
		-gencode arch=compute_20,code=sm_21 \
		-gencode arch=compute_30,code=sm_30 \
		-gencode arch=compute_35,code=sm_35 \
		-gencode arch=compute_50,code=sm_50 \
		-gencode arch=compute_50,code=compute_50

INCLUDE_DIRS := /usr/local/include
LIBRARY_DIRS := /usr/local/lib /usr/lib
CXXFLAGS := -std=c++11
NVCCFLAGS := -std=c++11

# -------------------------------------------------

BUILD_DIR_LINK := $(BUILD_DIR)
ifeq ($(RELEASE_BUILD_DIR),)
	RELEASE_BUILD_DIR := .$(BUILD_DIR)_release
endif
ifeq ($(DEBUG_BUILD_DIR),)
	DEBUG_BUILD_DIR := .$(BUILD_DIR)_debug
endif

DEBUG ?= 0
ifeq ($(DEBUG), 1)
	BUILD_DIR := $(DEBUG_BUILD_DIR)
	OTHER_BUILD_DIR := $(RELEASE_BUILD_DIR)
else
	BUILD_DIR := $(RELEASE_BUILD_DIR)
	OTHER_BUILD_DIR := $(DEBUG_BUILD_DIR)
endif

# All of the directories containing code.
SRC_DIRS := $(shell find * -type d -exec bash -c "find {} -maxdepth 1 \
	\( -name '*.cpp' -o -name '*.proto' \) | grep -q ." \; -print)

# The target shared library name
LIBRARY_NAME := $(PROJECT)
LIB_BUILD_DIR := $(BUILD_DIR)/lib
STATIC_NAME := $(LIB_BUILD_DIR)/lib$(LIBRARY_NAME).a
DYNAMIC_VERSION_MAJOR 		:= 1
DYNAMIC_VERSION_MINOR 		:= 0
DYNAMIC_VERSION_REVISION 	:= 0-rc3
DYNAMIC_NAME_SHORT := lib$(LIBRARY_NAME).so
#DYNAMIC_SONAME_SHORT := $(DYNAMIC_NAME_SHORT).$(DYNAMIC_VERSION_MAJOR)
DYNAMIC_VERSIONED_NAME_SHORT := $(DYNAMIC_NAME_SHORT).$(DYNAMIC_VERSION_MAJOR).$(DYNAMIC_VERSION_MINOR).$(DYNAMIC_VERSION_REVISION)
DYNAMIC_NAME := $(LIB_BUILD_DIR)/$(DYNAMIC_VERSIONED_NAME_SHORT)
COMMON_FLAGS += -DCAFFE_VERSION=$(DYNAMIC_VERSION_MAJOR).$(DYNAMIC_VERSION_MINOR).$(DYNAMIC_VERSION_REVISION)

##############################
# Get all source files
##############################
# CXX_SRCS are the source files excluding the test ones.
CXX_SRCS := $(shell find src/$(PROJECT) ! -name "test_*.cpp" -name "*.cpp")
# CU_SRCS are the cuda source files
CU_SRCS := $(shell find src/$(PROJECT) ! -name "test_*.cu" -name "*.cu")
# TEST_SRCS are the test source files
TEST_MAIN_SRC := src/$(PROJECT)/test/test_caffe_main.cpp
TEST_SRCS := $(shell find src/$(PROJECT) -name "test_*.cpp")
TEST_SRCS := $(filter-out $(TEST_MAIN_SRC), $(TEST_SRCS))
TEST_CU_SRCS := $(shell find src/$(PROJECT) -name "test_*.cu")
GTEST_SRC := src/gtest/gtest-all.cpp
# BUILD_INCLUDE_DIR contains any generated header files we want to include.
BUILD_INCLUDE_DIR := $(BUILD_DIR)/src
# PROTO_SRCS are the protocol buffer definitions
PROTO_SRC_DIR := src/$(PROJECT)/proto
PROTO_SRCS := $(wildcard $(PROTO_SRC_DIR)/*.proto)
# PROTO_BUILD_DIR will contain the .cc and obj files generated from
# PROTO_SRCS; PROTO_BUILD_INCLUDE_DIR will contain the .h header files
PROTO_BUILD_DIR := $(BUILD_DIR)/$(PROTO_SRC_DIR)
PROTO_BUILD_INCLUDE_DIR := $(BUILD_INCLUDE_DIR)/$(PROJECT)/proto
# NONGEN_CXX_SRCS includes all source/header files except those generated
# automatically (e.g., by proto).
NONGEN_CXX_SRCS := $(shell find \
	src/$(PROJECT) \
	include/$(PROJECT) \
	-name "*.cpp" -or -name "*.hpp" -or -name "*.cu" -or -name "*.cuh")

##############################
# Derive generated files
##############################
# The generated files for protocol buffers
PROTO_GEN_HEADER_SRCS := $(addprefix $(PROTO_BUILD_DIR)/, \
		$(notdir ${PROTO_SRCS:.proto=.pb.h}))
PROTO_GEN_HEADER := $(addprefix $(PROTO_BUILD_INCLUDE_DIR)/, \
		$(notdir ${PROTO_SRCS:.proto=.pb.h}))
PROTO_GEN_CC := $(addprefix $(BUILD_DIR)/, ${PROTO_SRCS:.proto=.pb.cc})
# The objects corresponding to the source files
# These objects will be linked into the final shared library, so we
# exclude the test objects.
CXX_OBJS := $(addprefix $(BUILD_DIR)/, ${CXX_SRCS:.cpp=.o})
CU_OBJS := $(addprefix $(BUILD_DIR)/cuda/, ${CU_SRCS:.cu=.o})
PROTO_OBJS := ${PROTO_GEN_CC:.cc=.o}
OBJS := $(PROTO_OBJS) $(CXX_OBJS) $(CU_OBJS)
# test objects
TEST_CXX_BUILD_DIR := $(BUILD_DIR)/src/$(PROJECT)/test
TEST_CU_BUILD_DIR := $(BUILD_DIR)/cuda/src/$(PROJECT)/test
TEST_CXX_OBJS := $(addprefix $(BUILD_DIR)/, ${TEST_SRCS:.cpp=.o})
TEST_CU_OBJS := $(addprefix $(BUILD_DIR)/cuda/, ${TEST_CU_SRCS:.cu=.o})
TEST_OBJS := $(TEST_CXX_OBJS) $(TEST_CU_OBJS)
GTEST_OBJ := $(addprefix $(BUILD_DIR)/, ${GTEST_SRC:.cpp=.o})
# Output files for automatic dependency generation
DEPS := ${CXX_OBJS:.o=.d} ${CU_OBJS:.o=.d} ${TEST_CXX_OBJS:.o=.d} ${TEST_CU_OBJS:.o=.d}
# Put the test binaries in build/test for convenience.
TEST_BIN_DIR := $(BUILD_DIR)/test
TEST_CU_BINS := $(addsuffix .testbin,$(addprefix $(TEST_BIN_DIR)/, \
		$(foreach obj,$(TEST_CU_OBJS),$(basename $(notdir $(obj))))))
TEST_CXX_BINS := $(addsuffix .testbin,$(addprefix $(TEST_BIN_DIR)/, \
		$(foreach obj,$(TEST_CXX_OBJS),$(basename $(notdir $(obj))))))
TEST_BINS := $(TEST_CXX_BINS) $(TEST_CU_BINS)
# TEST_ALL_BIN is the test binary that links caffe dynamically.
TEST_ALL_BIN := $(TEST_BIN_DIR)/test_all.testbin

##############################
# Derive include and lib directories
##############################
CUDA_INCLUDE_DIR := $(CUDA_DIR)/include

CUDA_LIB_DIR :=
# add <cuda>/lib64 only if it exists
ifneq ("$(wildcard $(CUDA_DIR)/lib64)","")
	CUDA_LIB_DIR += $(CUDA_DIR)/lib64
endif
CUDA_LIB_DIR += $(CUDA_DIR)/lib

INCLUDE_DIRS += $(BUILD_INCLUDE_DIR) ./src ./include
ifneq ($(CPU_ONLY), 1)
	INCLUDE_DIRS += $(CUDA_INCLUDE_DIR)
	LIBRARY_DIRS += $(CUDA_LIB_DIR)
	LIBRARIES := cudart cublas curand
endif

LIBRARIES += glog protobuf
WARNINGS := -Wall -Wno-sign-compare

##############################
# Set build directories
##############################

DISTRIBUTE_DIR ?= distribute
DISTRIBUTE_SUBDIRS := $(DISTRIBUTE_DIR)/lib
DIST_ALIASES := dist
ifneq ($(strip $(DISTRIBUTE_DIR)),distribute)
		DIST_ALIASES += distribute
endif

ALL_BUILD_DIRS := $(sort $(BUILD_DIR) $(addprefix $(BUILD_DIR)/, $(SRC_DIRS)) \
	$(addprefix $(BUILD_DIR)/cuda/, $(SRC_DIRS)) \
	$(LIB_BUILD_DIR) $(TEST_BIN_DIR) $(DISTRIBUTE_SUBDIRS) $(PROTO_BUILD_INCLUDE_DIR))

##############################
# Configure build
##############################

# Determine platform
UNAME := $(shell uname -s)
ifeq ($(UNAME), Linux)
	LINUX := 1
else ifeq ($(UNAME), Darwin)
	OSX := 1
	OSX_MAJOR_VERSION := $(shell sw_vers -productVersion | cut -f 1 -d .)
	OSX_MINOR_VERSION := $(shell sw_vers -productVersion | cut -f 2 -d .)
endif

# Linux
ifeq ($(LINUX), 1)
	CXX ?= /usr/bin/g++
	GCCVERSION := $(shell $(CXX) -dumpversion | cut -f1,2 -d.)
	# older versions of gcc are too dumb to build boost with -Wuninitalized
	ifeq ($(shell echo | awk '{exit $(GCCVERSION) < 4.6;}'), 1)
		WARNINGS += -Wno-uninitialized
	endif
	LIBRARIES += stdc++
	VERSIONFLAGS += -Wl,-soname,$(DYNAMIC_VERSIONED_NAME_SHORT) -Wl,-rpath,$(ORIGIN)/../lib
endif

# OS X:
# clang++ instead of g++
# libstdc++ for NVCC compatibility on OS X >= 10.9 with CUDA < 7.0
ifeq ($(OSX), 1)
	CXX := /usr/bin/clang++
	ifneq ($(CPU_ONLY), 1)
		CUDA_VERSION := $(shell $(CUDA_DIR)/bin/nvcc -V | grep -o 'release [0-9.]*' | tr -d '[a-z ]')
		ifeq ($(shell echo | awk '{exit $(CUDA_VERSION) < 7.0;}'), 1)
			CXXFLAGS += -stdlib=libstdc++
			LINKFLAGS += -stdlib=libstdc++
		endif
		# clang throws this warning for cuda headers
		WARNINGS += -Wno-unneeded-internal-declaration
		# 10.11 strips DYLD_* env vars so link CUDA (rpath is available on 10.5+)
		OSX_10_OR_LATER   := $(shell [ $(OSX_MAJOR_VERSION) -ge 10 ] && echo true)
		OSX_10_5_OR_LATER := $(shell [ $(OSX_MINOR_VERSION) -ge 5 ] && echo true)
		ifeq ($(OSX_10_OR_LATER),true)
			ifeq ($(OSX_10_5_OR_LATER),true)
				LDFLAGS += -Wl,-rpath,$(CUDA_LIB_DIR)
			endif
		endif
	endif
	# gtest needs to use its own tuple to not conflict with clang
	COMMON_FLAGS += -DGTEST_USE_OWN_TR1_TUPLE=1
	# we need to explicitly ask for the rpath to be obeyed
	ORIGIN := @loader_path
	VERSIONFLAGS += -Wl,-install_name,@rpath/$(DYNAMIC_VERSIONED_NAME_SHORT) -Wl,-rpath,$(ORIGIN)/../../build/lib
else
	ORIGIN := \$$ORIGIN
endif

# Custom compiler
ifdef CUSTOM_CXX
	CXX := $(CUSTOM_CXX)
endif

# Static linking
ifneq (,$(findstring clang++,$(CXX)))
	STATIC_LINK_COMMAND := -Wl,-force_load $(STATIC_NAME)
else ifneq (,$(findstring g++,$(CXX)))
	STATIC_LINK_COMMAND := -Wl,--whole-archive $(STATIC_NAME) -Wl,--no-whole-archive
else
  # The following line must not be indented with a tab, since we are not inside a target
  $(error Cannot static link with the $(CXX) compiler)
endif

# Debugging
ifeq ($(DEBUG), 1)
	COMMON_FLAGS += -DDEBUG -g -O0
	NVCCFLAGS += -G
else
	COMMON_FLAGS += -DNDEBUG -O2
endif

# cuDNN acceleration configuration.
ifeq ($(USE_CUDNN), 1)
	LIBRARIES += cudnn
	COMMON_FLAGS += -DUSE_CUDNN
endif

# CPU-only configuration
ifeq ($(CPU_ONLY), 1)
	OBJS := $(PROTO_OBJS) $(CXX_OBJS)
	TEST_OBJS := $(TEST_CXX_OBJS)
	TEST_BINS := $(TEST_CXX_BINS)
	TEST_FILTER := --gtest_filter="-*GPU*"
	COMMON_FLAGS += -DCPU_ONLY
endif

BLAS ?= open
ifeq ($(BLAS), mkl)
	LIBRARIES += mkl_rt
	COMMON_FLAGS += -DUSE_MKL
	MKLROOT ?= /opt/intel/mkl
	BLAS_INCLUDE ?= $(MKLROOT)/include
	BLAS_LIB ?= $(MKLROOT)/lib $(MKLROOT)/lib/intel64
else ifeq ($(BLAS), open)
	LIBRARIES += openblas
else ifeq ($(BLAS), eigen)
	COMMON_FLAGS += -DUSE_EIGEN
	BLAS_INCLUDE := submodules/eigen
else
	$(error unknown BLAS: $(BLAS))
endif
INCLUDE_DIRS += $(BLAS_INCLUDE)
LIBRARY_DIRS += $(BLAS_LIB)

LIBRARY_DIRS += $(LIB_BUILD_DIR)

# Automatic dependency generation (nvcc is handled separately)
CXXFLAGS += -MMD -MP

# Complete build flags.
COMMON_FLAGS += $(foreach includedir,$(INCLUDE_DIRS),-I$(includedir))
CXXFLAGS += -pthread -fPIC $(COMMON_FLAGS) $(WARNINGS)
NVCCFLAGS += -ccbin=$(CXX) -Xcompiler -fPIC $(COMMON_FLAGS)
LINKFLAGS += -pthread -fPIC $(COMMON_FLAGS) $(WARNINGS)

LDFLAGS += $(foreach librarydir,$(LIBRARY_DIRS),-L$(librarydir)) \
		$(foreach library,$(LIBRARIES),-l$(library))

##############################
# Define build targets
##############################
.PHONY: all lib clean $(DIST_ALIASES) proto test runtest

all: lib

lib: $(STATIC_NAME) $(DYNAMIC_NAME)

test: $(TEST_ALL_BIN) $(TEST_ALL_DYNLINK_BIN) $(TEST_BINS)

runtest: $(TEST_ALL_BIN)
	$(TEST_ALL_BIN) $(TEST_GPUID) --gtest_shuffle $(TEST_FILTER)

$(BUILD_DIR_LINK): $(BUILD_DIR)/.linked

# Create a target ".linked" in this BUILD_DIR to tell Make that the "build" link
# is currently correct, then delete the one in the OTHER_BUILD_DIR in case it
# exists and $(DEBUG) is toggled later.
$(BUILD_DIR)/.linked:
	@ mkdir -p $(BUILD_DIR)
	@ $(RM) $(OTHER_BUILD_DIR)/.linked
	@ $(RM) -r $(BUILD_DIR_LINK)
	@ ln -s $(BUILD_DIR) $(BUILD_DIR_LINK)
	@ touch $@

$(ALL_BUILD_DIRS): | $(BUILD_DIR_LINK)
	@ mkdir -p $@

$(DYNAMIC_NAME): $(OBJS) | $(LIB_BUILD_DIR)
	@ echo LD -o $@
	$(Q)$(CXX) -shared -o $@ $(OBJS) $(VERSIONFLAGS) $(LINKFLAGS) $(LDFLAGS)
	@ cd $(BUILD_DIR)/lib; rm -f $(DYNAMIC_NAME_SHORT);   ln -s $(DYNAMIC_VERSIONED_NAME_SHORT) $(DYNAMIC_NAME_SHORT)

$(STATIC_NAME): $(OBJS) | $(LIB_BUILD_DIR)
	@ echo AR -o $@
	$(Q)ar rcs $@ $(OBJS)

$(BUILD_DIR)/%.o: %.cpp | $(ALL_BUILD_DIRS)
	@ echo CXX $<
	$(Q)$(CXX) $< $(CXXFLAGS) -c -o $@

$(PROTO_BUILD_DIR)/%.pb.o: $(PROTO_BUILD_DIR)/%.pb.cc $(PROTO_GEN_HEADER) \
		| $(PROTO_BUILD_DIR)
	@ echo CXX $<
	$(Q)$(CXX) $< $(CXXFLAGS) -c -o $@

$(BUILD_DIR)/cuda/%.o: %.cu | $(ALL_BUILD_DIRS)
	@ echo NVCC $<
	$(Q)$(CUDA_DIR)/bin/nvcc $(NVCCFLAGS) $(CUDA_ARCH) -M $< -o ${@:.o=.d} \
		-odir $(@D)
	$(Q)$(CUDA_DIR)/bin/nvcc $(NVCCFLAGS) $(CUDA_ARCH) -c $< -o $@

$(TEST_ALL_BIN): $(TEST_MAIN_SRC) $(TEST_OBJS) $(GTEST_OBJ) \
		| $(DYNAMIC_NAME) $(TEST_BIN_DIR)
	@ echo CXX/LD -o $@ $<
	$(Q)$(CXX) $(TEST_MAIN_SRC) $(TEST_OBJS) $(GTEST_OBJ) \
		-o $@ $(LINKFLAGS) $(CXXFLAGS) $(LDFLAGS) -l$(LIBRARY_NAME) -Wl,-rpath,$(ORIGIN)/../lib

$(TEST_CU_BINS): $(TEST_BIN_DIR)/%.testbin: $(TEST_CU_BUILD_DIR)/%.o \
	$(GTEST_OBJ) | $(DYNAMIC_NAME) $(TEST_BIN_DIR)
	@ echo LD $<
	$(Q)$(CXX) $(TEST_MAIN_SRC) $< $(GTEST_OBJ) \
		-o $@ $(LINKFLAGS) $(CXXFLAGS) $(LDFLAGS) -l$(LIBRARY_NAME) -Wl,-rpath,$(ORIGIN)/../lib

$(TEST_CXX_BINS): $(TEST_BIN_DIR)/%.testbin: $(TEST_CXX_BUILD_DIR)/%.o \
	$(GTEST_OBJ) | $(DYNAMIC_NAME) $(TEST_BIN_DIR)
	@ echo LD $<
	$(Q)$(CXX) $(TEST_MAIN_SRC) $< $(GTEST_OBJ) \
		-o $@ $(LINKFLAGS) $(CXXFLAGS) $(LDFLAGS) -l$(LIBRARY_NAME) -Wl,-rpath,$(ORIGIN)/../lib

proto: $(PROTO_GEN_CC) $(PROTO_GEN_HEADER)

$(PROTO_BUILD_DIR)/%.pb.cc $(PROTO_BUILD_DIR)/%.pb.h : \
		$(PROTO_SRC_DIR)/%.proto | $(PROTO_BUILD_DIR)
	@ echo PROTOC $<
	$(Q)protoc --proto_path=$(PROTO_SRC_DIR) --cpp_out=$(PROTO_BUILD_DIR) $<

clean:
	@- $(RM) -rf $(ALL_BUILD_DIRS)
	@- $(RM) -rf $(OTHER_BUILD_DIR)
	@- $(RM) -rf $(BUILD_DIR_LINK)
	@- $(RM) -rf $(DISTRIBUTE_DIR)

$(DIST_ALIASES): $(DISTRIBUTE_DIR)

$(DISTRIBUTE_DIR): all | $(DISTRIBUTE_SUBDIRS)
	$(Q) cp -r src/caffe/proto $(DISTRIBUTE_DIR)/
	$(Q) cp -r include $(DISTRIBUTE_DIR)/
	$(Q) mkdir -p $(DISTRIBUTE_DIR)/include/caffe/proto
	$(Q) cp $(PROTO_GEN_HEADER_SRCS) $(DISTRIBUTE_DIR)/include/caffe/proto
	$(Q) cp $(STATIC_NAME) $(DISTRIBUTE_DIR)/lib
	$(Q) install -m 644 $(DYNAMIC_NAME) $(DISTRIBUTE_DIR)/lib
	$(Q) cd $(DISTRIBUTE_DIR)/lib; rm -f $(DYNAMIC_NAME_SHORT);   ln -s $(DYNAMIC_VERSIONED_NAME_SHORT) $(DYNAMIC_NAME_SHORT)

-include $(DEPS)
