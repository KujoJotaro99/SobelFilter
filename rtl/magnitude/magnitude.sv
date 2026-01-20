`timescale 1ns/1ps

module magnitude 
#(
    parameter WIDTH_P = 8
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [0:0] valid_i,
    input logic [0:0] ready_i,
    input logic [WIDTH_P-1:0] gx_i,
    input logic [WIDTH_P-1:0] gy_i,
    output logic [0:0] valid_o,
    output logic [0:0] ready_o,
    output logic [2*WIDTH_P-1:0] mag_o
);
    logic [2*WIDTH_P-1:0] mag_w;

    // note: check dsp synth inderence 
    // sqrt(x^2 + y^2) for x > y > 0
    // x * sqrt(1 + (y/x)^2)
    // x * sqrt(1 + r^2) contrained to x*[1, sqrt(2)]
    // x * (1 + kr)
    // x + ky
    // 1+k(1) = sqrt(2) at r = 1, the bound is sqrt(2) so k must be sqrt(2) - 1
    // approximate to 0.5 for shift purposes
    always_comb begin
        if (!rstn_i) begin
            mag_w = '0;
        end else begin
            mag_w = (gx_i >= gy_i) ? (gx_i + (gy_i >> 1)) : (gy_i + (gx_i >> 1));
        end
    end

    elastic #(
        .WIDTH_P(2*WIDTH_P)
    ) magnitude_elastic (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(mag_w),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .valid_o(valid_o),
        .data_o(mag_o),
        .ready_i(ready_i)
    );

endmodule
