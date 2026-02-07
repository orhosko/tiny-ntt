{
  description = "NTT Multiplication Unit - Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Use Python 3.12 which is well-supported by cocotb
        python = pkgs.python312;
        
        pythonEnv = python.withPackages (ps: with ps; [
          cocotb
          cocotb-bus
        ]);
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pythonEnv
            pkgs.iverilog         # Icarus Verilog
            pkgs.gtkwave          # Waveform viewer (optional but useful)
            
            # Additional useful tools
            pkgs.verilator        # Alternative simulator
            pkgs.gnumake          # For running Makefile
            pkgs.yosys            # Synthesis tool
          ];

          shellHook = ''
            echo "🚀 NTT Multiplication Unit Development Environment"
            echo ""
            echo "Available tools:"
            echo "  • Python ${python.version} with cocotb"
            echo "  • Icarus Verilog: $(iverilog -V 2>&1 | head -n1)"
            echo "  • Verilator: $(verilator --version | head -n1)"
            echo "  • Yosys: $(yosys -V | head -n1)"
            echo "  • GTKWave for waveform viewing"
            echo ""
            echo "To run tests:"
            echo "  cd test && make"
            echo ""
            echo "To synthesize:"
            echo "  cd synth && make synth-all"
            echo ""
            echo "To view waveforms:"
            echo "  gtkwave test/*.vcd"
            echo ""
          '';
        };
      }
    );
}
