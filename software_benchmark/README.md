# Software Benchmarks

Build:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

Run the default 24-bit benchmarks:

```sh
./build/benchmark_simple_scalar --reps 100
./build/benchmark_ntt_scalar --reps 100
./build/benchmark_simple_avx2 --reps 100
./build/benchmark_ntt_avx2 --reps 100
./build/benchmark_simple_avx512 --reps 100
./build/benchmark_ntt_avx512 --reps 100
```

The NTT benchmarks print both full polynomial multiplication timing and
`forward_ntt_*` timing for one negacyclic forward transform.

Run the 60-bit benchmarks:

```sh
./build/benchmark_simple_60bit_scalar --reps 100
./build/benchmark_ntt_60bit_scalar --reps 100
./build/benchmark_simple_60bit_avx2 --reps 100
./build/benchmark_ntt_60bit_avx2 --reps 100
./build/benchmark_simple_60bit_avx512 --reps 100
./build/benchmark_ntt_60bit_avx512 --reps 100
```

Change the default 24-bit parameters at configure time:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBENCH_N=4096 -DBENCH_Q=8380417 -DBENCH_PSI=283817 -DBENCH_REPS=100
```
