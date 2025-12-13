`timescale 1ns/1ps

module ramdelaybuffer #(
    parameter WIDTH_P = 8, 
    parameter DELAY_P = 8
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [WIDTH_P-1:0] data_i,
    output logic [WIDTH_P-1:0] data_o,
);

    // counter
    logic [$clog2(depth_p)-1:0] wr_addr_i;
    logic [$clog2(depth_p)-1:0] rd_addr_i;

    // synchronous memory buffer
    sync_ram_block #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(DELAY_P)
    ) sync_ram_delay (
        .clk_i(),
        .rstn_i(),
        .data_i(),
        .wr_addr_i(),
        .rd_addr_i(),
        .wr_en_i(),
        .rd_en_i(),
        .data_o()
    );

endmodule