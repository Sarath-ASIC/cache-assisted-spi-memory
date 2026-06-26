// ============================================================
// Module   : cache_ctrl
// Project  : Cache-Assisted SPI Memory Accelerator
// Author   : Sarath K C
// Description:
//   4-entry direct-mapped cache with write-through policy.
//   Sits between a CPU-like requester and an SPI external memory.
//   On a hit : data returned immediately from cache.
//   On a miss: SPI memory is read and cache line is updated.
//   Write-through: writes go to both cache and SPI memory.
//
//   Cache structure:
//     - 4 lines (index = addr[1:0])
//     - Each line: valid bit + tag + data byte
//     - Tag = addr[7:2] (upper 6 bits of 8-bit address)
// ============================================================

module cache_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // CPU-side interface
    input  wire        cpu_req,      // CPU wants to access memory
    input  wire        cpu_we,       // 1 = write, 0 = read
    input  wire [7:0]  cpu_addr,     // Address (8-bit: 4 index + 4 tag for simplicity)
    input  wire [7:0]  cpu_wdata,    // Data CPU wants to write
    output reg  [7:0]  cpu_rdata,   // Data returned to CPU on read hit
    output reg         cpu_ready,   // High when operation is complete

    // SPI-side interface (to spi_master)
    output reg         spi_start,   // Trigger SPI transfer
    output reg         spi_we,      // 1 = write to SPI mem, 0 = read
    output reg  [7:0]  spi_addr,   // Address for SPI memory
    output reg  [7:0]  spi_wdata,  // Data to write to SPI memory
    input  wire [7:0]  spi_rdata,  // Data read from SPI memory
    input  wire        spi_done    // SPI transfer complete
);

    // --------------------------------------------------------
    // Cache storage: 4 lines
    // --------------------------------------------------------
    localparam CACHE_LINES = 4;

    reg        valid [0:CACHE_LINES-1];  // Valid bits
    reg [5:0]  tag   [0:CACHE_LINES-1]; // Tag bits (addr[7:2])
    reg [7:0]  data  [0:CACHE_LINES-1]; // Cached data

    // --------------------------------------------------------
    // Address decode
    // index = lower 2 bits of address
    // tag   = upper 6 bits of address
    // --------------------------------------------------------
    wire [1:0] index = cpu_addr[1:0];
    wire [5:0] ctag  = cpu_addr[7:2];

    // --------------------------------------------------------
    // Hit detection: valid AND tag matches
    // --------------------------------------------------------
    wire hit = valid[index] && (tag[index] == ctag);

    // --------------------------------------------------------
    // FSM states
    // --------------------------------------------------------
    localparam IDLE       = 2'b00;
    localparam CHECK      = 2'b01;
    localparam SPI_WAIT   = 2'b10;
    localparam COMPLETE   = 2'b11;

    reg [1:0] state;

    // Saved request info (latch on entry)
    reg        saved_we;
    reg [7:0]  saved_addr;
    reg [7:0]  saved_wdata;
    reg [1:0]  saved_index;
    reg [5:0]  saved_tag;

    integer i;

    // --------------------------------------------------------
    // FSM: sequential block
    // --------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= IDLE;
            cpu_rdata  <= 8'h00;
            cpu_ready  <= 1'b0;
            spi_start  <= 1'b0;
            spi_we     <= 1'b0;
            spi_addr   <= 8'h00;
            spi_wdata  <= 8'h00;
            for (i = 0; i < CACHE_LINES; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i]   <= 6'h00;
                data[i]  <= 8'h00;
            end
        end
        else begin
            cpu_ready <= 1'b0;
            spi_start <= 1'b0;

            case (state)
                // ------------------------------------------
                // IDLE: Wait for CPU request
                // ------------------------------------------
                IDLE: begin
                    if (cpu_req) begin
                        saved_we    <= cpu_we;
                        saved_addr  <= cpu_addr;
                        saved_wdata <= cpu_wdata;
                        saved_index <= index;
                        saved_tag   <= ctag;
                        state <= CHECK;
                    end
                end

                // ------------------------------------------
                // CHECK: Determine hit or miss
                // ------------------------------------------
                CHECK: begin
                    if (hit) begin
                        // === CACHE HIT ===
                        if (!saved_we) begin
                            // Read hit: return cached data immediately
                            cpu_rdata <= data[saved_index];
                        end
                        else begin
                            // Write hit: update cache + write through to SPI
                            data[saved_index] <= saved_wdata;
                            spi_start         <= 1'b1;
                            spi_we            <= 1'b1;
                            spi_addr          <= saved_addr;
                            spi_wdata         <= saved_wdata;
                        end
                        cpu_ready <= 1'b1;
                        state     <= IDLE;
                    end
                    else begin
                        // === CACHE MISS ===
                        // Must go fetch from SPI memory
                        spi_start <= 1'b1;
                        spi_we    <= saved_we;
                        spi_addr  <= saved_addr;
                        spi_wdata <= saved_wdata;
                        state     <= SPI_WAIT;
                    end
                end

                // ------------------------------------------
                // SPI_WAIT: Wait for SPI transfer to finish
                // ------------------------------------------
                SPI_WAIT: begin
                    if (spi_done) begin
                        if (!saved_we) begin
                            // Read miss: fill cache line with data from SPI
                            valid[saved_index] <= 1'b1;
                            tag[saved_index]   <= saved_tag;
                            data[saved_index]  <= spi_rdata;
                            cpu_rdata          <= spi_rdata;
                        end
                        // Write miss: write-through already done by SPI
                        cpu_ready <= 1'b1;
                        state     <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
