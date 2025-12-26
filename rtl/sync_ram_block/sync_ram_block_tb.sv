`timescale 1ns/1ps

module sync_ram_block_tb;

    localparam int WIDTH_P = 8;
    localparam int DEPTH_P = 16;

    logic clk_i;
    logic rstn_i;
    logic [WIDTH_P-1:0] data_i;
    logic [$clog2(DEPTH_P)-1:0] wr_addr_i;
    logic [$clog2(DEPTH_P)-1:0] rd_addr_a_i;
    logic [$clog2(DEPTH_P)-1:0] rd_addr_b_i;
    logic wr_en_i;
    logic rd_en_a_i;
    logic rd_en_b_i;
    logic [WIDTH_P-1:0] data_a_o;
    logic [WIDTH_P-1:0] data_b_o;

    sync_ram_block #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(DEPTH_P)
    ) dut (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(data_i),
        .wr_addr_i(wr_addr_i),
        .rd_addr_a_i(rd_addr_a_i),
        .rd_addr_b_i(rd_addr_b_i),
        .wr_en_i(wr_en_i),
        .rd_en_a_i(rd_en_a_i),
        .rd_en_b_i(rd_en_b_i),
        .data_a_o(data_a_o),
        .data_b_o(data_b_o)
    );

    // simple clock
    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    task automatic reset_dut;
        begin
            rstn_i = 0;
            wr_en_i = 0;
            rd_en_a_i = 0;
            rd_en_b_i = 0;
            data_i = '0;
            wr_addr_i = '0;
            rd_addr_a_i = '0;
            rd_addr_b_i = '0;
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
            rd_en_a_i = 0;
            rd_en_b_i = 0;
            wr_addr_i = addr[$clog2(DEPTH_P)-1:0];
            data_i = val;
            @(negedge clk_i);
            wr_en_i = 0;
        end
    endtask

    task automatic read_word_a(input int addr, output logic [WIDTH_P-1:0] val);
        begin
            @(negedge clk_i);
            rd_en_a_i = 1;
            rd_addr_a_i = addr[$clog2(DEPTH_P)-1:0];
            @(negedge clk_i);
            val = data_a_o;
            @(negedge clk_i);
            rd_en_a_i = 0;
        end
    endtask

    task automatic read_word_b(input int addr, output logic [WIDTH_P-1:0] val);
        begin
            @(negedge clk_i);
            rd_en_b_i = 1;
            rd_addr_b_i = addr[$clog2(DEPTH_P)-1:0];
            @(negedge clk_i);
            val = data_b_o;
            @(negedge clk_i);
            rd_en_b_i = 0;
        end
    endtask

    task automatic read_dual(input int addr_a, input int addr_b,
                             output logic [WIDTH_P-1:0] val_a,
                             output logic [WIDTH_P-1:0] val_b);
        begin
            @(negedge clk_i);
            rd_en_a_i = 1;
            rd_en_b_i = 1;
            rd_addr_a_i = addr_a[$clog2(DEPTH_P)-1:0];
            rd_addr_b_i = addr_b[$clog2(DEPTH_P)-1:0];
            @(negedge clk_i);
            val_a = data_a_o;
            val_b = data_b_o;
            @(negedge clk_i);
            rd_en_a_i = 0;
            rd_en_b_i = 0;
        end
    endtask

    task automatic check_single;
        logic [WIDTH_P-1:0] rdata;
        begin
            write_word(0, 8'd42);
            read_word_a(0, rdata);
            if (rdata !== 8'd42) $fatal(1, "Single read mismatch on port A got %0d exp 42", rdata);
            read_word_b(0, rdata);
            if (rdata !== 8'd42) $fatal(1, "Single read mismatch on port B got %0d exp 42", rdata);
        end
    endtask

    task automatic check_boundary;
        logic [WIDTH_P-1:0] rdata_a, rdata_b;
        begin
            write_word(DEPTH_P-1, {WIDTH_P{1'b1}});
            read_dual(DEPTH_P-1, DEPTH_P-1, rdata_a, rdata_b);
            if (rdata_a !== {WIDTH_P{1'b1}}) $fatal(1, "Boundary read mismatch on port A got %0d exp %0d", rdata_a, {WIDTH_P{1'b1}});
            if (rdata_b !== {WIDTH_P{1'b1}}) $fatal(1, "Boundary read mismatch on port B got %0d exp %0d", rdata_b, {WIDTH_P{1'b1}});
        end
    endtask

    task automatic check_same_cycle_rd_wr;
        begin
            // preload
            write_word(0, 8'd7);
            // same-cycle rd/wr on port A
            @(negedge clk_i);
            wr_en_i = 1;
            rd_en_a_i = 1;
            wr_addr_i = '0;
            rd_addr_a_i = '0;
            data_i = 8'd13;
            @(posedge clk_i);
            @(negedge clk_i);
            rd_en_a_i = 0;
            if (data_a_o !== 8'd7) $fatal(1, "Same cycle rd/wr old data expected 7 got %0d", data_a_o);
            wr_en_i = 0;
            rd_en_a_i = 1;
            @(negedge clk_i);
            @(posedge clk_i);
            if (data_a_o !== 8'd13) $fatal(1, "Updated data expected 13 got %0d", data_a_o);
            rd_en_a_i = 0;
        end
    endtask

    task automatic check_dual_read;
        logic [WIDTH_P-1:0] data_a, data_b;
        begin
            write_word(0, 8'd55);
            write_word(1, 8'd11);
            read_dual(0, 1, data_a, data_b);
            if (data_a !== 8'd55) $fatal(1, "Dual read mismatch port A exp 55 got %0d", data_a);
            if (data_b !== 8'd11) $fatal(1, "Dual read mismatch port B exp 11 got %0d", data_b);
        end
    endtask

    task automatic check_conflicting_reads;
        logic [WIDTH_P-1:0] data_a, data_b;
        begin
            write_word(4, 8'd77);
            read_dual(4, 4, data_a, data_b);
            if (data_a !== 8'd77 || data_b !== 8'd77) begin
                $fatal(1, "Conflicting dual read mismatch A=%0d B=%0d", data_a, data_b);
            end
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
                if (i % 2 == 0) begin
                    read_word_a(addr, rdata);
                end else begin
                    read_word_b(addr, rdata);
                end
                if (rdata !== exp[i]) $fatal(1, "Random read mismatch addr %0d got %0d exp %0d", addr, rdata, exp[i]);
            end
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, sync_ram_block_tb);
        reset_dut();
        check_single();
        check_boundary();
        check_same_cycle_rd_wr();
        check_dual_read();
        check_conflicting_reads();
        check_random();
        $display("sync_ram_block_tb passed");
        $finish;
    end

endmodule
