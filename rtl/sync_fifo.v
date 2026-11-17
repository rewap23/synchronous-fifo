module sync_fifo #(
    parameter     DATA_WIDTH = 8,          // 8 bits of data per word
    parameter     DEPTH      = 8           // 8 storage slots
) (
    input wire                    clk,     // clock
    input wire                    rst,     // reset queue
    input wire                    wr_en,   // write enable
    input wire [DATA_WIDTH-1:0]   wr_data, // data going in
    input wire                    rd_en,   // read enable
    
    output reg [DATA_WIDTH-1:0]   rd_data, // data going out
    output wire                   full,    // return full if queue full
    output wire                   empty    // return empty if queue empty
    
); 
    // Calculating memory array using log base 2
    localparam ADDR_WIDTH = $clog2(DEPTH);

    // 
    reg [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    // Write and read register pointers
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    // Updated the write and read register pointers in a clocked block
    always @(posedge clk) begin 
        if (rst) begin 
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin 
            if (wr_en && !full) begin 
                if (wr_ptr == DEPTH - 1) 
                    wr_ptr <= 0;
                else 
                    wr_ptr <= wr_ptr + 1'b1;
            end
            if (rd_en && !empty) begin 
                if (rd_ptr == DEPTH - 1) 
                    rd_ptr <= 0;
                else 
                    rd_ptr <= rd_ptr + 1'b1;

            end
        end
    end



endmodule