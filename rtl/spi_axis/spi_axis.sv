module spi_axis #(
    parameter int DATA_W = 8,
    parameter int TID_W = 1,
    parameter int TDEST_W = 1,
    parameter int TUSER_W = 1,
    parameter logic [7:0] RX_ADDR_P = 8'h00, // i dont have the addresses 
    parameter logic [7:0] IRQ_ADDR_P = 8'h00,
    parameter int IRQ_RRDY_BIT_P = 3,
    parameter bit IRQ_CLEAR_EN_P = 0
) (
    input logic clk_i, // core clock
    input logic rstn_i, // async active low reset

    input logic si_i, // incoming data from slave
    output logic scko_o, // generated serial clock
    output logic [DATA_W-1:0] tdata_o, // stream payload
    output logic [DATA_W/8-1:0] tkeep_o, // byte qualifier
    output logic [DATA_W/8-1:0] tstrb_o, // byte strobe
    output logic tlast_o, // end of packet
    output logic tvalid_o, // payload valid
    input logic tready_i // sink ready
);

    // fsm for spi macro interfacing 
    typedeg enum logic [1:0] {
        IDLE, 
        CHECK_IRQ,
        READ_DATA,
        WRITE_DATA
    } spi_state_t

    spi_state_t curr_state, next_state; // state tracker
    logic [0:0] IRQRRDY_o;
    logic [0:0] spiirq_o;
    logic [0:0] sbacko_o;
    logic [7:0] sbdato_o;

    // fsm
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            curr_state <= IDLE;
        end else begin
            curr_state <= next_state;
        end
    end

    always_comb begin
        next_state = curr_state;
        
        case (curr_state)
            IDLE: begin
                if (spiirq_o) begin
                    next_state = CHECK_IRQ;
                end
            end

            CHECK_IRQ: begin
                // if read and IRQRRDY bit high 
                if (sbacko_o & IRQRRDY_o) begin
                    next_state = READ_DATA;
                end else if (sback) begin
                    next_state = IDLE;
                end
            end

            READ_DATA: begin
                // 
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
        end
    end

    SB_SPI 
    #(
    ) u_sb_spi (
        .SBCLKI(clk_i), // system bus clock
        .SBRWI(), // read or write selection, read only
        .SBSTBI(sbstb), // register transaction strobe

        .SBADRI7(), // register address bit 7
        .SBADRI6(), // register address bit 6
        .SBADRI5(), // register address bit 5
        .SBADRI4(), // register address bit 4
        .SBADRI3(), // register address bit 3
        .SBADRI2(), // register address bit 2
        .SBADRI1(), // register address bit 1
        .SBADRI0(), // register address bit 0

        .SBDATI7(), // write data bit 7
        .SBDATI6(), // write data bit 6
        .SBDATI5(), // write data bit 5
        .SBDATI4(), // write data bit 4
        .SBDATI3(), // write data bit 3
        .SBDATI2(), // write data bit 2
        .SBDATI1(), // write data bit 1
        .SBDATI0(), // write data bit 0

        .MI(), // incoming data for master mode
        .SI(), // incoming data for slave mode
        .SCKI(), // external serial clock
        .SCSNI(), // external chip select

        .SBDATO7(sbdato_o[7]), // read data bit 7
        .SBDATO6(sbdato_o[6]), // read data bit 6
        .SBDATO5(sbdato_o[5]), // read data bit 5
        .SBDATO4(sbdato_o[4]), // read data bit 4
        .SBDATO3(sbdato_o[3]), // read data bit 3 IRQRRDY_o
        .SBDATO2(sbdato_o[2]), // read data bit 2
        .SBDATO1(sbdato_o[1]), // read data bit 1
        .SBDATO0(sbdato_o[0]), // read data bit 0

        .SBACKO(sbacko_o), // transaction complete
        .SPIIRQ(spiirq_o), // interrupt request, 12.10 https://www.latticesemi.com/-/media/LatticeSemi/Documents/ApplicationNotes/AD2/FPGA-TN-02011-1-8-Advanced-iCE40-I2C-and-SPI-Hardened-IP-User-Guide.ashx?document_id=50117
        .SPIWKUP(), // wakeup request
        .SO(), // serial data output
        .SOE(), // serial data output enable
        .MO(), // master data output
        .MOE(), // master data output enable
        .SCKO(), // serial clock output
        .SCKOE(), // serial clock output enable
        .MCSNO3(), // chip select 3 output
        .MCSNO2(), // chip select 2 output
        .MCSNO1(), // chip select 1 output
        .MCSNO0(), // chip select 0 output
        .MCSNOE3(), // chip select 3 enable
        .MCSNOE2(), // chip select 2 enable
        .MCSNOE1(), // chip select 1 enable
        .MCSNOE0() // chip select 0 enable
    );

endmodule
