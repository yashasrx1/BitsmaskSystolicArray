`timescale 1ns / 1ps

module post_proc_quant_unit (
    input  logic signed [31:0] raw_acc_in,
    input  logic signed [31:0] bias_in,
    output logic [7:0]         act_out_int8
);

    logic signed [31:0] biased_sum;
    logic signed [31:0] relu_out;
    logic signed [31:0] scaled_out;

    assign biased_sum = raw_acc_in + bias_in;
    assign relu_out   = (biased_sum < 32'sd0) ? 32'sd0 : biased_sum; // ReLU
    assign scaled_out = relu_out >>> 7;                            // Re-quantization Scale Shift

    assign act_out_int8 = (scaled_out > 32'sd127) ? 8'd127 : scaled_out[7:0];

endmodule
