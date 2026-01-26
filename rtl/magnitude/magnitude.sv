`timescale 1ns/1ps

module magnitude 
#(
    parameter WIDTH_P = 8,
    parameter LUT_HALF_BITS_P = 5,
    parameter LUT_FILE_P = "../../rtl/magnitude/magnitude_lut.mem"
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [0:0] valid_i,
    input logic [0:0] ready_i,
    input logic [WIDTH_P-1:0] gx_i,
    input logic [WIDTH_P-1:0] gy_i,
    output logic [0:0] valid_o,
    output logic [0:0] ready_o,
    output logic [2*WIDTH_P-1:0] mag_o
);
    logic [2*WIDTH_P-1:0] lut_mem [0:(1 << (2 * LUT_HALF_BITS_P)) - 1];
    logic [2*WIDTH_P-1:0] gx_sq;
    logic [2*WIDTH_P-1:0] gy_sq;
    logic [31:0] gx_mac_o;
    logic [31:0] gy_mac_o;
    logic [15:0] gx_mac_a;
    logic [15:0] gx_mac_b;
    logic [15:0] gy_mac_a;
    logic [15:0] gy_mac_b;
    logic [2*WIDTH_P-1:0] gx_sq_r;
    logic [2*WIDTH_P-1:0] gy_sq_r;
    logic [LUT_HALF_BITS_P-1:0] gx_idx;
    logic [LUT_HALF_BITS_P-1:0] gy_idx;
    logic [(2 * LUT_HALF_BITS_P)-1:0] lut_addr;
    logic [2*WIDTH_P-1:0] mag_w;
    logic [0:0] valid_r;
    logic [0:0] stage_ready;

    initial begin
        if (LUT_FILE_P != "") begin
            $readmemh(LUT_FILE_P, lut_mem);
        end
    end

`ifndef SYNTHESIS
    assign gx_sq = gx_i * gx_i;
    assign gy_sq = gy_i * gy_i;
`else
    assign gx_mac_a = {{(16-WIDTH_P){1'b0}}, gx_i};
    assign gx_mac_b = {{(16-WIDTH_P){1'b0}}, gx_i};
    assign gy_mac_a = {{(16-WIDTH_P){1'b0}}, gy_i};
    assign gy_mac_b = {{(16-WIDTH_P){1'b0}}, gy_i};

    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .C_REG(1'b0),
        .A_REG(1'b0),
        .B_REG(1'b0),
        .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0),
        .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0),
        .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b00),
        .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0),
        .TOPADDSUB_CARRYSELECT(2'b00),
        .BOTOUTPUT_SELECT(2'b00),
        .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0),
        .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0),
        .A_SIGNED(1'b0),
        .B_SIGNED(1'b0)
    ) gx_mac (
        .CLK(clk_i),
        .CE(1'b1),
        .C(16'b0),
        .A(gx_mac_a),
        .B(gx_mac_b),
        .D(16'b0),
        .AHOLD(1'b0),
        .BHOLD(1'b0),
        .CHOLD(1'b0),
        .DHOLD(1'b0),
        .IRSTTOP(1'b0),
        .IRSTBOT(1'b0),
        .ORSTTOP(1'b0),
        .ORSTBOT(1'b0),
        .OLOADTOP(1'b0),
        .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0),
        .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0),
        .OHOLDBOT(1'b0),
        .CI(1'b0),
        .ACCUMCI(1'b0),
        .SIGNEXTIN(1'b0),
        .O(gx_mac_o),
        .CO(),
        .ACCUMCO(),
        .SIGNEXTOUT()
    );

    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .C_REG(1'b0),
        .A_REG(1'b0),
        .B_REG(1'b0),
        .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0),
        .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0),
        .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b00),
        .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0),
        .TOPADDSUB_CARRYSELECT(2'b00),
        .BOTOUTPUT_SELECT(2'b00),
        .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0),
        .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0),
        .A_SIGNED(1'b0),
        .B_SIGNED(1'b0)
    ) gy_mac (
        .CLK(clk_i),
        .CE(1'b1),
        .C(16'b0),
        .A(gy_mac_a),
        .B(gy_mac_b),
        .D(16'b0),
        .AHOLD(1'b0),
        .BHOLD(1'b0),
        .CHOLD(1'b0),
        .DHOLD(1'b0),
        .IRSTTOP(1'b0),
        .IRSTBOT(1'b0),
        .ORSTTOP(1'b0),
        .ORSTBOT(1'b0),
        .OLOADTOP(1'b0),
        .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0),
        .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0),
        .OHOLDBOT(1'b0),
        .CI(1'b0),
        .ACCUMCI(1'b0),
        .SIGNEXTIN(1'b0),
        .O(gy_mac_o),
        .CO(),
        .ACCUMCO(),
        .SIGNEXTOUT()
    );

    assign gx_sq = gx_mac_o[2*WIDTH_P-1:0];
    assign gy_sq = gy_mac_o[2*WIDTH_P-1:0];
`endif
    assign gx_idx = gx_sq_r[2*WIDTH_P-1 -: LUT_HALF_BITS_P];
    assign gy_idx = gy_sq_r[2*WIDTH_P-1 -: LUT_HALF_BITS_P];
    assign lut_addr = {gx_idx, gy_idx};

    // note: check dsp synth inderence 
    // sqrt(x^2 + y^2) for x > y > 0
    // x * sqrt(1 + (y/x)^2)
    // x * sqrt(1 + r^2) contrained to x*[1, sqrt(2)]
    // x * (1 + kr)
    // x + ky
    // 1+k(1) = sqrt(2) at r = 1, the bound is sqrt(2) so k must be sqrt(2) - 1
    // approximate to 0.5 for shift purposes
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            gx_sq_r <= '0;
            gy_sq_r <= '0;
            valid_r <= 1'b0;
        end else if (stage_ready) begin
            valid_r <= valid_i;
            if (valid_i) begin
                gx_sq_r <= gx_sq;
                gy_sq_r <= gy_sq;
            end
        end
    end

    assign mag_w = valid_r ? lut_mem[lut_addr] : '0;

    elastic #(
        .WIDTH_P(2*WIDTH_P)
    ) magnitude_elastic (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(mag_w),
        .valid_i(valid_r),
        .ready_o(stage_ready),
        .valid_o(valid_o),
        .data_o(mag_o),
        .ready_i(ready_i)
    );

    assign ready_o = stage_ready;

endmodule
