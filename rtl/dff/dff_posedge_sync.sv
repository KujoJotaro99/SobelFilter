`timescale 1ns/1ps

module dff_posedge_sync(
    input logic [0:0] clk_i,
    input logic [0:0] d_i,
    input logic [0:0] rstn_i,
    output logic [0:0] q_o
);

    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            q_o <= '0;
        end else begin
            q_o <= d_i;
        end
    end

endmodule


