`timescale 1ns / 1ps

module lutram_stream_queue #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 784
) (
    input  logic clk,
    input  logic rst_n,
    input  logic write_en,
    input  logic [9:0] write_addr,
    input  logic signed [DATA_WIDTH-1:0] write_data,
    
    input  logic read_en,
    input  logic [9:0] read_addr,
    output logic signed [DATA_WIDTH-1:0] read_data
);

    logic signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (write_en) begin
            mem[write_addr] <= write_data;
        end
    end

    assign read_data = mem[read_addr];

endmodule