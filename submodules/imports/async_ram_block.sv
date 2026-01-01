`timescale 1ns/1ps

module async_ram_1r1w #(
    parameter WIDTH_P = 8,
    parameter DEPTH_P = 512,
    parameter filename_p = ""
) (
    input  logic wr_clk_i,
    input  logic wr_rstn_i,
    input  logic wr_en_i,
    input  logic [WIDTH_P-1:0] wr_data_i,
    input  logic [$clog2(DEPTH_P)-1:0] wr_addr_i,

    input  logic rd_clk_i,
    input  logic rd_rstn_i,
    input  logic rd_en_i,
    input  logic [$clog2(DEPTH_P)-1:0] rd_addr_i,
    output logic [WIDTH_P-1:0] rd_data_o
);

    logic [WIDTH_P-1:0] mem_array [DEPTH_P-1:0];
    logic [WIDTH_P-1:0] rd_data_l;

    initial begin
        if (filename_p != "") begin
            $readmemb(filename_p, mem_array);
        end
        for (int i = 0; i < DEPTH_P; i++) begin
            $dumpvars(0, mem_array[i]);
        end
        $display("%m: depth_p is %d, width_p is %d", DEPTH_P, WIDTH_P);
    end

    always_ff @(posedge wr_clk_i) begin
        if (!wr_rstn_i) begin
        end else if (wr_en_i) begin
            mem_array[wr_addr_i] <= wr_data_i;
        end
    end

    always_ff @(posedge rd_clk_i) begin
        if (!rd_rstn_i) begin
            rd_data_l <= '0;
        end else if (rd_en_i) begin
            rd_data_l <= mem_array[rd_addr_i];
        end
    end

    assign rd_data_o = rd_data_l;

endmodule
