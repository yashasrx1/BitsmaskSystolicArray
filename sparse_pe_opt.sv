`timescale 1ns / 1ps

module sparse_pe_opt #(
    parameter int ACT_WIDTH    = 8,
    parameter int WEIGHT_WIDTH = 8,
    parameter int ACC_WIDTH    = 32
) (
    input  logic clk,
    input  logic rst_n,
    
    input  logic clear_acc,
    input  logic pe_enable,
    
    input  logic signed [ACT_WIDTH-1:0]    act_in,
    input  logic                            act_valid_in,
    input  logic signed [WEIGHT_WIDTH-1:0] weight_in,
    input  logic                            bitmask_bit,
    
    output logic signed [ACT_WIDTH-1:0]    act_out,
    output logic                            act_valid_out,
    output logic signed [ACC_WIDTH-1:0]    acc_out
);

    logic compute_valid;
    // Dual-Sparsity Gating: Gate if weight bitmask == 0 OR input activation == 0
    assign compute_valid = pe_enable & act_valid_in & bitmask_bit & (act_in != 8'sd0);

    logic signed [ACT_WIDTH+WEIGHT_WIDTH-1:0] mult_reg;
    logic                                     mult_valid_reg;
    logic                                     clear_acc_q;

    // Stage 1: DSP48 Multiplier Register with Clock Enable Gating
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_reg        <= '0;
            mult_valid_reg <= 1'b0;
            clear_acc_q     <= 1'b0;
        end else begin
            clear_acc_q <= clear_acc;
            if (pe_enable) begin
                if (compute_valid) begin
                    mult_reg <= $signed(act_in) * $signed(weight_in);
                end else begin
                    mult_reg <= 16'sd0;
                end
                mult_valid_reg <= compute_valid;
            end else begin
                mult_valid_reg <= 1'b0;
            end
        end
    end

    // Stage 2: Accumulator
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= '0;
        end else if (clear_acc_q) begin
            acc_out <= mult_valid_reg ? 32'(signed'(mult_reg)) : '0;
        end else if (mult_valid_reg) begin
            acc_out <= acc_out + 32'(signed'(mult_reg));
        end
    end

    // Activation Forwarding
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_out        <= '0;
            act_valid_out <= 1'b0;
        end else if (pe_enable) begin
            act_out        <= act_in;
            act_valid_out <= act_valid_in;
        end else begin
            act_valid_out <= 1'b0;
        end
    end

endmodule
