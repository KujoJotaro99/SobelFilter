`timescale 1ns/1ps

module i2c_fsm 
(
    input logic clk_i,
    input logic rstn_i,
    output logic sbwr_o,
    output logic sbstb_o,
    output logic [3:0] sbadri_o,
    output logic [7:0] sbdati_o,
    input logic sback_i,
    output logic done_o
);

    // i2c hard ip register addresses for ice40 ultraplus table 15: http://www.latticesemi.com/-/media/LatticeSemi/Documents/ApplicationNotes/AD/AdvancediCE40SPII2CHardenedIPUsageGuide.ashx?document_id=50117
    localparam [3:0] I2CCR1_ADDR = 4'h1;
    localparam [3:0] I2CTXDR_ADDR = 4'h8;
    localparam [3:0] I2CCMDR_ADDR = 4'h7;
    
    // hm0360 camera i2c slave address
    localparam [7:0] CAM_I2C_ADDR = 8'h24;
    
    // i2c control values
    localparam [7:0] I2CEN = 8'h80;
    localparam [7:0] CMD_START_WRITE = 8'h94;
    localparam [7:0] CMD_WRITE = 8'h14;
    localparam [7:0] CMD_STOP = 8'h44;
    localparam [15:0]
        MODE_SELECT = 16'h0100,
        SW_RESET = 16'h0103,
        COMMAND_UPDATE = 16'h0104,
        PLL1_CONFIG = 16'h0300,
        FRAME_LEN_LINES_H = 16'h0340,
        FRAME_LEN_LINES_L = 16'h0341,
        LINE_LEN_PCK_H = 16'h0342,
        LINE_LEN_PCK_L = 16'h0343;

    // camera config reg_addr[15:0], data[7:0]
    localparam CONFIG_LEN = 8;
    localparam REG_IDX_W = $clog2(CONFIG_LEN);

    localparam [3:0]
        IDLE = 4'd0,
        ENABLE_I2C = 4'd1,
        SEND_CAM_ADDR = 4'd2,
        SEND_START = 4'd3,
        LOAD_REG_H = 4'd4,
        SEND_WR_H = 4'd5,
        LOAD_REG_L = 4'd6,
        SEND_WR_L = 4'd7,
        LOAD_DATA = 4'd8,
        SEND_WR_DATA = 4'd9,
        SEND_STOP = 4'd10,
        NEXT_REG = 4'd11,
        DONE = 4'd12;

    logic [3:0] state;
    logic [3:0] next_state;
    logic [REG_IDX_W-1:0] reg_idx;
    logic [15:0] current_reg;
    logic [7:0] current_data;
    
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // counter for fsm to write all config values
    counter #(
        .WIDTH_P(REG_IDX_W),
        .MAX_VAL_P(CONFIG_LEN-1)
    ) reg_counter (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i('0),
        .up_i(1'b1),
        .down_i(1'b0),
        .en_i(state == NEXT_REG),
        .count_o(reg_idx)
    );
    
    always_comb begin
        // address and value to write from hm0360.cpp
        case (reg_idx)
            0: begin current_reg = SW_RESET; current_data = 8'h00; end
            1: begin current_reg = PLL1_CONFIG; current_data = 8'h08; end
            2: begin current_reg = FRAME_LEN_LINES_H; current_data = 8'h02; end
            3: begin current_reg = FRAME_LEN_LINES_L; current_data = 8'h14; end
            4: begin current_reg = LINE_LEN_PCK_H; current_data = 8'h03; end
            5: begin current_reg = LINE_LEN_PCK_L; current_data = 8'h00; end
            6: begin current_reg = COMMAND_UPDATE; current_data = 8'h01; end
            7: begin current_reg = MODE_SELECT; current_data = 8'h01; end
            default: begin current_reg = 16'h0; current_data = 8'h0; end
        endcase

        next_state = state;
        sbwr_o = 1'b0;
        sbstb_o = 1'b0;
        sbadri_o = 4'h0;
        sbdati_o = 8'h00;
        done_o = 1'b0;

        case (state)
            IDLE: begin
                next_state = ENABLE_I2C;
            end
            ENABLE_I2C: begin
                sbwr_o = 1'b1;
                sbstb_o = 1'b1;
                sbadri_o = I2CCR1_ADDR;
                sbdati_o = I2CEN;
                if (sback_i) next_state = SEND_CAM_ADDR;
            end
            SEND_CAM_ADDR: begin
                sbwr_o = 1'b1;
                sbstb_o = 1'b1;
                sbadri_o = I2CTXDR_ADDR;
                sbdati_o = CAM_I2C_ADDR;
                if (sback_i) next_state = SEND_START;
            end
            SEND_START: begin
                sbwr_o = 1'b1;
                sbstb_o = 1'b1;
                sbadri_o = I2CCMDR_ADDR;
                sbdati_o = CMD_START_WRITE;
                if (sback_i) next_state = LOAD_REG_H;
            end
            LOAD_REG_H: begin
                sbwr_o = 1'b1;
                sbstb_o = 1'b1;
                sbadri_o = I2CTXDR_ADDR;
                sbdati_o = current_reg[15:8];
                if (sback_i) next_state = SEND_WR_H;
            end
            SEND_WR_H: begin
                sbwr_o = 1'b1;
                sbstb_o = 1'b1;
                sbadri_o = I2CCMDR_ADDR;
                sbdati_o = CMD_WRITE;
                if (sback_i) next_state = LOAD_REG_L;
            end
            LOAD_REG_L: begin
                sbwr_o = 1'b1;
                sbstb_o = 1'b1;
                sbadri_o = I2CTXDR_ADDR;
                sbdati_o = current_reg[7:0];
                if (sback_i) next_state = SEND_WR_L;
            end
            SEND_WR_L: begin
                sbwr_o = 1'b1;
                sbstb_o = 1'b1;
                sbadri_o = I2CCMDR_ADDR;
                sbdati_o = CMD_WRITE;
                if (sback_i) next_state = LOAD_DATA;
            end
            LOAD_DATA: begin
                sbwr_o = 1'b1;
                sbstb_o = 1'b1;
                sbadri_o = I2CTXDR_ADDR;
                sbdati_o = current_data;
                if (sback_i) next_state = SEND_WR_DATA;
            end
            SEND_WR_DATA: begin
                sbwr_o = 1'b1;
                sbstb_o = 1'b1;
                sbadri_o = I2CCMDR_ADDR;
                sbdati_o = CMD_WRITE;
                if (sback_i) next_state = SEND_STOP;
            end
            SEND_STOP: begin
                sbwr_o = 1'b1;
                sbstb_o = 1'b1;
                sbadri_o = I2CCMDR_ADDR;
                sbdati_o = CMD_STOP;
                if (sback_i) next_state = (reg_idx == CONFIG_LEN-1) ? DONE : NEXT_REG;
            end
            NEXT_REG: begin
                next_state = SEND_CAM_ADDR;
            end
            DONE: begin
                done_o = 1'b1;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule