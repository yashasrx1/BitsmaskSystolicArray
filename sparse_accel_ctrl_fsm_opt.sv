`timescale 1ns / 1ps

module sparse_accel_ctrl_fsm_opt (
    input  logic clk,
    input  logic rst_n,
    input  logic start_pulse,
    
    output logic clear_acc,
    output logic pe_enable,
    output logic [1:0]  tile_idx,
    output logic [9:0]  act_addr,
    output logic [11:0] weight_addr,
    output logic act_valid_stream,
    output logic fc2_enable,
    output logic [3:0]  fc2_neuron_idx,
    output logic m_axis_results_tvalid,
    output logic accel_done
);

    typedef enum logic [2:0] {
        IDLE            = 3'b000,
        INIT_ACC        = 3'b001,
        STREAM_TILE     = 3'b010,
        DRAIN_PIPELINE  = 3'b011,
        CHECK_FC1_TILE  = 3'b100,
        EXECUTE_FC2     = 3'b101,
        DONE            = 3'b110
    } state_t;

    state_t state, next_state;

    logic [9:0] col_cnt;
    logic [1:0] tile_cnt;
    logic [3:0] drain_cnt;
    logic [3:0] fc2_cnt;

    assign tile_idx       = tile_cnt;
    assign fc2_neuron_idx = fc2_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            col_cnt   <= '0;
            tile_cnt  <= '0;
            drain_cnt <= '0;
            fc2_cnt   <= '0;
        end else begin
            state <= next_state;
            
            if (state == STREAM_TILE) begin
                col_cnt <= col_cnt + 1'b1;
            end else if (state == INIT_ACC || state == IDLE) begin
                col_cnt <= '0;
            end

            if (state == DRAIN_PIPELINE) begin
                drain_cnt <= drain_cnt + 1'b1;
            end else begin
                drain_cnt <= '0;
            end

            if (state == CHECK_FC1_TILE) begin
                tile_cnt <= tile_cnt + 1'b1;
            end else if (state == IDLE) begin
                tile_cnt <= '0;
            end

            if (state == EXECUTE_FC2) begin
                fc2_cnt <= fc2_cnt + 1'b1;
            end else if (state == IDLE) begin
                fc2_cnt <= '0;
            end
        end
    end

    // Linear Address Generation (Stride = 784 per tile)
    always_comb begin
        next_state             = state;
        clear_acc              = 1'b0;
        pe_enable              = 1'b0;
        act_valid_stream       = 1'b0;
        fc2_enable             = 1'b0;
        m_axis_results_tvalid  = 1'b0;
        accel_done             = 1'b0;
        act_addr               = col_cnt;

        case (tile_cnt)
            2'd0:    weight_addr = 12'd0    + col_cnt;
            2'd1:    weight_addr = 12'd784  + col_cnt;
            2'd2:    weight_addr = 12'd1568 + col_cnt;
            2'd3:    weight_addr = 12'd2352 + col_cnt;
            default: weight_addr = 12'd0    + col_cnt;
        endcase

        case (state)
            IDLE: begin
                if (start_pulse) next_state = INIT_ACC;
            end

            INIT_ACC: begin
                clear_acc  = 1'b1;
                next_state = STREAM_TILE;
            end

            STREAM_TILE: begin
                pe_enable        = 1'b1;
                act_valid_stream = 1'b1;
                if (col_cnt == 10'd783) next_state = DRAIN_PIPELINE;
            end

            DRAIN_PIPELINE: begin
                pe_enable = 1'b1;
                if (drain_cnt == 4'd8) next_state = CHECK_FC1_TILE;
            end

            CHECK_FC1_TILE: begin
                if (tile_cnt == 2'd3) next_state = EXECUTE_FC2;
                else                  next_state = INIT_ACC;
            end

            EXECUTE_FC2: begin
                fc2_enable = 1'b1;
                if (fc2_cnt == 4'd9) next_state = DONE;
            end

            DONE: begin
                accel_done            = 1'b1;
                m_axis_results_tvalid = 1'b1;
                if (start_pulse) next_state = INIT_ACC;
                else             next_state = DONE;
            end

            default: next_state = IDLE;
        endcase
    end

endmodule