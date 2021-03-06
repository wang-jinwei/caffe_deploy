#ifndef CAFFE_COMMON_HPP_
#define CAFFE_COMMON_HPP_

#include <glog_deploy.hpp>

#include <climits>
#include <cmath>
#include <fstream>  // NOLINT(readability/streams)
#include <iostream>  // NOLINT(readability/streams)
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <utility>  // pair
#include <vector>
#include <memory>

#include "caffe/util/device_alternate.hpp"

// Convert macro to string
#define STRINGIFY(m) #m
#define AS_STRING(m) STRINGIFY(m)

// Disable the copy and assignment operator for a class.
#define DISABLE_COPY_AND_ASSIGN(classname) \
private:\
  classname(const classname&);\
  classname& operator=(const classname&)

// Instantiate a class with float and double specifications.
#define INSTANTIATE_CLASS(classname) \
  char gInstantiationGuard##classname; \
  template class classname<float>;

#define INSTANTIATE_LAYER_GPU_FORWARD(classname) \
  template void classname<float>::Forward_gpu( \
      const std::vector<Blob<float>*>& bottom, \
      const std::vector<Blob<float>*>& top);

#define INSTANTIATE_LAYER_GPU_BACKWARD(classname) \
  template void classname<float>::Backward_gpu( \
      const std::vector<Blob<float>*>& top, \
      const std::vector<bool>& propagate_down, \
      const std::vector<Blob<float>*>& bottom);

#define INSTANTIATE_LAYER_GPU_FUNCS(classname) \
  INSTANTIATE_LAYER_GPU_FORWARD(classname); \
  INSTANTIATE_LAYER_GPU_BACKWARD(classname)

// A simple macro to mark codes that are not implemented, so that when the code
// is executed we will see a fatal log.
#define NOT_IMPLEMENTED LOG(FATAL) << "Not Implemented Yet"

namespace caffe {

// Common functions and classes from std that caffe often uses.
using std::shared_ptr;
using std::fstream;
using std::ios;
using std::isnan;
using std::isinf;
using std::iterator;
using std::make_pair;
using std::map;
using std::ostringstream;
using std::pair;
using std::set;
using std::string;
using std::stringstream;
using std::vector;

#if defined(__x86_64__) || defined(_M_X64) || defined(__amd64)
#define CAFFE_ARCH_x86_64 1
#else
#define CAFFE_ARCH_x86_64 0
#endif

#if defined(__i386__) || defined(_M_IX86) || defined(_X86_) || defined(__i386)
#define CAFFE_ARCH_i386 1
#else
#define CAFFE_ARCH_i386 0
#endif

#if (__cplusplus > 201103L) || CAFFE_ARCH_x86_64 || CAFFE_ARCH_i386
#define CAFFE_HAS_CXX11_MATH 1
#else
#define CAFFE_HAS_CXX11_MATH 0
#endif

class MemoryNode;

// A singleton class to hold common caffe stuff, such as the handler that
// caffe is going to use for cublas, curand, etc.
class Caffe {
 public:
  ~Caffe();

  // Thread local context for Caffe. Moved to common.cpp instead of
  // including boost/thread.hpp to avoid a boost/NVCC issues (#1009, #1010)
  // on OSX. Also fails on Linux with CUDA 7.0.18.
  static Caffe& Get();

  enum Brew { CPU, GPU };

  // This random number generator facade hides boost and CUDA rng
  // implementation from one another (for cross-platform compatibility).
  class RNG {
   public:
    RNG();
    explicit RNG(unsigned int seed);
    explicit RNG(const RNG&);
    RNG& operator=(const RNG&);
    void* generator();
   private:
    class Generator;
    shared_ptr<Generator> generator_;
  };

  // Getters for boost rng, curand, and cublas handles
  inline static RNG& rng_stream() {
    if (!Get().random_generator_) {
      Get().random_generator_.reset(new RNG());
    }
    return *(Get().random_generator_);
  }
#ifndef CPU_ONLY
  inline static cublasHandle_t cublas_handle() {
    return Get().cublas_handle_;
  }
  inline static curandGenerator_t curand_generator() {
    return Get().curand_generator_;
  }
  static void* GpuBuffer(size_t size);
  static void ReleaseGpuBuffer(const void* buffer);
  static void ClearGpuBuffer(void);
  static void* GpuWorkspace(size_t size);
#ifdef USE_CUDNN
  inline static cudnnHandle_t cudnn_handle() {
    return Get().cudnn_handle_;
  }
#endif
#endif
  static void* CpuBuffer(size_t size);
  static void ReleaseCpuBuffer(const void* buffer);
  static void ClearCpuBuffer(void);
  static void* CpuWorkspace(size_t size);

  // Returns the mode: running on CPU or GPU.
  inline static Brew mode() { return Get().mode_; }
  // The setters for the variables
  // Sets the mode. It is recommended that you don't change the mode halfway
  // into the program since that may cause allocation of pinned memory being
  // freed in a non-pinned way, which may cause problems - I haven't verified
  // it personally but better to note it here in the header file.
  inline static void set_mode(Brew mode) { Get().mode_ = mode; }
  // Sets the random seed of both boost and curand
  static void set_random_seed(const unsigned int seed);
  // Sets the device. Since we have cublas and curand stuff, set device also
  // requires us to reset those values.
  static void SetDevice(const int device_id);
  // Prints the current GPU status.
  static void DeviceQuery();
  // Check if specified device is available
  static bool CheckDevice(const int device_id);
  // Search from start_id to the highest possible device ordinal,
  // return the ordinal of the first available device.
  static int FindDevice(const int start_id = 0);

 protected:
#ifndef CPU_ONLY
  cublasHandle_t cublas_handle_;
  curandGenerator_t curand_generator_;
  bool device_set_;
  vector<MemoryNode*> gpu_memory_list_;
  void* gpu_workspace_;
  size_t gpu_workspace_size_;
#ifdef USE_CUDNN
  cudnnHandle_t cudnn_handle_;
#endif
#endif
  vector<MemoryNode*> cpu_memory_list_;
  void* cpu_workspace_;
  size_t cpu_workspace_size_;
  shared_ptr<RNG> random_generator_;

  Brew mode_;

 private:
  // The private constructor to avoid duplicate instantiation.
  Caffe();

  DISABLE_COPY_AND_ASSIGN(Caffe);
};

}  // namespace caffe

#endif  // CAFFE_COMMON_HPP_
