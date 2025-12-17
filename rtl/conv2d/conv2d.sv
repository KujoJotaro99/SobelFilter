`timescale 1ns/1ps

module conv2d #(
    parameter WIDTH_P = 8,
    parameter DEPTH_P = 16
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [0:0] valid_i,
    input logic [0:0] ready_i,
    input logic [WIDTH_P-1:0] data_i,
    output logic [0:0] valid_o,
    output logic [0:0] ready_o,
    output logic [(2*WIDTH_P)-1:0] data_o
)

    // elastic pipeline

    // sliding window 

    // line buffer 1

    // line buffer 2

    // sum

endmodule