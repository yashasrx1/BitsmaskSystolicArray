`timescale 1ns / 1ps

module weight_bitmask_buffer #(
    parameter int DEPTH = 3136
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [11:0] addr,
    output logic [3:0] bitmask_out,
    output logic signed [7:0] weight_out [0:3]
);

    // 36-bit memory word: [35:32] bitmask (4 bits), [31:0] weights (4 x INT8)
    logic [35:0] mem [0:DEPTH-1];
    logic [35:0] read_data;

    // Combinational read matches LUTRAM activation queue timing exactly
    assign read_data = mem[addr];

    assign bitmask_out   = read_data[35:32];
    assign weight_out[0] = $signed(read_data[31:24]);
    assign weight_out[1] = $signed(read_data[23:16]);
    assign weight_out[2] = $signed(read_data[15:8]);
    assign weight_out[3] = $signed(read_data[7:0]);

endmodule