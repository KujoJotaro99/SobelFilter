`timescale 1ns/1ps
module sync_ram_block #(
    parameter WIDTH_P = 32, 
    parameter DEPTH_P = 128, 
    parameter filename_p = ""
) (
    input logic clk_i,
    input logic rstn_i,
    input logic [WIDTH_P-1:0] data_i,
    input logic [$clog2(DEPTH_P)-1:0] wr_addr_i,
    input logic [$clog2(DEPTH_P)-1:0] rd_addr_a_i,
    input logic [$clog2(DEPTH_P)-1:0] rd_addr_b_i,
    input logic wr_en_i,
    input logic rd_en_a_i,
    input logic rd_en_b_i,
    output logic [WIDTH_P-1:0] data_a_o,
    output logic [WIDTH_P-1:0] data_b_o
);

    logic [WIDTH_P-1:0] mem_array [DEPTH_P-1:0];
    logic [$clog2(DEPTH_P)-1:0] rd_addr_a_r;
    logic [$clog2(DEPTH_P)-1:0] rd_addr_b_r;
    
    initial begin
        if (filename_p != "") begin
            $readmemb(filename_p, mem_array);
        end
        $display("%m: depth_p is %d, width_p is %d", DEPTH_P, WIDTH_P);
    end
    
    always_ff @(posedge clk_i) begin
        if (wr_en_i) begin
            mem_array[wr_addr_i] <= data_i;
        end
    end
    
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            rd_addr_a_r <= '0;
        end else if (rd_en_a_i) begin
            rd_addr_a_r <= rd_addr_a_i;
        end
    end
    
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            rd_addr_b_r <= '0;
        end else if (rd_en_b_i) begin
            rd_addr_b_r <= rd_addr_b_i;
        end
    end
    
    assign data_a_o = mem_array[rd_addr_a_r];
    assign data_b_o = mem_array[rd_addr_b_r];

endmodule