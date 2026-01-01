`timescale 1ns/1ps

module fifo_sync #(
    parameter WIDTH_P = 8,
    parameter DEPTH_P = 16
) (
    input logic [0:0] pclk_i, 
    input logic [0:0] cclk_i,
    input logic [0:0] rstn_i,
    input logic [WIDTH_P-1:0] data_i,
    input logic [0:0] valid_i, 
    input logic [0:0] ready_i,
    output logic [0:0] valid_o, 
    output logic [0:0] ready_o,
    output logic [WIDTH_P-1:0] data_o
);

    logic [$clog2(DEPTH_P):0] wr_ptr_l, rd_ptr_l, rd_ptr_next_w;
    logic [$clog2(DEPTH_P):0] wr_ptr_gray, wr_ptr_gray_sync, wr_ptr_sync;
    logic [$clog2(DEPTH_P):0] rd_ptr_gray, rd_ptr_gray_sync, rd_ptr_sync;


    // full empty and bypass logic
    assign valid_o = (wr_ptr_sync[$clog2(DEPTH_P):0] != rd_ptr_l[$clog2(DEPTH_P):0]); // not empty
    assign ready_o = ~((wr_ptr_l[$clog2(DEPTH_P)] != rd_ptr_sync[$clog2(DEPTH_P)]) && (wr_ptr_l[$clog2(DEPTH_P)-1:0] == rd_ptr_sync[$clog2(DEPTH_P)-1:0])); // not full

    // next ptr logic
    always_comb begin
        if (!rstn_i) begin
            rd_ptr_next_w = '0;
        end else if (valid_o & ready_i) begin
            rd_ptr_next_w = rd_ptr_l + 1'b1;
        end else begin
            rd_ptr_next_w = rd_ptr_l;
        end
    end

    // curr ptr logic
    always_ff @(posedge pclk_i) begin
        if (!rstn_i) begin
            wr_ptr_l <= '0;
        end else if (valid_i & ready_o) begin
            wr_ptr_l <= wr_ptr_l + 1'b1;
        end
    end

    always_ff @(posedge cclk_i) begin
        if (!rstn_i) begin
            rd_ptr_l <= '0;
        end else if (valid_o & ready_i) begin
            rd_ptr_l <= rd_ptr_l + 1'b1;
        end
    end

    async_ram_1r1w #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(DEPTH_P)
    ) fifo_ram (
        .wr_clk_i(pclk_i),
        .wr_rstn_i(rstn_i),
        .wr_en_i(valid_i & ready_o),
        .wr_data_i(data_i),
        .wr_addr_i(wr_ptr_l[$clog2(DEPTH_P)-1:0]),
        .rd_clk_i(cclk_i),
        .rd_rstn_i(rstn_i),
        .rd_en_i(1'b1),
        .rd_addr_i(rd_ptr_next_w[$clog2(DEPTH_P)-1:0]),
        .rd_data_o(data_o)
    );

    Nbin2gray #(.N($clog2(DEPTH_P)+1)) wrgray (.bin_i(wr_ptr_l), .gray_o(wr_ptr_gray));
    sync2 #(.width($clog2(DEPTH_P)+1)) wr_to_rd (.rstn_i(rstn_i), .clk_sync_i(cclk_i), .sync_i(wr_ptr_gray), .sync_o(wr_ptr_gray_sync));
    Ngray2bin #(.N($clog2(DEPTH_P)+1)) wrsync (.bin_o(wr_ptr_sync), .gray_i(wr_ptr_gray_sync));

    Nbin2gray #(.N($clog2(DEPTH_P)+1)) rdgray (.bin_i(rd_ptr_l), .gray_o(rd_ptr_gray));
    sync2 #(.width($clog2(DEPTH_P)+1)) rd_to_wr (.rstn_i(rstn_i), .clk_sync_i(pclk_i), .sync_i(rd_ptr_gray), .sync_o(rd_ptr_gray_sync));
    Ngray2bin #(.N($clog2(DEPTH_P)+1)) rdsync (.bin_o(rd_ptr_sync), .gray_i(rd_ptr_gray_sync));

endmodule
