cmake_minimum_required(VERSION 3.20)

project(tiny_ntt_software_benchmark LANGUAGES CXX)

set(BENCH_N "4096" CACHE STRING "Polynomial/NTT size. Must be a power of two.")
set(BENCH_Q "8380417" CACHE STRING "Prime modulus.")
set(BENCH_PSI "283817" CACHE STRING "Primitive 2N-th root for negacyclic NTT.")
set(BENCH_REPS "10" CACHE STRING "Default benchmark repetitions.")

option(BUILD_AVX2 "Build AVX2 benchmark variants when supported." ON)
option(BUILD_AVX512 "Build AVX-512 benchmark variants when supported." ON)

include(CheckCXXCompilerFlag)
check_cxx_compiler_flag("-mavx2" COMPILER_SUPPORTS_AVX2)
check_cxx_compiler_flag("-mavx512f -mavx512dq" COMPILER_SUPPORTS_AVX512)

function(add_benchmark_target name source simd_kind)
    add_executable(${name} ${source})
    target_compile_features(${name} PRIVATE cxx_std_20)
    target_compile_definitions(${name} PRIVATE
        BENCH_N=${BENCH_N}
        BENCH_Q=${BENCH_Q}
        BENCH_PSI=${BENCH_PSI}
        BENCH_REPS=${BENCH_REPS}
        BENCH_SIMD_KIND=${simd_kind}
        BENCH_TARGET_NAME="${name}"
    )
    target_compile_options(${name} PRIVATE -O3 -Wall -Wextra -Wpedantic)
endfunction()

add_benchmark_target(benchmark_simple_scalar benchmark_simple.cpp 0)
add_benchmark_target(benchmark_ntt_scalar benchmark_ntt.cpp 0)
add_benchmark_target(benchmark_simple_60bit_scalar benchmark_simple_60bit.cpp 0)
add_benchmark_target(benchmark_ntt_60bit_scalar benchmark_ntt_60bit.cpp 0)

if(BUILD_AVX2 AND COMPILER_SUPPORTS_AVX2)
    add_benchmark_target(benchmark_simple_avx2 benchmark_simple.cpp 1)
    add_benchmark_target(benchmark_ntt_avx2 benchmark_ntt.cpp 1)
    add_benchmark_target(benchmark_simple_60bit_avx2 benchmark_simple_60bit.cpp 1)
    add_benchmark_target(benchmark_ntt_60bit_avx2 benchmark_ntt_60bit.cpp 1)
    target_compile_options(benchmark_simple_avx2 PRIVATE -mavx2)
    target_compile_options(benchmark_ntt_avx2 PRIVATE -mavx2)
    target_compile_options(benchmark_simple_60bit_avx2 PRIVATE -mavx2)
    target_compile_options(benchmark_ntt_60bit_avx2 PRIVATE -mavx2)
else()
    message(STATUS "Skipping AVX2 benchmark targets")
endif()

if(BUILD_AVX512 AND COMPILER_SUPPORTS_AVX512)
    add_benchmark_target(benchmark_simple_avx512 benchmark_simple.cpp 2)
    add_benchmark_target(benchmark_ntt_avx512 benchmark_ntt.cpp 2)
    add_benchmark_target(benchmark_simple_60bit_avx512 benchmark_simple_60bit.cpp 2)
    add_benchmark_target(benchmark_ntt_60bit_avx512 benchmark_ntt_60bit.cpp 2)
    target_compile_options(benchmark_simple_avx512 PRIVATE -mavx512f -mavx512dq)
    target_compile_options(benchmark_ntt_avx512 PRIVATE -mavx512f -mavx512dq)
    target_compile_options(benchmark_simple_60bit_avx512 PRIVATE -mavx512f -mavx512dq)
    target_compile_options(benchmark_ntt_60bit_avx512 PRIVATE -mavx512f -mavx512dq)
else()
    message(STATUS "Skipping AVX-512 benchmark targets")
endif()
