#include <cuda_runtime.h>
#include <cstdio>
#include <vector>
#include <algorithm>

#define CHECK_CUDA(call) \
  do { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
      fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__, __LINE__, cudaGetErrorString(err)); \
      exit(EXIT_FAILURE); \
    } \
  } while (0)

struct Result {
  double avg_us;
  double min_us;
  double max_us;
  double gbps;
};

Result run_test(size_t size, int iterations, bool h2d) {
  void *h_buf, *d_buf;

  CHECK_CUDA(cudaMallocHost(&h_buf, size));  // pinned
  CHECK_CUDA(cudaMalloc(&d_buf, size));

  cudaStream_t stream;
  CHECK_CUDA(cudaStreamCreate(&stream));

  std::vector<float> times;

  // warmup
  for (int i = 0; i < 10; i++) {
    if (h2d)
      CHECK_CUDA(cudaMemcpyAsync(d_buf, h_buf, size, cudaMemcpyHostToDevice, stream));
    else
      CHECK_CUDA(cudaMemcpyAsync(h_buf, d_buf, size, cudaMemcpyDeviceToHost, stream));
  }
  CHECK_CUDA(cudaStreamSynchronize(stream));

  for (int i = 0; i < iterations; i++) {
    cudaEvent_t start, stop;
    CHECK_CUDA(cudaEventCreate(&start));
    CHECK_CUDA(cudaEventCreate(&stop));

    CHECK_CUDA(cudaEventRecord(start, stream));

    if (h2d)
      CHECK_CUDA(cudaMemcpyAsync(d_buf, h_buf, size, cudaMemcpyHostToDevice, stream));
    else
      CHECK_CUDA(cudaMemcpyAsync(h_buf, d_buf, size, cudaMemcpyDeviceToHost, stream));

    CHECK_CUDA(cudaEventRecord(stop, stream));
    CHECK_CUDA(cudaEventSynchronize(stop));

    float ms = 0;
    CHECK_CUDA(cudaEventElapsedTime(&ms, start, stop));
    times.push_back(ms * 1000.0); // us

    cudaEventDestroy(start);
    cudaEventDestroy(stop);
  }

  CHECK_CUDA(cudaStreamSynchronize(stream));

  double sum = 0;
  for (auto t : times) sum += t;

  double avg = sum / times.size();
  double minv = *std::min_element(times.begin(), times.end());
  double maxv = *std::max_element(times.begin(), times.end());

  double gbps = (double)size / (avg / 1e6) / 1e9;

  cudaFreeHost(h_buf);
  cudaFree(d_buf);
  cudaStreamDestroy(stream);

  return {avg, minv, maxv, gbps};
}

int main() {
  std::vector<size_t> sizes = {
    4096ULL,
    8192ULL,
    16384ULL,
    32768ULL,
    65536ULL,
    131072ULL,
    262144ULL,
    524288ULL,
    1048576ULL,
    2097152ULL,
    4194304ULL,
    8388608ULL,
    16777216ULL,
    33554432ULL,
    67108864ULL,
    134217728ULL,
    268435456ULL
  };

  int iterations = 50;

  printf("direction,size_bytes,avg_us,min_us,max_us,GBps\n");

  for (auto size : sizes) {
    Result h2d = run_test(size, iterations, true);
    printf("H2D,%zu,%.3f,%.3f,%.3f,%.3f\n",
           size, h2d.avg_us, h2d.min_us, h2d.max_us, h2d.gbps);

    Result d2h = run_test(size, iterations, false);
    printf("D2H,%zu,%.3f,%.3f,%.3f,%.3f\n",
           size, d2h.avg_us, d2h.min_us, d2h.max_us, d2h.gbps);
  }

  return 0;
}
