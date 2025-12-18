`timescale 1ns/1ps

module conv2d #(
    parameter WIDTH_P = 8,
    parameter DEPTH_P = 16
)(
    input logic clk_i,
    input logic rstn_i,
    input logic valid_i,
    input logic ready_i,
    input logic [WIDTH_P-1:0] data_i,
    output logic valid_o,
    output logic ready_o,
    output logic signed [(2*WIDTH_P)-1:0] gx_o,
    output logic signed [(2*WIDTH_P)-1:0] gy_o
);

    elastic #(
        .WIDTH_P(WIDTH_P)
    ) stream_pipe (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i('0),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .valid_o(valid_o),
        .data_o(),
        .ready_i(ready_i)
    );

    logic [WIDTH_P-1:0] conv_window [2:0][2:0];
    logic [WIDTH_P-1:0] line_buf1_o;
    logic [WIDTH_P-1:0] line_buf2_o;

    integer r;
    integer c;
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            for (r = 0; r < 3; r = r + 1)
                for (c = 0; c < 3; c = c + 1)
                    conv_window[r][c] <= '0;
        end else if (valid_i & ready_o) begin
            conv_window[0][2] <= conv_window[0][1];
            conv_window[0][1] <= conv_window[0][0];
            conv_window[0][0] <= line_buf2_o;

            conv_window[1][2] <= conv_window[1][1];
            conv_window[1][1] <= conv_window[1][0];
            conv_window[1][0] <= line_buf1_o;

            conv_window[2][2] <= conv_window[2][1];
            conv_window[2][1] <= conv_window[2][0];
            conv_window[2][0] <= data_i;
        end
    end

    ramdelaybuffer #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(DEPTH_P-1)
    ) ram1 (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i & ready_o),
        .ready_i(1'b1),
        .valid_o(),
        .ready_o(),
        .data_i(data_i),
        .data_o(line_buf1_o)
    );

    ramdelaybuffer #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(DEPTH_P-1)
    ) ram2 (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i & ready_o),
        .ready_i(1'b1),
        .valid_o(),
        .ready_o(),
        .data_i(line_buf1_o),
        .data_o(line_buf2_o)
    );

    localparam signed [3:0] KX [2:0][2:0] = '{
        '{-1, 0, 1},
        '{-2, 0, 2},
        '{-1, 0, 1}
    };

    localparam signed [3:0] KY [2:0][2:0] = '{
        '{-1, -2, -1},
        '{0, 0, 0},
        '{1, 2, 1}
    };

    SB_MAC16 #(
        .NEG_TRIGGER(1'b1), // negedge reset
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
    ) sb_mac16_inst (
        .CLK(),
        .CE(),

        .A(),   // [15:0]
        .B(),   // [15:0]
        .C(),   // [15:0]
        .D(),   // [15:0]

        .AHOLD(),
        .BHOLD(),
        .CHOLD(),
        .DHOLD(),

        .IRSTTOP(),
        .IRSTBOT(),

        .ORSTTOP(),
        .ORSTBOT(),

        .OLOADTOP(),
        .OLOADBOT(),

        .ADDSUBTOP(),
        .ADDSUBBOT(),

        .OHOLDTOP(),
        .OHOLDBOT(),

        .CI(),
        .ACCUMCI(),
        .SIGNEXTIN(),

        .CO(),
        .ACCUMCO(),
        .SIGNEXTOUT(),

        .O()    //[31:0]
    );

endmodule
