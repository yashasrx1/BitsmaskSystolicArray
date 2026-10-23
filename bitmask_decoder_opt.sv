`timescale 1ns / 1ps

module bitmask_decoder_opt (
    input  logic [3:0] bitmask,
    output logic [3:0] is_active
);
    assign is_active = bitmask;
endmodule