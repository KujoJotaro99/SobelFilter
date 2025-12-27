module spi_axis #(
    parameter int DATA_W = 8,
    parameter int TID_W = 1,
    parameter int TDEST_W = 1,
    parameter int TUSER_W = 1,
    parameter logic [7:0] RX_ADDR_P = 8'h0E, // SPIRXDR address
    parameter logic [7:0] IRQ_ADDR_P = 8'h06, // SPIIRQ address
    parameter int IRQ_RRDY_BIT_P = 3
) (
    input logic clk_i, // core clock
    input logic rstn_i, // async active low reset
    input logic mi_i, // incoming data from slave
    output logic scko_o, // generated serial clock
    output logic sckoe_o, // enable
    output logic mcsno0_o, // master chip select output
    output logic mcsnoe0_o, // enable
    output logic [DATA_W-1:0] tdata_o, // stream payload
    output logic [DATA_W/8-1:0] tkeep_o, // byte qualifier
    output logic [DATA_W/8-1:0] tstrb_o, // byte strobe
    output logic tlast_o, // end of packet
    output logic tvalid_o, // payload valid
    input logic tready_i // sink ready
);

    // fsm for spi macro interfacing 
    typedef enum logic [2:0] {
        IDLE, 
        CHECK_IRQ,
        READ_DATA,
        STREAM_OUT,
        CLEAR_IRQ
    } spi_state_t;

    spi_state_t curr_state, next_state; // state tracker
    logic spiirq_o;
    logic sbacko_o;
    logic [7:0] sbdato_o;
    logic [7:0] sbdati_i;
    logic [7:0] sbadri_i;
    logic sbstbi_i;
    logic sbrwi_i;

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
        sbadri_i = 8'h00;
        sbdati_i = 8'h00;
        sbstbi_i = 1'b0;
        sbrwi_i = 1'b0;
        
        case (curr_state)
            IDLE: begin
                if (spiirq_o) begin
                    next_state = CHECK_IRQ;
                end
            end

            CHECK_IRQ: begin
                if (!sbacko_o) begin
                    sbadri_i = IRQ_ADDR_P;
                    sbstbi_i = 1'b1;
                    sbrwi_i = 1'b0;
                end
                
                if (sbacko_o) begin
                    // completed register to signal valid rx
                    if (sbdato_o[IRQ_RRDY_BIT_P]) begin
                        next_state = READ_DATA;
                    // interrupt but no valid data unknown so just clear and wait for next interrupt
                    end else begin
                        next_state = CLEAR_IRQ;
                    end
                end
            end

            READ_DATA: begin
                if (!sbacko_o) begin
                    sbadri_i = RX_ADDR_P;
                    sbstbi_i = 1'b1;
                    sbrwi_i = 1'b0;
                end
                
                // stream out
                if (sbacko_o) begin
                    next_state = STREAM_OUT;
                end
            end

            STREAM_OUT: begin
                if (tready_i & tvalid_o) begin
                    next_state = IDLE;
                end
            end

            CLEAR_IRQ: begin
                if (!sbacko_o) begin
                    sbadri_i = IRQ_ADDR_P;
                    sbdati_i = (8'h1 << IRQ_RRDY_BIT_P);
                    sbstbi_i = 1'b1;
                    sbrwi_i = 1'b1;
                end
                
                if (sbacko_o) begin
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            tdata_o <= '0;
            tvalid_o <= 1'b0;
        end else begin
            // read rx register to collect valid data
            if (curr_state == READ_DATA && sbacko_o) begin
                tdata_o <= sbdato_o;
                tvalid_o <= 1'b1;
            end
            
            // reset valid for next rx transaction
            if (curr_state == STREAM_OUT && tvalid_o && tready_i) begin
                tvalid_o <= 1'b0;
            end
        end
    end

    assign tkeep_o = {(DATA_W/8){1'b1}};
    assign tstrb_o = {(DATA_W/8){1'b1}};
    assign tlast_o  = 1'b0;

    SB_SPI 
    #(
        .BUS_ADDR74()
    ) u_sb_spi (
        .SBCLKI(clk_i), // system bus clock
        .SBRWI(sbrwi_i), // read or write selection, read only
        .SBSTBI(sbstbi_i), // register transaction strobe

        .SBADRI7(sbadri_i[7]), // register address bit 7
        .SBADRI6(sbadri_i[6]), // register address bit 6
        .SBADRI5(sbadri_i[5]), // register address bit 5
        .SBADRI4(sbadri_i[4]), // register address bit 4
        .SBADRI3(sbadri_i[3]), // register address bit 3
        .SBADRI2(sbadri_i[2]), // register address bit 2
        .SBADRI1(sbadri_i[1]), // register address bit 1
        .SBADRI0(sbadri_i[0]), // register address bit 0

        .MI(mi_i), // incoming data for master mode
        .SI(1'b0), // unused in master mode
        .SCKI(1'b0), // unused in master mode
        .SCSNI(1'b1), // unused in master mode

        .SBDATO7(sbdato_o[7]), // read data bit 7
        .SBDATO6(sbdato_o[6]), // read data bit 6
        .SBDATO5(sbdato_o[5]), // read data bit 5
        .SBDATO4(sbdato_o[4]), // read data bit 4
        .SBDATO3(sbdato_o[3]), // read data bit 3 IRQRRDY_l
        .SBDATO2(sbdato_o[2]), // read data bit 2
        .SBDATO1(sbdato_o[1]), // read data bit 1
        .SBDATO0(sbdato_o[0]), // read data bit 0

        .SBACKO(sbacko_o), // transaction complete
        .SPIIRQ(spiirq_o), // interrupt request 12.10 https://www.latticesemi.com/-/media/LatticeSemi/Documents/ApplicationNotes/AD2/FPGA-TN-02011-1-8-Advanced-iCE40-I2C-and-SPI-Hardened-IP-User-Guide.ashx?document_id=50117
        .SPIWKUP(), // wakeup request

        .SCKO(scko_o), // serial clock output
        .SCKOE(sckoe_o), // serial clock output enable

        .MCSNO0(mcsno0_o), // chip select 0 output
        .MCSNOE0(mcsnoe0_o), // chip select 0 enable

        .SBDATI7(sbdati_i[7]), // write data bit 7
        .SBDATI6(sbdati_i[6]), // write data bit 6
        .SBDATI5(sbdati_i[5]), // write data bit 5
        .SBDATI4(sbdati_i[4]), // write data bit 4
        .SBDATI3(sbdati_i[3]), // write data bit 3
        .SBDATI2(sbdati_i[2]), // write data bit 2
        .SBDATI1(sbdati_i[1]), // write data bit 1
        .SBDATI0(sbdati_i[0]), // write data bit 0

        .SO(), // unused
        .SOE(), // unused
        .MO(), // unused
        .MOE(), // unused
        .MCSNO3(), // unused
        .MCSNO2(), // unused
        .MCSNO1(), // unused
        .MCSNOE3(), // unused
        .MCSNOE2(), // unused
        .MCSNOE1() // unused
    );

endmodule
