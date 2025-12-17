`timescale 1ns/1ps

module sync_ram_block #(
    parameter WIDTH_P = 32, 
    parameter DEPTH_P = 128, 
    parameter filename_p = ""
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [WIDTH_P-1:0] data_i,
    input logic [$clog2(DEPTH_P)-1:0] wr_addr_i,
    input logic [$clog2(DEPTH_P)-1:0] rd_addr_i,
    input logic [0:0] wr_en_i,
    input logic [0:0] rd_en_i,
    output logic [WIDTH_P-1:0] data_o
);

    logic [WIDTH_P-1:0] mem_array [DEPTH_P-1:0];

    initial begin
        if (filename_p != "") begin
            $readmemb(filename_p, mem_array);
        end
        for (int i = 0; i < DEPTH_P; i++) begin
            $dumpvars(0,mem_array[i]);
        end
        $display("%m: depth_p is %d, width_p is %d", DEPTH_P, WIDTH_P);
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            data_o <= '0;
            for (int i = 0; i < DEPTH_P; i++) begin
                //
            end
        end else begin
            // read priority
            if (rd_en_i) begin
                data_o <= mem_array[rd_addr_i];
            end
            if (wr_en_i) begin
                mem_array[wr_addr_i] <= data_i;
            end
        end
    end

endmodule
