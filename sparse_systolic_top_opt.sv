`timescale 1ns / 1ps

module sparse_systolic_top_opt (
    input  logic clk,
    input  logic rst_n,
    input  logic start_pulse,
    
    output logic m_axis_results_tvalid,
    output logic [3:0] predicted_digit,
    output logic accel_done
);

    // FSM Control Signals
    logic clear_acc, pe_enable, act_valid_stream, fc2_enable;
    logic [1:0]  tile_idx;
    logic [9:0]  act_addr;
    logic [11:0] weight_addr;
    logic [3:0]  fc2_neuron_idx;

    sparse_accel_ctrl_fsm_opt ctrl_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .start_pulse(start_pulse),
        .clear_acc(clear_acc),
        .pe_enable(pe_enable),
        .tile_idx(tile_idx),
        .act_addr(act_addr),
        .weight_addr(weight_addr),
        .act_valid_stream(act_valid_stream),
        .fc2_enable(fc2_enable),
        .fc2_neuron_idx(fc2_neuron_idx),
        .m_axis_results_tvalid(m_axis_results_tvalid),
        .accel_done(accel_done)
    );

    // Activation RAM (784 Bytes)
    logic signed [7:0] raw_act_data;
    lutram_stream_queue #(.DATA_WIDTH(8), .DEPTH(784)) act_queue (
        .clk(clk), .rst_n(rst_n), .write_en(1'b0), .write_addr(10'd0),
        .write_data(8'sd0), .read_en(pe_enable), .read_addr(act_addr),
        .read_data(raw_act_data)
    );

    // FC1 Weight Buffer (3136 Words)
    logic [3:0] bitmask_out;
    logic signed [7:0] weights_out [0:3];
    weight_bitmask_buffer #(.DEPTH(3136)) weight_buf (
        .clk(clk), .rst_n(rst_n), .addr(weight_addr),
        .bitmask_out(bitmask_out), .weight_out(weights_out)
    );

    // Skew Buffers
    logic signed [7:0] skewed_act [0:3];
    logic skewed_valid [0:3];
    logic signed [7:0] skewed_weight [0:3];
    logic [3:0] skewed_bitmask;
    logic unused_w_valid [0:3], unused_b_valid [0:3];

    generate
        for (genvar i = 0; i < 4; i++) begin : gen_skew
            srl_skew_buffer #(.DATA_WIDTH(8), .SKEW_DEPTH(i)) act_skew_inst (
                .clk(clk), .rst_n(rst_n), .data_in(raw_act_data),
                .valid_in(act_valid_stream), .data_out(skewed_act[i]), .valid_out(skewed_valid[i])
            );
            srl_skew_buffer #(.DATA_WIDTH(8), .SKEW_DEPTH(i)) weight_skew_inst (
                .clk(clk), .rst_n(rst_n), .data_in(weights_out[i]),
                .valid_in(act_valid_stream), .data_out(skewed_weight[i]), .valid_out(unused_w_valid[i])
            );
            srl_skew_buffer #(.DATA_WIDTH(1), .SKEW_DEPTH(i)) bitmask_skew_inst (
                .clk(clk), .rst_n(rst_n), .data_in(bitmask_out[i]),
                .valid_in(act_valid_stream), .data_out(skewed_bitmask[i]), .valid_out(unused_b_valid[i])
            );
        end
    endgenerate

    // Systolic Array Interconnect Wires
    logic signed [7:0] pe_act_wire [0:3][0:4];
    logic pe_valid_wire [0:3][0:4];
    logic signed [31:0] pe_acc_wire [0:3][0:3];

    generate
        for (genvar j = 0; j < 4; j++) begin : gen_input_conn
            assign pe_act_wire[j][0]   = skewed_act[j];
            assign pe_valid_wire[j][0] = skewed_valid[j];
        end
    endgenerate

    generate
        for (genvar r = 0; r < 4; r++) begin : gen_row
            for (genvar c = 0; c < 4; c++) begin : gen_col
                sparse_pe_opt #(.ACT_WIDTH(8), .WEIGHT_WIDTH(8), .ACC_WIDTH(32)) pe_inst (
                    .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc), .pe_enable(pe_enable),
                    .act_in(pe_act_wire[r][c]), .act_valid_in(pe_valid_wire[r][c]),
                    .weight_in(skewed_weight[r]), .bitmask_bit(skewed_bitmask[r]),
                    .act_out(pe_act_wire[r][c+1]), .act_valid_out(pe_valid_wire[r][c+1]),
                    .acc_out(pe_acc_wire[r][c])
                );
            end
        end
    endgenerate

    // FC1 Biases & Post-Processing Storage
    logic signed [31:0] bias_fc1_mem [0:15];
    logic [7:0] fc1_act_ram [0:15];

    // Latch Post-Processed FC1 Activations cleanly on tile completion
    always_ff @(posedge clk) begin
        if (ctrl_fsm.state == ctrl_fsm.CHECK_FC1_TILE) begin
            for (int k = 0; k < 4; k++) begin
                automatic logic signed [31:0] raw_sum;
                automatic logic signed [31:0] relu_val;
                automatic logic signed [31:0] shifted_val;
                
                raw_sum     = pe_acc_wire[k][0] + bias_fc1_mem[{tile_idx, k[1:0]}];
                relu_val    = (raw_sum < 32'sd0) ? 32'sd0 : raw_sum;
                shifted_val = relu_val >>> 7;
                
                fc1_act_ram[{tile_idx, k[1:0]}] <= (shifted_val > 32'sd127) ? 8'd127 : shifted_val[7:0];
            end
        end
    end

    // FC2 Memory (1D Array fixes Vivado $readmemh 2D array bug)
    logic signed [7:0]  weights_fc2_mem [0:159];
    logic signed [31:0] bias_fc2_mem [0:9];
    logic signed [31:0] fc2_logit_calc;

    // Linear Bit-Slice Indexing: {fc2_neuron_idx (4 bits), m (4 bits)} = n * 16 + m
    always_comb begin
        fc2_logit_calc = bias_fc2_mem[fc2_neuron_idx];
        for (int m = 0; m < 16; m++) begin
            fc2_logit_calc = fc2_logit_calc + 
                ($signed(fc1_act_ram[m]) * $signed(weights_fc2_mem[{fc2_neuron_idx, m[3:0]}]));
        end
    end

    // Argmax Classification Unit
    argmax_classifier argmax_inst (
        .clk(clk), .rst_n(rst_n), .start_eval(fc2_enable),
        .logit_in(fc2_logit_calc), .logit_idx(fc2_neuron_idx),
        .predicted_digit(predicted_digit)
    );

endmodule