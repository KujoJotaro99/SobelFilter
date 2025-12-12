`timescale 1ns/1ps

module full_add(
    input logic [0:0] a_i,
    input logic [0:0] b_i,
    input logic [0:0] cin_i,
    output logic [0:0] sum_o,
    output logic [0:0] carry_o
);

    wire [0:0] wire_sum1;
    wire [0:0] wire_carry1;
    wire [0:0] wire_carry2;

    half_add ha1 (
        .a_i(a_i),
        .b_i(b_i),
        .sum_o(wire_sum1),
        .carry_o(wire_carry1)
    );

    half_add ha2 (
        .a_i(wire_sum1),
        .b_i(cin_i),
        .sum_o(sum_o),
        .carry_o(wire_carry2)
    );

    assign carry_o = wire_carry1 | wire_carry2;

endmodule


