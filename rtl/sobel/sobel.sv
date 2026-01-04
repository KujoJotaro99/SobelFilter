`timescale 1ns/1ps

module sobel #(
    parameter int WIDTH_P = 8,
    parameter int LINE_W_P = 640,
    parameter int FRAME_H_P = 480,
    parameter int FIFO_DEPTH_P = 512
) (
    input logic [0:0] mclk_i, // camera reference clock in
    input logic [0:0] rstn_i, // async active low reset
    input logic [0:0] cam_pclk_i, // pixel clock from camera
    input logic [0:0] cam_hsync_i, // line valid from camera
    input logic [0:0] cam_vsync_i, // frame sync from camera
    input logic [WIDTH_P-1:0] cam_data_i, // pixel byte from camera
    output logic [0:0] cam_xclk_o, // reference clock to camera
    inout wire [0:0] cam_scl_io, // i2c scl line
    inout wire [0:0] cam_sda_io, // i2c sda line
    output logic [2*WIDTH_P-1:0] tdata_o, // axis payload
    output logic [(2*WIDTH_P)/8-1:0] tkeep_o, // axis byte qualifier
    output logic [(2*WIDTH_P)/8-1:0] tstrb_o, // axis byte strobe
    output logic [0:0] tlast_o, // axis end of line
    output logic [0:0] tuser_o, // axis start of frame
    output logic [0:0] tvalid_o, // axis payload valid
    input logic [0:0] tready_i // axis sink ready
);

    logic [0:0] pll_clk_w; // pll output clock
    logic [0:0] rstn_mclk_w; // reset synced to mclk_i (async assert, sync deassert)
    logic [0:0] rstn_pclk_w; // reset synced to cam_pclk_i (async assert, sync deassert)
    logic [0:0] cam_vsync_d_l;
    logic [0:0] vsync_rise_w;
    logic [0:0] rstn_vid_w;
    logic [0:0] sof_pending_l;

    logic [0:0] dvp_valid_w; // dvp valid
    logic [0:0] dvp_ready_w; // dvp ready
    logic [0:0] dvp_last_w; // dvp end of line
    logic [WIDTH_P-1:0] dvp_data; // dvp byte

    logic [0:0] fifo_valid_w; // fifo valid
    logic [0:0] fifo_ready_w; // fifo ready
    logic [WIDTH_P-1:0] fifo_data; // fifo data

    logic [0:0] conv_valid_w; // conv2d valid
    logic signed [2*WIDTH_P-1:0] gx_s; // conv2d gx
    logic signed [2*WIDTH_P-1:0] gy_s; // conv2d gy
    logic [2*WIDTH_P-1:0] gx_abs; // abs gx
    logic [2*WIDTH_P-1:0] gy_abs; // abs gy

    logic [0:0] mag_valid_w; // magnitude valid
    logic [0:0] mag_ready_w; // magnitude ready
    logic [2*WIDTH_P-1:0] mag_data; // magnitude data

    logic [0:0] i2c_scl_i_w; // i2c scl input
    logic [0:0] i2c_sda_i_w; // i2c sda input
    logic [0:0] i2c_scl_o_w; // i2c scl output
    logic [0:0] i2c_scl_oe_w; // i2c scl output enable
    logic [0:0] i2c_sda_o_w; // i2c sda output
    logic [0:0] i2c_sda_oe_w; // i2c sda output enable

    logic [0:0] i2c_sback_w; // i2c transaction complete
    logic [0:0] i2c_irq_w; // i2c interrupt
    logic [0:0] i2c_wkup_w; // i2c wakeup
    logic [7:0] i2c_sbdato; // i2c read data

    logic [$clog2(LINE_W_P)-1:0] x_cnt; // output column counter
    logic [$clog2(FRAME_H_P)-1:0] y_cnt; // output row counter

    sync2 #(
        .WIDTH_P(1)
    ) rst_sync_mclk (
        .clk_i(mclk_i),
        .rstn_i(rstn_i),
        .sync_i(1'b1),
        .sync_o(rstn_mclk_w)
    );

    sync2 #(
        .WIDTH_P(1)
    ) rst_sync_pclk (
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_i),
        .sync_i(1'b1),
        .sync_o(rstn_pclk_w)
    );

    always_ff @(posedge cam_pclk_i) begin
        if (!rstn_pclk_w) begin
            cam_vsync_d_l <= 1'b0;
            sof_pending_l <= 1'b0;
        end else begin
            cam_vsync_d_l <= cam_vsync_i;
            if (vsync_rise_w) begin
                sof_pending_l <= 1'b1;
            end else if (mag_valid_w & tready_i) begin
                sof_pending_l <= 1'b0;
            end
        end
    end

    assign vsync_rise_w = cam_vsync_i & ~cam_vsync_d_l;
    assign rstn_vid_w = rstn_pclk_w & ~vsync_rise_w;

    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .PLLOUT_SELECT("GENCLK"),
        .DIVR(4'b0000),
        .DIVF(7'b0111111),
        .DIVQ(3'b101),
        .FILTER_RANGE(3'b001)
    ) cam_pll (
        .PACKAGEPIN(mclk_i),
        .PLLOUTCORE(pll_clk_w),
        .PLLOUTGLOBAL(),
        .EXTFEEDBACK(1'b0),
        .DYNAMICDELAY(8'b00000000),
        .LOCK(),
        .BYPASS(1'b0),
        .RESETB(rstn_i),
        .LATCHINPUTVALUE(1'b0),
        .SDO(),
        .SDI(1'b0),
        .SCLK(1'b0)
    );

    assign cam_xclk_o = pll_clk_w;

    assign cam_scl_io = i2c_scl_oe_w ? i2c_scl_o_w : 1'bz;
    assign cam_sda_io = i2c_sda_oe_w ? i2c_sda_o_w : 1'bz;
    assign i2c_scl_i_w = cam_scl_io;
    assign i2c_sda_i_w = cam_sda_io;

    SB_I2C #(
        .BUS_ADDR74("0b0001")
    ) cam_i2c (
        .SBCLKI(mclk_i),
        .SBRWI(1'b0),
        .SBSTBI(1'b0),
        .SBADRI7(1'b0),
        .SBADRI6(1'b0),
        .SBADRI5(1'b0),
        .SBADRI4(1'b0),
        .SBADRI3(1'b0),
        .SBADRI2(1'b0),
        .SBADRI1(1'b0),
        .SBADRI0(1'b0),
        .SBDATI7(1'b0),
        .SBDATI6(1'b0),
        .SBDATI5(1'b0),
        .SBDATI4(1'b0),
        .SBDATI3(1'b0),
        .SBDATI2(1'b0),
        .SBDATI1(1'b0),
        .SBDATI0(1'b0),
        .SCLI(i2c_scl_i_w),
        .SDAI(i2c_sda_i_w),
        .SBDATO7(i2c_sbdato[7]),
        .SBDATO6(i2c_sbdato[6]),
        .SBDATO5(i2c_sbdato[5]),
        .SBDATO4(i2c_sbdato[4]),
        .SBDATO3(i2c_sbdato[3]),
        .SBDATO2(i2c_sbdato[2]),
        .SBDATO1(i2c_sbdato[1]),
        .SBDATO0(i2c_sbdato[0]),
        .SBACKO(i2c_sback_w),
        .I2CIRQ(i2c_irq_w),
        .I2CWKUP(i2c_wkup_w),
        .SCLO(i2c_scl_o_w),
        .SCLOE(i2c_scl_oe_w),
        .SDAO(i2c_sda_o_w),
        .SDAOE(i2c_sda_oe_w)
    );

    dvp_axis #(
        .WIDTH_P(WIDTH_P)
    ) hm0360_dvp_axis (
        .pclk_i(cam_pclk_i),
        .rstn_i(rstn_vid_w),
        .vsync_i(cam_vsync_i),
        .hsync_i(cam_hsync_i),
        .data_i(cam_data_i),
        .tdata_o(dvp_data),
        .tkeep_o(),
        .tstrb_o(),
        .tlast_o(dvp_last_w),
        .tvalid_o(dvp_valid_w),
        .tready_i(dvp_ready_w)
    );

    fifo_sync #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(FIFO_DEPTH_P)
    ) cam_fifo (
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_vid_w),
        .data_i(dvp_data),
        .valid_i(dvp_valid_w),
        .ready_o(dvp_ready_w),
        .valid_o(fifo_valid_w),
        .ready_i(fifo_ready_w),
        .data_o(fifo_data)
    );

    conv2d #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(LINE_W_P)
    ) sobel_conv2d (
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_vid_w),
        .valid_i(fifo_valid_w),
        .ready_i(mag_ready_w),
        .data_i(fifo_data),
        .valid_o(conv_valid_w),
        .ready_o(fifo_ready_w),
        .gx_o(gx_s),
        .gy_o(gy_s)
    );

    assign gx_abs = gx_s[2*WIDTH_P-1] ? (~gx_s + 1'b1) : gx_s;
    assign gy_abs = gy_s[2*WIDTH_P-1] ? (~gy_s + 1'b1) : gy_s;

    magnitude #(
        .WIDTH_P(WIDTH_P)
    ) sobel_magnitude (
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_vid_w),
        .valid_i(conv_valid_w),
        .ready_i(tready_i),
        .gx_i(gx_abs),
        .gy_i(gy_abs),
        .valid_o(mag_valid_w),
        .ready_o(mag_ready_w),
        .mag_o(mag_data)
    );

    counter #(
        .WIDTH_P($clog2(LINE_W_P)),
        .MAX_VAL_P(LINE_W_P-1)
    ) x_counter (
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_vid_w),
        .rstn_data_i('0),
        .up_i(mag_valid_w & tready_i),
        .down_i(1'b0),
        .en_i(1'b1),
        .count_o(x_cnt)
    );

    counter #(
        .WIDTH_P($clog2(FRAME_H_P)),
        .MAX_VAL_P(FRAME_H_P-1)
    ) y_counter (
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_vid_w),
        .rstn_data_i('0),
        .up_i((mag_valid_w & tready_i) & (x_cnt == LINE_W_P-1)),
        .down_i(1'b0),
        .en_i(1'b1),
        .count_o(y_cnt)
    );

    assign tdata_o = mag_data;
    assign tvalid_o = mag_valid_w;
    assign tlast_o = mag_valid_w & (x_cnt == LINE_W_P-1);
    assign tuser_o = mag_valid_w & sof_pending_l;
    assign tkeep_o = {((2*WIDTH_P)/8){1'b1}};
    assign tstrb_o = {((2*WIDTH_P)/8){1'b1}};

endmodule
