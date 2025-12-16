`timescale 1ns/1ps

module ramdelaybuffer #(
    parameter WIDTH_P = 8,
    parameter DELAY_P = 12
) (
    input logic clk_i,
    input logic rstn_i,
    input logic valid_i,
    input logic ready_i,
    output logic valid_o,
    output logic ready_o,
    input logic [WIDTH_P-1:0] data_i,
    output logic [WIDTH_P-1:0] data_o
);

    logic [$clog2(DELAY_P+1)-1:0] wr_addr;
    logic [$clog2(DELAY_P+1)-1:0] rd_addr;

    counter #(
        .WIDTH_P($clog2(DELAY_P+1)),
        .MAX_VAL_P(DELAY_P),
        .SATURATE_P(0)
    ) wr_ptr_counter (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i($clog2(DELAY_P+1)'(DELAY_P)),
        .data_i('0),
        .up_i(valid_i & ready_o),
        .down_i(1'b0),
        .load_i((valid_i & ready_o) && (wr_addr == $clog2(DELAY_P+1)'(DELAY_P))),
        .en_i(1'b1),
        .count_o(wr_addr)
    );

    counter #(
        .WIDTH_P($clog2(DELAY_P+1)),
        .MAX_VAL_P(DELAY_P),
        .SATURATE_P(0)
    ) rd_ptr_counter (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i('0),
        .data_i('0),
        .up_i(valid_i & ready_o),
        .down_i(1'b0),
        .load_i((valid_i & ready_o) && (rd_addr == $clog2(DELAY_P+1)'(DELAY_P))),
        .en_i(1'b1),
        .count_o(rd_addr)
    );

    sync_ram_block #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(DELAY_P+1)
    ) sync_ram_delay (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(data_i),
        .wr_addr_i(wr_addr),
        .rd_addr_i(rd_addr),
        .wr_en_i(valid_i & ready_o),
        .rd_en_i(valid_i & ready_o),
        .data_o(data_o)
    );

    elastic #(
        .WIDTH_P(WIDTH_P)
    ) stream_pipe (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i('0),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .valid_o(valid_o),
        .data_o(),
        .ready_i(ready_i)
    );

endmodule
