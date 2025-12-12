`timescale 1ns/1ps

module half_add(
    input logic [0:0] a_i,
    input logic [0:0] b_i,
    output logic [0:0] sum_o,
    output logic [0:0] carry_o
);

    always_comb begin
        sum_o = a_i ^ b_i;
        carry_o = a_i & b_i;
    end

endmodule


