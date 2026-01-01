`timescale 1ns/1ps

module dvp_axis #(
    parameter int WIDTH_P = 8
) (
    input logic pclk_i, // pixel clock
    input logic rstn_i, // async active low reset
    input logic vsync_i, // frame sync
    input logic hsync_i, // line valid
    input logic [WIDTH_P-1:0] data_i, // pixel byte
    output logic [WIDTH_P-1:0] tdata_o, // stream payload
    output logic [WIDTH_P/8-1:0] tkeep_o, // byte qualifier
    output logic [WIDTH_P/8-1:0] tstrb_o, // byte strobe
    output logic tlast_o, // end of packet
    output logic tvalid_o, // payload valid
    input logic tready_i // sink ready
);

    logic hsync_d;
    logic [WIDTH_P-1:0] data_d;

    always_ff @(posedge pclk_i) begin
        if (!rstn_i) begin
            hsync_d <= 1'b0;
            data_d <= '0;
            tdata_o <= '0;
            tvalid_o <= 1'b0;
            tlast_o <= 1'b0;
        end else begin
            hsync_d <= hsync_i;
            data_d <= data_i;
            tdata_o <= data_d;
            tvalid_o <= hsync_d;
            tlast_o <= hsync_d & ~hsync_i;
        end
    end

    assign tkeep_o = {(WIDTH_P/8){1'b1}};
    assign tstrb_o = {(WIDTH_P/8){1'b1}};

endmodule
