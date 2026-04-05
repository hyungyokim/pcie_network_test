#include <cuda_runtime.h>

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/stat.h>
#include <sys/types.h>
#include <string>
#include <vector>

#define CHECK_CUDA(call)                                                       \
  do {                                                                         \
    cudaError_t err = call;                                                    \
    if (err != cudaSuccess) {                                                  \
      fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__, __LINE__,            \
              cudaGetErrorString(err));                                        \
      exit(EXIT_FAILURE);                                                      \
    }                                                                          \
  } while (0)

struct Result {
  double avg_us;
  double min_us;
  double max_us;
  double gbps;
};

static Result run_test(size_t size, int iterations, bool h2d) {
  void *h_buf = nullptr;
  void *d_buf = nullptr;

  CHECK_CUDA(cudaMallocHost(&h_buf, size));
  CHECK_CUDA(cudaMalloc(&d_buf, size));

  cudaStream_t stream;
  CHECK_CUDA(cudaStreamCreate(&stream));

  std::vector<float> times;
  times.reserve(iterations);

  for (int i = 0; i < 10; ++i) {
    if (h2d) {
      CHECK_CUDA(
          cudaMemcpyAsync(d_buf, h_buf, size, cudaMemcpyHostToDevice, stream));
    } else {
      CHECK_CUDA(
          cudaMemcpyAsync(h_buf, d_buf, size, cudaMemcpyDeviceToHost, stream));
    }
  }
  CHECK_CUDA(cudaStreamSynchronize(stream));

  for (int i = 0; i < iterations; ++i) {
    cudaEvent_t start;
    cudaEvent_t stop;
    CHECK_CUDA(cudaEventCreate(&start));
    CHECK_CUDA(cudaEventCreate(&stop));

    CHECK_CUDA(cudaEventRecord(start, stream));

    if (h2d) {
      CHECK_CUDA(
          cudaMemcpyAsync(d_buf, h_buf, size, cudaMemcpyHostToDevice, stream));
    } else {
      CHECK_CUDA(
          cudaMemcpyAsync(h_buf, d_buf, size, cudaMemcpyDeviceToHost, stream));
    }

    CHECK_CUDA(cudaEventRecord(stop, stream));
    CHECK_CUDA(cudaEventSynchronize(stop));

    float ms = 0.0f;
    CHECK_CUDA(cudaEventElapsedTime(&ms, start, stop));
    times.push_back(ms * 1000.0f);

    CHECK_CUDA(cudaEventDestroy(start));
    CHECK_CUDA(cudaEventDestroy(stop));
  }

  CHECK_CUDA(cudaStreamSynchronize(stream));

  double sum = 0.0;
  for (float t : times) {
    sum += t;
  }

  const double avg = sum / static_cast<double>(times.size());
  const double minv = *std::min_element(times.begin(), times.end());
  const double maxv = *std::max_element(times.begin(), times.end());
  const double gbps = static_cast<double>(size) / (avg / 1e6) / 1e9;

  CHECK_CUDA(cudaFreeHost(h_buf));
  CHECK_CUDA(cudaFree(d_buf));
  CHECK_CUDA(cudaStreamDestroy(stream));

  return {avg, minv, maxv, gbps};
}

static std::string dirname_of(const std::string &path) {
  const std::string::size_type pos = path.find_last_of('/');
  if (pos == std::string::npos) {
    return ".";
  }
  if (pos == 0) {
    return "/";
  }
  return path.substr(0, pos);
}

static void ensure_dir_exists(const std::string &dir) {
  if (dir.empty() || dir == ".") {
    return;
  }

  std::string current;
  if (dir[0] == '/') {
    current = "/";
  }

  std::string::size_type start = (dir[0] == '/') ? 1 : 0;
  while (start <= dir.size()) {
    const std::string::size_type end = dir.find('/', start);
    const std::string piece = dir.substr(start, end - start);
    if (!piece.empty()) {
      if (!current.empty() && current.back() != '/') {
        current += "/";
      }
      current += piece;
      if (mkdir(current.c_str(), 0755) != 0 && errno != EEXIST) {
        fprintf(stderr, "Failed to create directory %s: %s\n", current.c_str(),
                strerror(errno));
        exit(EXIT_FAILURE);
      }
    }

    if (end == std::string::npos) {
      break;
    }
    start = end + 1;
  }
}

static FILE *open_output(int argc, char **argv, std::string *output_path) {
  *output_path = "pcie_logs/profile_pcie.csv";

  for (int i = 1; i < argc; ++i) {
    if ((strcmp(argv[i], "--output") == 0 || strcmp(argv[i], "-o") == 0) &&
        i + 1 < argc) {
      *output_path = argv[++i];
    } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
      printf("Usage: %s [--output <csv_path>]\n", argv[0]);
      printf("Default output: pcie_logs/profile_pcie.csv\n");
      exit(EXIT_SUCCESS);
    } else {
      fprintf(stderr, "Unknown argument: %s\n", argv[i]);
      exit(EXIT_FAILURE);
    }
  }

  ensure_dir_exists(dirname_of(*output_path));

  FILE *fp = fopen(output_path->c_str(), "w");
  if (fp == nullptr) {
    fprintf(stderr, "Failed to open output file: %s\n", output_path->c_str());
    exit(EXIT_FAILURE);
  }

  return fp;
}

static void emit_line(FILE *fp, const char *direction, size_t size,
                      const Result &result) {
  fprintf(stdout, "%s,%zu,%.3f,%.3f,%.3f,%.3f\n", direction, size,
          result.avg_us, result.min_us, result.max_us, result.gbps);
  fprintf(fp, "%s,%zu,%.3f,%.3f,%.3f,%.3f\n", direction, size, result.avg_us,
          result.min_us, result.max_us, result.gbps);
}

int main(int argc, char **argv) {
  std::string output_path;
  FILE *fp = open_output(argc, argv, &output_path);

  const std::vector<size_t> sizes = {
      4096ULL,     8192ULL,     16384ULL,    32768ULL,    65536ULL,
      131072ULL,   262144ULL,   524288ULL,   1048576ULL,  2097152ULL,
      4194304ULL,  8388608ULL,  16777216ULL, 33554432ULL, 67108864ULL,
      134217728ULL, 268435456ULL};
  const int iterations = 50;

  const char *header =
      "direction,size_bytes,avg_latency_us,min_latency_us,max_latency_us,bandwidth_GBps\n";
  fputs(header, stdout);
  fputs(header, fp);

  for (size_t size : sizes) {
    Result h2d = run_test(size, iterations, true);
    emit_line(fp, "H2D", size, h2d);

    Result d2h = run_test(size, iterations, false);
    emit_line(fp, "D2H", size, d2h);
  }

  fclose(fp);
  fprintf(stderr, "[INFO] Saved PCIe profile to %s\n", output_path.c_str());
  return 0;
}
