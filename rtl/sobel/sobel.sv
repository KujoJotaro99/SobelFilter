`timescale 1ns/1ps

module sobel #(
    parameter int WIDTH_P = 8,
    parameter int LINE_W_P = 16,
    parameter int FRAME_H_P = 16,
    parameter int FIFO_DEPTH_P = 512
) (
    input logic mclk_i, // camera reference clock in
    input logic sys_clk_i, // system clock in
    input logic rstn_i, // async active low reset
    input logic cam_pclk_i, // pixel clock from camera
    input logic cam_hsync_i, // line valid from camera
    input logic cam_vsync_i, // frame sync from camera
    input logic [WIDTH_P-1:0] cam_data_i, // pixel byte from camera
    output logic cam_xclk_o, // reference clock to camera
    inout wire cam_scl_io, // i2c scl line
    inout wire cam_sda_io, // i2c sda line
    output logic [2*WIDTH_P-1:0] tdata_o, // axis payload
    output logic [(2*WIDTH_P)/8-1:0] tkeep_o, // axis byte qualifier
    output logic [(2*WIDTH_P)/8-1:0] tstrb_o, // axis byte strobe
    output logic tlast_o, // axis end of line
    output logic tuser_o, // axis start of frame
    output logic tvalid_o, // axis payload valid
    input logic tready_i // axis sink ready
);

    logic pll_clk; // pll output clock

    logic dvp_valid; // dvp valid
    logic dvp_ready; // dvp ready
    logic dvp_last; // dvp end of line
    logic [WIDTH_P-1:0] dvp_data; // dvp byte

    logic fifo_valid; // fifo valid
    logic fifo_ready; // fifo ready
    logic [WIDTH_P-1:0] fifo_data; // fifo data

    logic conv_valid; // conv2d valid
    logic signed [2*WIDTH_P-1:0] gx_s; // conv2d gx
    logic signed [2*WIDTH_P-1:0] gy_s; // conv2d gy
    logic [2*WIDTH_P-1:0] gx_abs; // abs gx
    logic [2*WIDTH_P-1:0] gy_abs; // abs gy

    logic mag_valid; // magnitude valid
    logic mag_ready; // magnitude ready
    logic [2*WIDTH_P-1:0] mag_data; // magnitude data

    logic i2c_scl_i; // i2c scl input
    logic i2c_sda_i; // i2c sda input
    logic i2c_scl_o; // i2c scl output
    logic i2c_scl_oe; // i2c scl output enable
    logic i2c_sda_o; // i2c sda output
    logic i2c_sda_oe; // i2c sda output enable

    logic i2c_sback; // i2c transaction complete
    logic i2c_irq; // i2c interrupt
    logic i2c_wkup; // i2c wakeup
    logic [7:0] i2c_sbdato; // i2c read data

    logic [$clog2(LINE_W_P)-1:0] x_cnt; // output column counter
    logic [$clog2(FRAME_H_P)-1:0] y_cnt; // output row counter

    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .PLLOUT_SELECT("GENCLK"),
        .DIVR(4'b0000),
        .DIVF(7'b0000000),
        .DIVQ(3'b000),
        .FILTER_RANGE(3'b000)
    ) cam_pll (
        .PACKAGEPIN(mclk_i),
        .PLLOUTCORE(pll_clk),
        .PLLOUTGLOBAL(),
        .EXTFEEDBACK(1'b0),
        .DYNAMICDELAY(8'b00000000),
        .LOCK(),
        .BYPASS(1'b1),
        .RESETB(rstn_i),
        .LATCHINPUTVALUE(1'b0),
        .SDO(),
        .SDI(1'b0),
        .SCLK(1'b0)
    );

    assign cam_xclk_o = pll_clk;

    assign cam_scl_io = i2c_scl_oe ? i2c_scl_o : 1'bz;
    assign cam_sda_io = i2c_sda_oe ? i2c_sda_o : 1'bz;
    assign i2c_scl_i = cam_scl_io;
    assign i2c_sda_i = cam_sda_io;

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
        .SCLI(i2c_scl_i),
        .SDAI(i2c_sda_i),
        .SBDATO7(i2c_sbdato[7]),
        .SBDATO6(i2c_sbdato[6]),
        .SBDATO5(i2c_sbdato[5]),
        .SBDATO4(i2c_sbdato[4]),
        .SBDATO3(i2c_sbdato[3]),
        .SBDATO2(i2c_sbdato[2]),
        .SBDATO1(i2c_sbdato[1]),
        .SBDATO0(i2c_sbdato[0]),
        .SBACKO(i2c_sback),
        .I2CIRQ(i2c_irq),
        .I2CWKUP(i2c_wkup),
        .SCLO(i2c_scl_o),
        .SCLOE(i2c_scl_oe),
        .SDAO(i2c_sda_o),
        .SDAOE(i2c_sda_oe)
    );

    dvp_axis #(
        .WIDTH_P(WIDTH_P)
    ) hm0360_dvp_axis (
        .pclk_i(cam_pclk_i),
        .rstn_i(rstn_i),
        .vsync_i(cam_vsync_i),
        .hsync_i(cam_hsync_i),
        .data_i(cam_data_i),
        .tdata_o(dvp_data),
        .tkeep_o(),
        .tstrb_o(),
        .tlast_o(dvp_last),
        .tvalid_o(dvp_valid),
        .tready_i(dvp_ready)
    );

    fifo_sync #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(FIFO_DEPTH_P)
    ) cam_fifo (
        .pclk_i(cam_pclk_i),
        .cclk_i(sys_clk_i),
        .rstn_i(rstn_i),
        .data_i(dvp_data),
        .valid_i(dvp_valid),
        .ready_o(dvp_ready),
        .valid_o(fifo_valid),
        .ready_i(fifo_ready),
        .data_o(fifo_data)
    );

    conv2d #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(LINE_W_P)
    ) sobel_conv2d (
        .clk_i(sys_clk_i),
        .rstn_i(rstn_i),
        .valid_i(fifo_valid),
        .ready_i(mag_ready),
        .data_i(fifo_data),
        .valid_o(conv_valid),
        .ready_o(fifo_ready),
        .gx_o(gx_s),
        .gy_o(gy_s)
    );

    assign gx_abs = gx_s[2*WIDTH_P-1] ? (~gx_s + 1'b1) : gx_s;
    assign gy_abs = gy_s[2*WIDTH_P-1] ? (~gy_s + 1'b1) : gy_s;

    magnitude #(
        .WIDTH_P(WIDTH_P)
    ) sobel_magnitude (
        .clk_i(sys_clk_i),
        .rstn_i(rstn_i),
        .valid_i(conv_valid),
        .ready_i(tready_i),
        .gx_i(gx_abs[WIDTH_P-1:0]),
        .gy_i(gy_abs[WIDTH_P-1:0]),
        .valid_o(mag_valid),
        .ready_o(mag_ready),
        .mag_o(mag_data)
    );

    always_ff @(posedge sys_clk_i) begin
        if (!rstn_i) begin
            x_cnt <= '0;
            y_cnt <= '0;
        end else if (mag_valid & tready_i) begin
            if (x_cnt == LINE_W_P-1) begin
                x_cnt <= '0;
                if (y_cnt == FRAME_H_P-1) begin
                    y_cnt <= '0;
                end else begin
                    y_cnt <= y_cnt + 1'b1;
                end
            end else begin
                x_cnt <= x_cnt + 1'b1;
            end
        end
    end

    assign tdata_o = mag_data;
    assign tvalid_o = mag_valid;
    assign tlast_o = mag_valid & (x_cnt == LINE_W_P-1);
    assign tuser_o = mag_valid & (x_cnt == 0) & (y_cnt == 0);
    assign tkeep_o = {((2*WIDTH_P)/8){1'b1}};
    assign tstrb_o = {((2*WIDTH_P)/8){1'b1}};

endmodule
