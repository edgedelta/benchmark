# Benchmark Analysis Instructions

When invoked in CI, run the `/analyse-benchmark` skill to analyse the benchmark results in `benchmark_results/`.

Save the final report to **`benchmark_results/report.md`**, overwriting any existing file. This fixed filename is required so the CI upload-artifact step can reliably find and upload the report.
