`timescale 1ns/1ps

module sync_fifo_tb;

    // ---------------- 1. Parameters & signals ----------------
    localparam DATA_WIDTH = 8;
    localparam DEPTH      = 8;

    reg                   clk;
    reg                   rst;
    reg                   wr_en;
    reg  [DATA_WIDTH-1:0] wr_data;
    reg                   rd_en;
    wire [DATA_WIDTH-1:0] rd_data;
    wire                  full;
    wire                  empty;

    // ---------------- 2. Instantiate the DUT (Design Under Test) ----------------
    sync_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .wr_data(wr_data),
        .rd_en(rd_en), .rd_data(rd_data),
        .full(full), .empty(empty)
    );

    // ---------------- 3. Clock: 10 ns period ----------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------- 4. Reference model (a software queue) ----------------
    reg [DATA_WIDTH-1:0] model_q [0:1023];
    integer head = 0;          // index of oldest item
    integer tail = 0;          // index where next item goes
    integer errors = 0;

    // ---------------- 5. Coverage counters ----------------
    integer cov_full = 0, cov_empty = 0, cov_wr_full = 0;
    integer cov_rd_empty = 0, cov_both = 0;

    // ---------------- 6. Helper task: one clock cycle of stimulus ----------------
    // Drives inputs, updates the model, checks DUT outputs after the edge.
    task do_cycle(input w, input r, input [DATA_WIDTH-1:0] d);
        reg will_write, will_read;
        begin
            @(negedge clk);                 // change inputs away from the rising edge
            wr_en = w; rd_en = r; wr_data = d;

            // Predict what the FIFO SHOULD do this cycle
            will_write = w && !full;
            will_read  = r && !empty;

            // Coverage
            if (full)          cov_full     = cov_full + 1;
            if (empty)         cov_empty    = cov_empty + 1;
            if (w && full)     cov_wr_full  = cov_wr_full + 1;
            if (r && empty)    cov_rd_empty = cov_rd_empty + 1;
            if (will_write && will_read) cov_both = cov_both + 1;

            if (will_write) begin
                model_q[tail % 1024] = d;
                tail = tail + 1;
            end

            @(posedge clk); #1;             // let the DUT update

            // Check read data (1-cycle latency: valid right after the edge)
            if (will_read) begin
                if (rd_data !== model_q[head % 1024]) begin
                    $display("ERROR @%0t: rd_data=%0h expected=%0h", $time, rd_data, model_q[head % 1024]);
                    errors = errors + 1;
                end
                head = head + 1;
            end

            // Check flags against the model
            if (empty !== (tail - head == 0)) begin
                $display("ERROR @%0t: empty=%b, model count=%0d", $time, empty, tail-head);
                errors = errors + 1;
            end
            if (full !== (tail - head == DEPTH)) begin
                $display("ERROR @%0t: full=%b, model count=%0d", $time, full, tail-head);
                errors = errors + 1;
            end

            wr_en = 0; rd_en = 0;
        end
    endtask

    // ---------------- 7. The tests ----------------
    integer i;
    initial begin
        $dumpfile("sync_fifo.vcd");     // waveform file for GTKWave
        $dumpvars(0, sync_fifo_tb);

        // Reset
        wr_en = 0; rd_en = 0; wr_data = 0; rst = 1;
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 0;

        // Test 1: after reset
        $display("Test 1: reset state");
        if (empty !== 1 || full !== 0) begin
            $display("ERROR: after reset empty=%b full=%b", empty, full);
            errors = errors + 1;
        end

        // Test 2: write one, read one
        $display("Test 2: write one, read one");
        do_cycle(1, 0, 8'hA5);
        do_cycle(0, 1, 8'h00);

        // Test 3: fill until full
        $display("Test 3: fill to full");
        for (i = 0; i < DEPTH; i = i + 1) do_cycle(1, 0, i + 8'h10);

        // Test 4: write while full (must be ignored)
        $display("Test 4: write while full");
        do_cycle(1, 0, 8'hFF);

        // Test 5: drain until empty (order must match)
        $display("Test 5: drain to empty");
        for (i = 0; i < DEPTH; i = i + 1) do_cycle(0, 1, 8'h00);

        // Test 6: read while empty (must be ignored)
        $display("Test 6: read while empty");
        do_cycle(0, 1, 8'h00);

        // Test 7: wraparound - fill, drain half, fill again, drain all
        $display("Test 7: wraparound");
        for (i = 0; i < DEPTH; i = i + 1)   do_cycle(1, 0, i + 8'h20);
        for (i = 0; i < DEPTH/2; i = i + 1) do_cycle(0, 1, 8'h00);
        for (i = 0; i < DEPTH/2; i = i + 1) do_cycle(1, 0, i + 8'h30);
        for (i = 0; i < DEPTH; i = i + 1)   do_cycle(0, 1, 8'h00);

        // Test 8: simultaneous read + write (half full)
        $display("Test 8: simultaneous read+write");
        for (i = 0; i < DEPTH/2; i = i + 1) do_cycle(1, 0, i + 8'h40);
        for (i = 0; i < 10; i = i + 1)      do_cycle(1, 1, i + 8'h50);

        // Test 9: random stress
        $display("Test 9: random (5000 cycles)");
        for (i = 0; i < 5000; i = i + 1) do_cycle($random, $random, $random);

        // EDGE CASE TESTS
        // Test 10: simultaneous read + write while empty
        $display("Test 10: simultaneous read+write empty");
        while (!empty) do_cycle(0, 1, 8'h00);
        do_cycle(1, 1, 8'hA1);
        do_cycle(0, 1, 8'h00);

        // Test 11: simultaneous read + write while full
        $display("Test 11: simultaneous read+write full");
        for (i = 0; i < DEPTH; i = i + 1)
            do_cycle(1, 0, i + 8'h60);
        do_cycle(1, 1, 8'hEE);
        for (i = 0; i < DEPTH-1; i = i + 1)
            do_cycle(0, 1, 8'h00);

        

        // ---------------- 8. Report ----------------
        $display("--------------------------------");
        $display("Coverage: full=%0d empty=%0d write_when_full=%0d read_when_empty=%0d both=%0d",
                 cov_full, cov_empty, cov_wr_full, cov_rd_empty, cov_both);
        if (errors == 0) $display("PASS: all checks passed");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule