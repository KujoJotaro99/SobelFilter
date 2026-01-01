module sync2 #(
    parameter width = 8
)(
    input  logic clk_sync_i,
    input  logic rstn_i,
    input  logic [width-1:0] sync_i,
    output logic [width-1:0] sync_o
);
    logic [width-1:0] sync_m;

    always_ff @(posedge clk_sync_i) begin
        if (!rstn_i) begin
            sync_m <= '0;
            sync_o <= '0;
        end else begin
            sync_m <= sync_i;
            sync_o <= sync_m;
        end
    end
endmodule