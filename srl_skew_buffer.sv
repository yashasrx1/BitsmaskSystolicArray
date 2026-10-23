`timescale 1ns / 1ps

module srl_skew_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int SKEW_DEPTH = 0
) (
    input  logic clk,
    input  logic rst_n,
    input  logic signed [DATA_WIDTH-1:0] data_in,
    input  logic valid_in,
    output logic signed [DATA_WIDTH-1:0] data_out,
    output logic valid_out
);

    if (SKEW_DEPTH == 0) begin : gen_passthrough
        assign data_out  = data_in;
        assign valid_out = valid_in;
    end else begin : gen_skew_srl
        logic signed [DATA_WIDTH-1:0] shift_data [0:SKEW_DEPTH-1];
        logic shift_valid [0:SKEW_DEPTH-1];

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                for (int i = 0; i < SKEW_DEPTH; i++) begin
                    shift_data[i]  <= '0;
                    shift_valid[i] <= 1'b0;
                end
            end else begin
                shift_data[0]  <= data_in;
                shift_valid[0] <= valid_in;
                for (int i = 1; i < SKEW_DEPTH; i++) begin
                    shift_data[i]  <= shift_data[i-1];
                    shift_valid[i] <= shift_valid[i-1];
                end
            end
        end

        assign data_out  = shift_data[SKEW_DEPTH-1];
        assign valid_out = shift_valid[SKEW_DEPTH-1];
    end

endmodule