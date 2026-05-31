- https://github.com/orhosko/chipyard

``` shell
make CONFIG=NTTRocketConfig \
  BINARY=../../tests/ntt.riscv \
  PLATFORM_OPTS="--assert --unroll-count 8192" \
  run-binary-fast 2>&1 | tee binary-fast-output.txt
 ```

``` shell
cd /home/berkay/Documents/projects/chipyard
source env.sh
cd vlsi
make syn CONFIG=NTTRocketConfig tech_name=sky130 INPUT_CONFS="example-design.yml example-openroad.yml example-sky130.yml" TOP_MACROCOMPILER_MODE="--mode synflops" ENABLE_YOSYS_FLOW=1 2>&1 | tee /tmp/syn_output.log
```

``` shell
cd /home/berkay/Documents/projects/chipyard
source env.sh
cd vlsi
make par CONFIG=NTTRocketConfig \
  tech_name=sky130 \
  INPUT_CONFS="example-design.yml example-openroad.yml example-sky130.yml" \ 
  TOP_MACROCOMPILER_MODE="--mode synflops" \
  ENABLE_YOSYS_FLOW=1 2>&1 | tee /tmp/par_output.log 
```
