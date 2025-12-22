`timescale 1ns/1ps

module rgb2gray #(
    parameter WIDTH_P = 8
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [0:0] valid_i,
    input logic [0:0] ready_i,
    output logic [0:0] valid_o,
    output logic [0:0] ready_o,
    input logic [WIDTH_P-1:0] red_i,
    input logic [WIDTH_P-1:0] blue_i,
    input logic [WIDTH_P-1:0] green_i,
    output logic [WIDTH_P-1:0] gray_o
);

    // formula y = 0.299*red + 0.587*green + 0.114*blue
    // refer: https://www.sciencedirect.com/science/article/pii/S187705092031200X

    // 0.299 approximated with 0.28125 
    // (red*0.25 + red*0.03125) = (red >> 2) + (red >> 5)
    localparam int RED_SHIFT_1 = 2;
    localparam int RED_SHIFT_2 = 5;

    // 0.587 approximated with 0.5625
    // (green*0.5 + green*0.0625) = (green >> 1) + (green >> 4)
    localparam int GREEN_SHIFT_1 = 1;
    localparam int GREEN_SHIFT_2 = 4;

    // 0.114 approximated with 0.09375
    // (blue*0.0625 + blue*0.03125) = (blue >> 4) + (blue >> 5)
    // note: 2^-3 (blue >> 3) could also work but overweights blue
    localparam int BLUE_SHIFT_1 = 4;
    localparam int BLUE_SHIFT_2 = 5;

    logic [WIDTH_P-1:0] red_term, green_term, blue_term;
    logic [WIDTH_P:0] gray_acc;

    // approximate shifts as a mac shift operation
    always_comb begin
        red_term = (red_i >> RED_SHIFT_1) + (red_i >> RED_SHIFT_2);
        green_term = (green_i >> GREEN_SHIFT_1) + (green_i >> GREEN_SHIFT_2);
        blue_term = (blue_i >> BLUE_SHIFT_1) + (blue_i >> BLUE_SHIFT_2);

        gray_acc = red_term + green_term + blue_term;
    end

    // elastic
    elastic #(
        .WIDTH_P(WIDTH_P)
    ) rgb2gray_elastic (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(gray_acc[WIDTH_P-1:0]),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .valid_o(valid_o),
        .data_o(gray_o),
        .ready_i(ready_i)
    );

endmodule
