`timescale 1ns / 1ps

module argmax_classifier (
    input  logic clk,
    input  logic rst_n,
    input  logic start_eval,
    input  logic signed [31:0] logit_in,
    input  logic [3:0] logit_idx,
    output logic [3:0] predicted_digit
);

    logic signed [31:0] max_logit;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_logit       <= -32'sd2147483648;
            predicted_digit <= 4'd0;
        end else if (start_eval) begin
            if (logit_idx == 4'd0) begin
                max_logit       <= logit_in;
                predicted_digit <= 4'd0;
            end else if (logit_in > max_logit) begin
                max_logit       <= logit_in;
                predicted_digit <= logit_idx;
            end
        end
    end

endmodule