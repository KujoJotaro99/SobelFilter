`timescale 1ns/1ps

module sobel
#(
    parameter WIDTH_P = 8,
    parameter LINE_W_P = 640,
    parameter FIFO_DEPTH_P = 512,
    parameter UART_PRESCALE_P = 16'd43
) (
    input  logic mclk_i,
    input  logic rstn_i,
    input  logic uart_rxd_i,
    output logic uart_txd_o
);

    logic core_clk;

    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .PLLOUT_SELECT("GENCLK"),
        .DIVR(4'b0000),
        .DIVF(7'b0110100),
        .DIVQ(3'b100),
        .FILTER_RANGE(3'b001)
    ) core_pll (
        .PACKAGEPIN(mclk_i),
        .PLLOUTCORE(core_clk),
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

    logic rstn_sync;

    sync2 #(
        .WIDTH_P(1)
    ) rstn_sync_inst (
        .clk_sync_i(core_clk),
        .rstn_i(1'b1),
        .sync_i(rstn_i),
        .sync_o(rstn_sync)
    );

    logic [7:0] uart_rx_data;
    logic uart_rx_valid;
    logic uart_rx_ready;

    logic [7:0] uart_tx_data;
    logic uart_tx_valid;
    logic uart_tx_ready;

    uart #(
        .DATA_WIDTH(8)
    ) uart_inst (
        .clk(core_clk),
        .rst(~rstn_sync),
        .s_axis_tdata(uart_tx_data),
        .s_axis_tvalid(uart_tx_valid),
        .s_axis_tready(uart_tx_ready),
        .m_axis_tdata(uart_rx_data),
        .m_axis_tvalid(uart_rx_valid),
        .m_axis_tready(uart_rx_ready),
        .rxd(uart_rxd_i),
        .txd(uart_txd_o),
        .tx_busy(),
        .rx_busy(),
        .rx_overrun_error(),
        .rx_frame_error(),
        .prescale(UART_PRESCALE_P)
    );

    logic [7:0] rx_fifo_data;
    logic rx_fifo_valid;
    logic rx_fifo_ready;

    fifo_sync #(
        .WIDTH_P(8),
        .DEPTH_P(FIFO_DEPTH_P)
    ) rx_fifo (
        .clk_i(core_clk),
        .rstn_i(rstn_sync),
        .data_i(uart_rx_data),
        .valid_i(uart_rx_valid),
        .ready_i(rx_fifo_ready),
        .valid_o(rx_fifo_valid),
        .ready_o(uart_rx_ready),
        .data_o(rx_fifo_data)
    );

    logic [23:0] rgb_data;
    logic rgb_valid;
    logic rgb_ready;

    axis_adapter #(
        .S_DATA_WIDTH(8),
        .M_DATA_WIDTH(24),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) rgb_pack (
        .clk(core_clk),
        .rst(~rstn_sync),
        .s_axis_tdata(rx_fifo_data),
        .s_axis_tkeep(1'b1),
        .s_axis_tvalid(rx_fifo_valid),
        .s_axis_tready(rx_fifo_ready),
        .s_axis_tlast(1'b0),
        .s_axis_tid('0),
        .s_axis_tdest('0),
        .s_axis_tuser('0),
        .m_axis_tdata(rgb_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(rgb_valid),
        .m_axis_tready(rgb_ready),
        .m_axis_tlast(),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    logic [23:0] rgb_pipe_data;
    logic rgb_pipe_valid;
    logic rgb_pipe_ready;

    elastic #(
        .WIDTH_P(24)
    ) rgb_pipe (
        .clk_i(core_clk),
        .rstn_i(rstn_sync),
        .data_i(rgb_data),
        .valid_i(rgb_valid),
        .ready_o(rgb_ready),
        .valid_o(rgb_pipe_valid),
        .data_o(rgb_pipe_data),
        .ready_i(rgb_pipe_ready)
    );

    logic gray_valid;
    logic [7:0] gray_data;
    logic gray_ready;

    rgb2gray #(
        .WIDTH_P(WIDTH_P)
    ) rgb2gray_inst (
        .clk_i(core_clk),
        .rstn_i(rstn_sync),
        .valid_i(rgb_pipe_valid),
        .ready_i(gray_ready),
        .valid_o(gray_valid),
        .ready_o(rgb_pipe_ready),
        .red_i(rgb_pipe_data[7:0]),
        .blue_i(rgb_pipe_data[23:16]),
        .green_i(rgb_pipe_data[15:8]),
        .gray_o(gray_data)
    );

    logic conv_valid;
    logic conv_ready;
    logic signed [(2*WIDTH_P)-1:0] conv_gx;
    logic signed [(2*WIDTH_P)-1:0] conv_gy;

    conv2d #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(LINE_W_P)
    ) sobel_conv2d (
        .clk_i(core_clk),
        .rstn_i(rstn_sync),
        .valid_i(gray_valid),
        .ready_i(conv_ready),
        .data_i(gray_data),
        .valid_o(conv_valid),
        .ready_o(gray_ready),
        .gx_o(conv_gx),
        .gy_o(conv_gy)
    );

    logic [WIDTH_P-1:0] gx_abs;
    logic [WIDTH_P-1:0] gy_abs;
    logic [2*WIDTH_P-1:0] abs_data;
    logic abs_valid;
    logic abs_ready;

    assign gx_abs = conv_gx[2*WIDTH_P-1] ? -conv_gx : conv_gx;
    assign gy_abs = conv_gy[2*WIDTH_P-1] ? -conv_gy : conv_gy;
    assign abs_data = {gx_abs, gy_abs};

    elastic #(
        .WIDTH_P(2*WIDTH_P)
    ) abs_pipe (
        .clk_i(core_clk),
        .rstn_i(rstn_sync),
        .data_i(abs_data),
        .valid_i(conv_valid),
        .ready_o(conv_ready),
        .valid_o(abs_valid),
        .data_o(abs_data),
        .ready_i(abs_ready)
    );

    logic mag_valid;
    logic mag_ready;
    logic [2*WIDTH_P-1:0] mag_data;

    magnitude #(
        .WIDTH_P(WIDTH_P)
    ) magnitude_inst (
        .clk_i(core_clk),
        .rstn_i(rstn_sync),
        .valid_i(abs_valid),
        .ready_i(mag_ready),
        .gx_i(abs_data[2*WIDTH_P-1:WIDTH_P]),
        .gy_i(abs_data[WIDTH_P-1:0]),
        .valid_o(mag_valid),
        .ready_o(abs_ready),
        .mag_o(mag_data)
    );

    logic [23:0] mag_rgb;
    logic [23:0] mag_pipe_data;
    logic mag_pipe_valid;
    logic mag_pipe_ready;

    assign mag_rgb = {3{mag_data[WIDTH_P-1:0]}};

    elastic #(
        .WIDTH_P(24)
    ) mag_pipe (
        .clk_i(core_clk),
        .rstn_i(rstn_sync),
        .data_i(mag_rgb),
        .valid_i(mag_valid),
        .ready_o(mag_ready),
        .valid_o(mag_pipe_valid),
        .data_o(mag_pipe_data),
        .ready_i(mag_pipe_ready)
    );

    axis_adapter #(
        .S_DATA_WIDTH(24),
        .M_DATA_WIDTH(8),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) rgb_unpack (
        .clk(core_clk),
        .rst(~rstn_sync),
        .s_axis_tdata(mag_pipe_data),
        .s_axis_tkeep(3'b111),
        .s_axis_tvalid(mag_pipe_valid),
        .s_axis_tready(mag_pipe_ready),
        .s_axis_tlast(1'b0),
        .s_axis_tid('0),
        .s_axis_tdest('0),
        .s_axis_tuser('0),
        .m_axis_tdata(uart_tx_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(uart_tx_valid),
        .m_axis_tready(uart_tx_ready),
        .m_axis_tlast(),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

endmodule
