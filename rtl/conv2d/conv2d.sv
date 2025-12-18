`timescale 1ns/1ps

module conv2d #(
    parameter WIDTH_P = 8,
    parameter DEPTH_P = 16,
    parameter BUFF_SIZE = 9
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [0:0] valid_i,
    input logic [0:0] ready_i,
    input logic [WIDTH_P-1:0] data_i,
    output logic [0:0] valid_o,
    output logic [0:0] ready_o,
    output logic [(2*WIDTH_P)-1:0] data_o
);

    // elastic pipeline
    elastic #(
        .WIDTH_P(WIDTH_P)
    ) stream_pipe
    (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i('0),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .valid_o(valid_o),
        .data_o(),
        .ready_i(ready_i)
    );

    logic [WIDTH_P-1:0] conv_window [2:0][2:0];
    logic [WIDTH_P-1:0] line_buf1_o;
    logic [WIDTH_P-1:0] line_buf2_o;

    int row;
    int col;
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            for (row = 0; row < 3; row++) begin
                for (col = 0; col < 3; col++) begin
                    conv_window[row][col] <= '0;
                end
            end
        end else if (valid_i & ready_o) begin
            conv_window[0][2] <= conv_window[0][1];
            conv_window[0][1] <= conv_window[0][0];
            conv_window[0][0] <= line_buf2_o;

            conv_window[1][2] <= conv_window[1][1];
            conv_window[1][1] <= conv_window[1][0];
            conv_window[1][0] <= line_buf1_o;

            conv_window[2][2] <= conv_window[2][1];
            conv_window[2][1] <= conv_window[2][0];
            conv_window[2][0] <= data_i;
        end
    end

    // line buffer 1
    ramdelaybuffer #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(DEPTH_P-1)
    ) conv2d_ramdelay_1_inst (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i & ready_o),
        .ready_i(1'b1),
        .valid_o(),
        .ready_o(),
        .data_i(data_i),
        .data_o(line_buf1_o)
    );

    // line buffer 2
    ramdelaybuffer #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(DEPTH_P-1)
    ) conv2d_ramdelay_2_inst (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i & ready_o),
        .ready_i(1'b1),
        .valid_o(),
        .ready_o(),
        .data_i(line_buf1_o),
        .data_o(line_buf2_o)
    );

    // assign data_o = 
    //   {{WIDTH_P{1'b0}}, conv_window[2][0]} +
    //   {{WIDTH_P{1'b0}}, conv_window[2][1]} +
    //   {{WIDTH_P{1'b0}}, conv_window[2][2]} +
    //   {{WIDTH_P{1'b0}}, conv_window[1][0]} +
    //   {{WIDTH_P{1'b0}}, conv_window[1][1]} +
    //   {{WIDTH_P{1'b0}}, conv_window[1][2]} +
    //   {{WIDTH_P{1'b0}}, conv_window[0][0]} +
    //   {{WIDTH_P{1'b0}}, conv_window[0][1]} +
    //   {{WIDTH_P{1'b0}}, conv_window[0][2]};

    logic [2*WIDTH_P-1:0] sum_chain [BUFF_SIZE-1:0];

    assign sum_chain[0] = {{WIDTH_P{1'b0}}, conv_window[0][0]};

    genvar t;
    generate
        for (t = 0; t < BUFF_SIZE-1; t++) begin : gen_add_chain
            localparam int TAP_ROW = (t+1) / 3;
            localparam int TAP_COL = (t+1) % 3;
            add #(
                .WIDTH_P(2*WIDTH_P)
            ) window_sum_add (
                .a_i(sum_chain[t]),
                .b_i({{WIDTH_P{1'b0}}, conv_window[TAP_ROW][TAP_COL]}), // sum of all older chains
                .cin_i(1'b0),
                .sum_o(sum_chain[t+1]),
                .carry_o()
            );
        end
    endgenerate

    // newest chain is sum of all old values
    assign data_o = sum_chain[BUFF_SIZE-1];

endmodule
