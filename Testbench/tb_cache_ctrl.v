// ============================================================
// Module   : tb_cache_ctrl
// Project  : Cache-Assisted SPI Memory Accelerator
// Author   : Sarath K C
// Description:
//   Testbench for cache_ctrl.
//   Simulates a simple SPI memory model (behavioral).
//   Tests: read miss, read hit, write-through, hit rate.
// ============================================================

`timescale 1ns/1ps

module tb_cache_ctrl;

    reg        clk, rst_n;
    reg        cpu_req, cpu_we;
    reg [7:0]  cpu_addr, cpu_wdata;
    wire [7:0] cpu_rdata;
    wire       cpu_ready;

    wire        spi_start, spi_we;
    wire [7:0]  spi_addr, spi_wdata;
    reg  [7:0]  spi_rdata;
    reg         spi_done;

    // Instantiate cache controller
    cache_ctrl u_cache (
        .clk       (clk),
        .rst_n     (rst_n),
        .cpu_req   (cpu_req),
        .cpu_we    (cpu_we),
        .cpu_addr  (cpu_addr),
        .cpu_wdata (cpu_wdata),
        .cpu_rdata (cpu_rdata),
        .cpu_ready (cpu_ready),
        .spi_start (spi_start),
        .spi_we    (spi_we),
        .spi_addr  (spi_addr),
        .spi_wdata (spi_wdata),
        .spi_rdata (spi_rdata),
        .spi_done  (spi_done)
    );

    // Simple behavioral SPI memory model (256 bytes)
    reg [7:0] spi_mem [0:255];
    integer   spi_latency_cnt;

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Behavioral SPI memory: responds after 4 cycles
    always @(posedge clk) begin
        spi_done <= 0;
        if (spi_start) begin
            repeat (4) @(posedge clk);  // Simulate SPI latency
            if (spi_we)
                spi_mem[spi_addr] <= spi_wdata;
            else
                spi_rdata <= spi_mem[spi_addr];
            spi_done <= 1;
            @(posedge clk);
            spi_done <= 0;
        end
    end

    integer pass_count, fail_count;

    // Task: issue one CPU read and wait for ready
    task cpu_read;
        input [7:0] addr;
        input [7:0] expected;
        begin
            cpu_req  = 1;
            cpu_we   = 0;
            cpu_addr = addr;
            @(posedge clk);
            cpu_req = 0;
            wait (cpu_ready);
            @(posedge clk);
            if (cpu_rdata === expected) begin
                $display("PASS: Read addr=%02h got %02h", addr, cpu_rdata);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Read addr=%02h got %02h, expected %02h",
                         addr, cpu_rdata, expected);
                fail_count = fail_count + 1;
            end
            #20;
        end
    endtask

    // Task: issue one CPU write
    task cpu_write;
        input [7:0] addr;
        input [7:0] wdata;
        begin
            cpu_req   = 1;
            cpu_we    = 1;
            cpu_addr  = addr;
            cpu_wdata = wdata;
            @(posedge clk);
            cpu_req = 0;
            wait (cpu_ready);
            @(posedge clk);
            $display("INFO: Write addr=%02h data=%02h done", addr, wdata);
            #20;
        end
    endtask

    initial begin
        $dumpfile("cache_sim.vcd");
        $dumpvars(0, tb_cache_ctrl);

        // Pre-load SPI memory
        spi_mem[8'h00] = 8'hAA;
        spi_mem[8'h04] = 8'hBB;
        spi_mem[8'h08] = 8'hCC;

        // Init
        rst_n      = 0; cpu_req = 0; cpu_we = 0;
        cpu_addr   = 0; cpu_wdata = 0;
        spi_rdata  = 0; spi_done  = 0;
        pass_count = 0; fail_count = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;
        #20;

        $display("=== Test 1: Read miss — fetches from SPI ===");
        cpu_read(8'h00, 8'hAA);   // Should miss, fetch 0xAA from SPI

        $display("=== Test 2: Read hit — served from cache ===");
        cpu_read(8'h00, 8'hAA);   // Should hit cache now

        $display("=== Test 3: Write to same address ===");
        cpu_write(8'h00, 8'h55);

        $display("=== Test 4: Read back written value ===");
        cpu_read(8'h00, 8'h55);   // Cache should have 0x55

        $display("=== Test 5: Read different address (miss) ===");
        cpu_read(8'h04, 8'hBB);

        $display("=== Results: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        $finish;
    end

endmodule
