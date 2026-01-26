`timescale 1ns/1ps

module sobel 
#(
    parameter WIDTH_P = 8,
    parameter LINE_W_P = 640,
    parameter FRAME_H_P = 480,
    parameter FIFO_DEPTH_P = 512
) (
    input logic mclk_i, // camera reference clock in
    input logic rstn_i,
    input logic cam_pclk_i, // pixel clock from camera
    input logic cam_hsync_i, // line valid from camera
    input logic cam_vsync_i, // frame sync from camera
    input logic [WIDTH_P-1:0] cam_data_i, // pixel byte from camera
    output logic cam_xclk_o, // reference clock to camera
    inout wire cam_scl_io, // i2c scl line
    inout wire cam_sda_io, // i2c sda line
    output logic [3:0] dvi_data_o, // video data nibble
    output logic dvi_pclk_o, // video pixel clock
    output logic dvi_hsync_o, // video hsync
    output logic dvi_vsync_o, // video vsync
    output logic dvi_de_o // video data enable
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
    logic sink_ready; // internal sink ready

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
    logic [7:0] i2c_sbadri; // i2c write address
    logic [7:0] i2c_sbdati; // i2c write data
    logic i2c_sbwr; // i2c write enable
    logic i2c_sbstb; // i2c strobe
    logic i2c_done; // i2c config done
    logic i2c_done_cam; // i2c done synced to cam clock

    logic rstn_mclk; // reset synced to mclk
    logic rstn_cam; // reset synced to cam clock

    logic [$clog2(LINE_W_P)-1:0] x_cnt; // output column counter
    logic [$clog2(FRAME_H_P)-1:0] y_cnt; // output row counter
    logic [$clog2(LINE_W_P+160)-1:0] h_cnt; // display column counter
    logic [$clog2(FRAME_H_P+45)-1:0] v_cnt; // display row counter

    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .PLLOUT_SELECT("GENCLK"),
        .DIVR(4'b0000),
        .DIVF(7'b0111111),
        .DIVQ(3'b101),
        .FILTER_RANGE(3'b001)
    ) cam_pll (
        .PACKAGEPIN(mclk_i),
        .PLLOUTCORE(pll_clk),
        .PLLOUTGLOBAL(),
        .EXTFEEDBACK(1'b0),
        .DYNAMICDELAY(8'b00000000),
        .LOCK(),
        .BYPASS(1'b0),
        .RESETB(rstn_mclk),
        .LATCHINPUTVALUE(1'b0),
        .SDO(),
        .SDI(1'b0),
        .SCLK(1'b0)
    );

    assign cam_xclk_o = pll_clk;
    assign dvi_pclk_o = cam_pclk_i;
    assign dvi_hsync_o = ~((h_cnt >= (LINE_W_P + 16)) && (h_cnt < (LINE_W_P + 16 + 96)));
    assign dvi_vsync_o = ~((v_cnt >= (FRAME_H_P + 10)) && (v_cnt < (FRAME_H_P + 10 + 2)));
    assign dvi_de_o = (h_cnt < LINE_W_P) && (v_cnt < FRAME_H_P);

    assign cam_scl_io = i2c_scl_oe ? i2c_scl_o : 1'bz;
    assign cam_sda_io = i2c_sda_oe ? i2c_sda_o : 1'bz;
    assign i2c_scl_i = cam_scl_io;
    assign i2c_sda_i = cam_sda_io;
    assign i2c_sbadri[7:4] = 4'b0000;
    assign sink_ready = 1'b1;

    sync2 #(
        .WIDTH_P(1)
    ) rstn_mclk_sync (
        .clk_sync_i(pll_clk),
        .rstn_i(rstn_i),
        .sync_i(rstn_i),
        .sync_o(rstn_mclk)
    );

    sync2 #(
        .WIDTH_P(1)
    ) rstn_cam_sync (
        .clk_sync_i(cam_pclk_i),
        .rstn_i(rstn_i),
        .sync_i(rstn_i),
        .sync_o(rstn_cam)
    );

    sync2 #(
        .WIDTH_P(1)
    ) i2c_done_sync (
        .clk_sync_i(cam_pclk_i),
        .rstn_i(rstn_cam),
        .sync_i(i2c_done),
        .sync_o(i2c_done_cam)
    );

    i2c_fsm cam_i2c_cfg (
        .clk_i(pll_clk),
        .rstn_i(rstn_mclk),
        .sbwr_o(i2c_sbwr),
        .sbstb_o(i2c_sbstb),
        .sbadri_o(i2c_sbadri[3:0]),
        .sbdati_o(i2c_sbdati),
        .sback_i(i2c_sback),
        .done_o(i2c_done)
    );

    SB_I2C #(
        .BUS_ADDR74("0b0001")
    ) cam_i2c (
        .SBCLKI(pll_clk),
        .SBRWI(i2c_sbwr),
        .SBSTBI(i2c_sbstb),
        .SBADRI7(i2c_sbadri[7]),
        .SBADRI6(i2c_sbadri[6]),
        .SBADRI5(i2c_sbadri[5]),
        .SBADRI4(i2c_sbadri[4]),
        .SBADRI3(i2c_sbadri[3]),
        .SBADRI2(i2c_sbadri[2]),
        .SBADRI1(i2c_sbadri[1]),
        .SBADRI0(i2c_sbadri[0]),
        .SBDATI7(i2c_sbdati[7]),
        .SBDATI6(i2c_sbdati[6]),
        .SBDATI5(i2c_sbdati[5]),
        .SBDATI4(i2c_sbdati[4]),
        .SBDATI3(i2c_sbdati[3]),
        .SBDATI2(i2c_sbdati[2]),
        .SBDATI1(i2c_sbdati[1]),
        .SBDATI0(i2c_sbdati[0]),
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
        .rstn_i(rstn_cam),
        .vsync_i(cam_vsync_i & i2c_done_cam),
        .hsync_i(cam_hsync_i & i2c_done_cam),
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
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_cam),
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
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_cam),
        .valid_i(fifo_valid),
        .ready_i(mag_ready),
        .data_i(fifo_data),
        .valid_o(conv_valid),
        .ready_o(fifo_ready),
        .gx_o(gx_s),
        .gy_o(gy_s)
    );

    // always_ff @(posedge clk_i) begin
    //     if(!rstn_i) begin
    //         gx_abs <= '0;
    //         gy_abs <= '0;
    //     end else begin
    //         gx_abs <= gx_s[2*WIDTH_P-1] ? (~gx_s + 1'b1) : gx_s;
    //         gy_abs <= gy_s[2*WIDTH_P-1] ? (~gy_s + 1'b1) : gy_s;
    //     end
    // end

    assign gx_abs = gx_s[2*WIDTH_P-1] ? (~gx_s + 1'b1) : gx_s;
    assign gy_abs = gy_s[2*WIDTH_P-1] ? (~gy_s + 1'b1) : gy_s;

    magnitude #(
        .WIDTH_P(WIDTH_P)
    ) sobel_magnitude (
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_cam),
        .valid_i(conv_valid),
        .ready_i(sink_ready),
        .gx_i(gx_abs[WIDTH_P-1:0]),
        .gy_i(gy_abs[WIDTH_P-1:0]),
        .valid_o(mag_valid),
        .ready_o(mag_ready),
        .mag_o(mag_data)
    );

    assign dvi_data_o = (dvi_de_o && mag_valid) ? mag_data[7:4] : 4'b0;

    always_ff @(posedge cam_pclk_i) begin
        if (!rstn_cam) begin
            h_cnt <= '0;
            v_cnt <= '0;
        end else if (h_cnt == (LINE_W_P + 160 - 1)) begin
            h_cnt <= '0;
            if (v_cnt == (FRAME_H_P + 45 - 1)) begin
                v_cnt <= '0;
            end else begin
                v_cnt <= v_cnt + 1'b1;
            end
        end else begin
            h_cnt <= h_cnt + 1'b1;
        end
    end

    counter #(
        .WIDTH_P($clog2(LINE_W_P)),
        .MAX_VAL_P(LINE_W_P-1)
    ) x_counter (
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_cam),
        .rstn_data_i('0),
        .up_i(1'b1),
        .down_i(1'b0),
        .en_i(mag_valid & sink_ready),
        .count_o(x_cnt)
    );

    counter #(
        .WIDTH_P($clog2(FRAME_H_P)),
        .MAX_VAL_P(FRAME_H_P-1)
    ) y_counter (
        .clk_i(cam_pclk_i),
        .rstn_i(rstn_cam),
        .rstn_data_i('0),
        .up_i(1'b1),
        .down_i(1'b0),
        .en_i(mag_valid & sink_ready & (x_cnt == LINE_W_P-1)),
        .count_o(y_cnt)
    );

endmodule
