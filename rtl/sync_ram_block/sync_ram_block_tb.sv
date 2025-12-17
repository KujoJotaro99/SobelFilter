`timescale 1ns/1ps

module sync_ram_block_tb;

    localparam int WIDTH_P = 8;
    localparam int DEPTH_P = 16;

    logic [0:0] clk_i;
    logic [0:0] rstn_i;
    logic [WIDTH_P-1:0] data_i;
    logic [$clog2(DEPTH_P)-1:0] wr_addr_i;
    logic [$clog2(DEPTH_P)-1:0] rd_addr_i;
    logic [0:0] wr_en_i;
    logic [0:0] rd_en_i;
    logic [WIDTH_P-1:0] data_o;

    sync_ram_block #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(DEPTH_P)
    ) dut (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(data_i),
        .wr_addr_i(wr_addr_i),
        .rd_addr_i(rd_addr_i),
        .wr_en_i(wr_en_i),
        .rd_en_i(rd_en_i),
        .data_o(data_o)
    );

    // simple clock
    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    task automatic reset_dut;
        begin
            rstn_i = 0;
            wr_en_i = 0;
            rd_en_i = 0;
            data_i = '0;
            wr_addr_i = '0;
            rd_addr_i = '0;
            @(posedge clk_i);
            @(posedge clk_i);
            rstn_i = 1;
            @(posedge clk_i);
        end
    endtask

    task automatic write_word(input int addr, input logic [WIDTH_P-1:0] val);
        begin
            @(negedge clk_i);
            wr_en_i = 1;
            rd_en_i = 0;
            wr_addr_i = addr[$clog2(DEPTH_P)-1:0];
            data_i = val;
            @(negedge clk_i);
            wr_en_i = 0;
        end
    endtask

    task automatic read_word(input int addr, output logic [WIDTH_P-1:0] val);
        begin
            @(negedge clk_i);
            rd_en_i = 1;
            rd_addr_i = addr[$clog2(DEPTH_P)-1:0];
            @(negedge clk_i);
            val = data_o;
            @(negedge clk_i);
            rd_en_i = 0;
        end
    endtask

    task automatic check_single;
        logic [WIDTH_P-1:0] rdata;
        begin
            write_word(0, 8'd42);
            read_word(0, rdata);
            if (rdata !== 8'd42) $fatal(1, "Single read mismatch got %0d exp 42", rdata);
        end
    endtask

    task automatic check_boundary;
        logic [WIDTH_P-1:0] rdata;
        begin
            write_word(DEPTH_P-1, {WIDTH_P{1'b1}});
            read_word(DEPTH_P-1, rdata);
            if (rdata !== {WIDTH_P{1'b1}}) $fatal(1, "Boundary read mismatch got %0d exp %0d", rdata, {WIDTH_P{1'b1}});
        end
    endtask

    task automatic check_same_cycle_rd_wr;
        logic [WIDTH_P-1:0] rdata;
        begin
            // preload
            write_word(0, 8'd7);
            // same-cycle rd/wr
            @(negedge clk_i);
            wr_en_i = 1;
            rd_en_i = 1;
            wr_addr_i = '0;
            rd_addr_i = '0;
            data_i = 8'd13;
            @(posedge clk_i);
            @(negedge clk_i);
            rd_en_i = 0;
            if (data_o !== 8'd7) $fatal(1, "Same cycle rd/wr old data expected 7 got %0d", data_o);
            wr_en_i = 0;
            rd_en_i = 1;
            @(negedge clk_i);
            @(posedge clk_i);
            if (data_o !== 8'd13) $fatal(1, "Updated data expected 13 got %0d", data_o);
            rd_en_i = 0;
        end
    endtask

    task automatic check_random;
        logic [WIDTH_P-1:0] exp [DEPTH_P-1:0];
        logic [WIDTH_P-1:0] rdata;
        int addr;
        begin
            for (int i = 0; i < DEPTH_P; i++) begin
                addr = i;
                exp[i] = $urandom;
                write_word(addr, exp[i]);
            end
            for (int i = 0; i < DEPTH_P; i++) begin
                addr = i;
                read_word(addr, rdata);
                if (rdata !== exp[i]) $fatal(1, "Random read mismatch addr %0d got %0d exp %0d", addr, rdata, exp[i]);
            end
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars();
        reset_dut();
        check_single();
        check_boundary();
        check_same_cycle_rd_wr();
        check_random();
        $display("sync_ram_block_tb passed");
        $finish;
    end

endmodule
