/*
  elastic.sv: elastic pipeline module imported from CSE 225 curriculum UCSC
*/

`timescale 1ns/1ps

module elastic #( 
    parameter [31:0] WIDTH_P = 8
) (
    input [0:0] clk_i,
    input [0:0] rstn_i,

    input [WIDTH_P - 1:0] data_i,
    input [0:0] valid_i,
    output [0:0] ready_o,

    output [0:0] valid_o,
    output [WIDTH_P - 1:0] data_o, 
    input [0:0] ready_i
);

  logic [WIDTH_P - 1:0] data_o_l;
  always_ff @(posedge clk_i) begin
    if (!rstn_i) begin
      data_o_l <= 0;
    end else if (ready_o) begin
      data_o_l <= data_i;
    end
  end

  logic [0:0] valid_o_l;
  always_ff @(posedge clk_i) begin
    if (!rstn_i) begin
      valid_o_l <= 0;
    end else if (ready_o) begin
      valid_o_l <= ready_o & valid_i;
    end
  end

  assign ready_o = ~valid_o | ready_i;
  assign valid_o = valid_o_l;
  assign data_o = data_o_l;

endmodule
