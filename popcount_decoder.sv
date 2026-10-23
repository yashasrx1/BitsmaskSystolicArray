`timescale 1ns / 1ps

module popcount_decoder (
    input  logic [3:0] bitmask,
    output logic [2:0] non_zero_count
);
    always_comb begin
        non_zero_count = 3'd0;
        for (int i = 0; i < 4; i++) begin
            if (bitmask[i]) non_zero_count = non_zero_count + 1'b1;
        end
    end
endmodule