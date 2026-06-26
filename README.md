# cache-assisted-spi-memory
Verilog implementation of a cache-assisted SPI memory interface with direct-mapped cache , hit/miss detection, and FSM-based memory access control.

💡 Motivation

SPI memory is slow — a single byte read over SPI at 10 MHz takes ~800 ns (8 clock cycles + protocol overhead). If the CPU reads the same address repeatedly, we pay this cost every time.

Solution: Add a small cache between the CPU and SPI memory. On a hit, data returns in 1 clock cycle instead of 4–10 cycles. On a miss, we fetch from SPI and store in cache for future use.

HIT vs MISS

CPU Request
     │
     ▼
Check: valid[index] == 1 AND tag[index] == addr[7:2] ?
     │
     ├── YES (HIT)  → Return data[index] immediately (1 cycle)
     │
     └── NO  (MISS) → Fetch from SPI memory (4–10 cycles)
                       → Store in cache line
                       → Return data to CPU


🧪 Simulation Requirements
1.  Icarus Verilog
2.   GTKWave

To run Simulation : 
# Compile
iverilog -o cache_sim tb/tb_cache_ctrl.v rtl/cache_ctrl.v

# Run
./cache_sim ( or ) vvp sim`

# View waveforms
gtkwave cache_sim.vcd
