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
    input logic spiirq_i, // interrupt request 12.10 https://www.latticesemi.com/-/media/LatticeSemi/Documents/ApplicationNotes/AD2/FPGA-TN-02011-1-8-Advanced-iCE40-I2C-and-SPI-Hardened-IP-User-Guide.ashx?document_id=50117
    input logic sback_i, // transaction complete
    input logic [7:0] sbdato_i, // read data
    output logic sbrwi_o, // read or write selection, read only
    output logic sbstbi_o, // register transaction strobe
    output logic [7:0] sbadri_o, // register address
    output logic [7:0] sbdati_o, // write data
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
        sbadri_o = 8'h00;
        sbdati_o = 8'h00;
        sbstbi_o = 1'b0;
        sbrwi_o = 1'b0;
        
        case (curr_state)
            IDLE: begin
                if (spiirq_i) begin
                    next_state = CHECK_IRQ;
                end
            end

            CHECK_IRQ: begin
                if (!sback_i) begin
                    sbadri_o = IRQ_ADDR_P;
                    sbstbi_o = 1'b1;
                    sbrwi_o = 1'b0;
                end
                
                if (sback_i) begin
                    // completed register to signal valid rx
                    if (sbdato_i[IRQ_RRDY_BIT_P]) begin
                        next_state = READ_DATA;
                    // interrupt but no valid data unknown so just clear and wait for next interrupt
                    end else begin
                        next_state = CLEAR_IRQ;
                    end
                end
            end

            READ_DATA: begin
                if (!sback_i) begin
                    sbadri_o = RX_ADDR_P;
                    sbstbi_o = 1'b1;
                    sbrwi_o = 1'b0;
                end
                
                // stream out
                if (sback_i) begin
                    next_state = STREAM_OUT;
                end
            end

            STREAM_OUT: begin
                if (tready_i & tvalid_o) begin
                    next_state = IDLE;
                end
            end

            CLEAR_IRQ: begin
                if (!sback_i) begin
                    sbadri_o = IRQ_ADDR_P;
                    sbdati_o = (8'h1 << IRQ_RRDY_BIT_P);
                    sbstbi_o = 1'b1;
                    sbrwi_o = 1'b1;
                end
                
                if (sback_i) begin
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
            if (curr_state == READ_DATA && sback_i) begin
                tdata_o <= sbdato_i;
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

    // SB_SPI instance moved to top module

endmodule
