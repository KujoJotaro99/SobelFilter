`timescale 1ns/1ps

module dvp_axis 
#(
    parameter WIDTH_P = 8
) (
    input logic [0:0] pclk_i, // pixel clock
    input logic [0:0] rstn_i, // async active low reset
    input logic [0:0] vsync_i, // frame sync
    input logic [0:0] hsync_i, // line valid
    input logic [WIDTH_P-1:0] data_i, // pixel byte
    output logic [WIDTH_P-1:0] tdata_o, // stream payload
    output logic [WIDTH_P/8-1:0] tkeep_o, // byte qualifier
    output logic [WIDTH_P/8-1:0] tstrb_o, // byte strobe
    output logic [0:0] tlast_o, // end of packet
    output logic [0:0] tvalid_o, // payload valid
    input logic [0:0] tready_i // sink ready
);

    logic [0:0] hsync_d_l;
    logic [WIDTH_P-1:0] data_d_l;

    always_ff @(posedge pclk_i) begin
        if (!rstn_i) begin
            hsync_d_l <= 1'b0;
            data_d_l <= '0;
            tdata_o <= '0;
            tvalid_o <= 1'b0;
            tlast_o <= 1'b0;
        end else begin
            hsync_d_l <= hsync_i;
            data_d_l <= data_i;
            tdata_o <= data_d_l;
            tvalid_o <= hsync_d_l;
            tlast_o <= hsync_d_l & ~hsync_i;
        end
    end

    assign tkeep_o = {(WIDTH_P/8){1'b1}};
    assign tstrb_o = {(WIDTH_P/8){1'b1}};

endmodule
