module sync2 #(
    parameter WIDTH_P = 8
)(
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [WIDTH_P-1:0] sync_i,
    output logic [WIDTH_P-1:0] sync_o
);
    logic [WIDTH_P-1:0] sync_m_l;
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            sync_m_l <= '0;
            sync_o <= '0;
        end else begin
            sync_m_l <= sync_i;
            sync_o <= sync_m_l;
        end
    end
endmodule
