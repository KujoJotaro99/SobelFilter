`timescale 1ns/1ps

module conv2d 
#(
    parameter WIDTH_P = 8,
    parameter DEPTH_P = 16
)(
    input  logic clk_i,
    input  logic rstn_i,
    input  logic valid_i,
    input  logic ready_i,
    input  logic [WIDTH_P-1:0] data_i,
    output logic valid_o,
    output logic ready_o,
    output logic signed [(2*WIDTH_P)-1:0] gx_o,
    output logic signed [(2*WIDTH_P)-1:0] gy_o
);

    logic [WIDTH_P-1:0] ram_row0, ram_row1;

    // likely need some kind of delayed valid with the ram because contents not cleared between test, only conv window is cleared so the circular buffer may dump wrong values
    logic lb_valid;
    logic lb_ready;

    ramdelaybuffer #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(2*DEPTH_P-1),
        .DELAY_A_P(2*DEPTH_P-1),
        .DELAY_B_P(DEPTH_P-1)
    ) line_buffer (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i),
        .ready_i(lb_ready),
        .valid_o(lb_valid),
        .ready_o(ready_o),
        .data_i(data_i),
        .data_a_o(ram_row0),
        .data_b_o(ram_row1)
    );

    // convolution sliding window
    logic [WIDTH_P-1:0] conv_window [2:0][2:0];

    integer r;
    integer c;

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            for (r = 0; r < 3; r = r + 1) begin
                for (c = 0; c < 3; c = c + 1) begin
                    conv_window[r][c] <= '0;
                end
            end
        end else if (valid_i & ready_o) begin
            // shift data into each row
            for (r = 0; r < 3; r = r + 1) begin
                conv_window[r][0] <= conv_window[r][1];
                conv_window[r][1] <= conv_window[r][2];
            end
            
            // shift corresponding row data into each row
            conv_window[0][2] <= ram_row0; // 2 rows ago
            conv_window[1][2] <= ram_row1; // 1 row ago
            conv_window[2][2] <= data_i; // newest data
        end
    end

    logic signed [(2*WIDTH_P)-1:0] p00_s;
    logic signed [(2*WIDTH_P)-1:0] p01_s;
    logic signed [(2*WIDTH_P)-1:0] p02_s;
    logic signed [(2*WIDTH_P)-1:0] p10_s;
    logic signed [(2*WIDTH_P)-1:0] p12_s;
    logic signed [(2*WIDTH_P)-1:0] p20_s;
    logic signed [(2*WIDTH_P)-1:0] p21_s;
    logic signed [(2*WIDTH_P)-1:0] p22_s;
    logic signed [(2*WIDTH_P)-1:0] p00_r;
    logic signed [(2*WIDTH_P)-1:0] p01_r;
    logic signed [(2*WIDTH_P)-1:0] p02_r;
    logic signed [(2*WIDTH_P)-1:0] p10_r;
    logic signed [(2*WIDTH_P)-1:0] p12_r;
    logic signed [(2*WIDTH_P)-1:0] p20_r;
    logic signed [(2*WIDTH_P)-1:0] p21_r;
    logic signed [(2*WIDTH_P)-1:0] p22_r;
    logic signed [(2*WIDTH_P)-1:0] gx_pos;
    logic signed [(2*WIDTH_P)-1:0] gx_neg;
    logic signed [(2*WIDTH_P)-1:0] gy_pos;
    logic signed [(2*WIDTH_P)-1:0] gy_neg;
    logic signed [(2*WIDTH_P)-1:0] gx_comb;
    logic signed [(2*WIDTH_P)-1:0] gy_comb;
    logic p_valid;
    logic p_ready;

    assign p00_s = $signed({1'b0, conv_window[0][0]});
    assign p01_s = $signed({1'b0, conv_window[0][1]});
    assign p02_s = $signed({1'b0, conv_window[0][2]});
    assign p10_s = $signed({1'b0, conv_window[1][0]});
    assign p12_s = $signed({1'b0, conv_window[1][2]});
    assign p20_s = $signed({1'b0, conv_window[2][0]});
    assign p21_s = $signed({1'b0, conv_window[2][1]});
    assign p22_s = $signed({1'b0, conv_window[2][2]});
    assign p_valid = lb_valid;
    assign lb_ready = p_ready;

    assign gx_pos = p02_s + (p12_s <<< 1) + p22_s;
    assign gx_neg = p00_s + (p10_s <<< 1) + p20_s;
    assign gy_pos = p20_s + (p21_s <<< 1) + p22_s;
    assign gy_neg = p00_s + (p01_s <<< 1) + p02_s;

    assign gx_comb = gx_pos - gx_neg;
    assign gy_comb = gy_pos - gy_neg;

    logic [4*WIDTH_P-1:0] gxy_bus;

    assign gxy_bus = {gx_comb, gy_comb};
    assign {gx_o, gy_o} = gxy_bus;
    assign valid_o = p_valid;
    assign p_ready = ready_i;

endmodule
