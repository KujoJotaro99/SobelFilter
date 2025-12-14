`timescale 1ns/1ps

module counter_tb;

    localparam int WIDTH_P = 8;
    localparam int SATURATE_P = 1;
    localparam int MAX_VAL_P = 128;

    logic clk_i;
    logic rstn_i;
    logic [WIDTH_P-1:0] data_i;
    logic up_i;
    logic down_i;
    logic load_i;
    logic en_i;
    logic [WIDTH_P-1:0] count_o;

    counter #(
        .WIDTH_P(WIDTH_P),
        .SATURATE_P(SATURATE_P),
        .MAX_VAL_P(MAX_VAL_P)
    ) dut (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(data_i),
        .up_i(up_i),
        .down_i(down_i),
        .load_i(load_i),
        .en_i(en_i),
        .count_o(count_o)
    );

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    task automatic reset_dut;
        begin
            rstn_i = 0;
            en_i = 1;
            load_i = 0;
            up_i = 0;
            down_i = 0;
            data_i = '0;
            repeat (2) @(negedge clk_i);
            rstn_i = 1;
            @(negedge clk_i);
        end
    endtask

    task automatic check_load(input int val);
        logic [WIDTH_P-1:0] exp;
        begin
            exp = val > MAX_VAL_P ? MAX_VAL_P : val;
            @(negedge clk_i);
            load_i = 1;
            data_i = val[WIDTH_P-1:0];
            up_i = 0;
            down_i = 0;
            @(negedge clk_i);
            @(negedge clk_i);
            load_i = 0;
            @(negedge clk_i);
            if (count_o !== exp) $fatal(1, "Load mismatch got %0d exp %0d", count_o, exp);
        end
    endtask

    task automatic check_increment;
        logic [WIDTH_P-1:0] exp;
        begin
            check_load(0);
            @(negedge clk_i);
            up_i = 1;
            down_i = 0;
            for (int i = 1; i <= 5; i++) begin
                exp = i[WIDTH_P-1:0];
                @(negedge clk_i);
                if (count_o !== exp) $fatal(1, "Increment step %0d got %0d exp %0d", i, count_o, exp);
            end
            check_load(MAX_VAL_P);
            @(negedge clk_i);
            up_i = 1;
            down_i = 0;
            @(negedge clk_i);
            if (count_o !== MAX_VAL_P[WIDTH_P-1:0]) $fatal(1, "Saturate increment mismatch got %0d exp %0d", count_o, MAX_VAL_P);
            @(negedge clk_i);
            if (count_o !== MAX_VAL_P[WIDTH_P-1:0]) $fatal(1, "Saturate hold mismatch got %0d exp %0d", count_o, MAX_VAL_P);
            up_i = 0;
        end
    endtask

    task automatic check_decrement;
        logic [WIDTH_P-1:0] exp;
        begin
            check_load(5);
            @(negedge clk_i);
            up_i = 0;
            down_i = 1;
            for (int i = 4; i >= 0; i--) begin
                exp = i[WIDTH_P-1:0];
                @(negedge clk_i);
                if (count_o !== exp) $fatal(1, "Decrement step %0d got %0d exp %0d", i, count_o, exp);
            end
            @(negedge clk_i);
            if (count_o !== '0) $fatal(1, "Decrement underflow expected 0 got %0d", count_o);
            down_i = 0;
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars();
        reset_dut();
        check_load(42);
        check_load(MAX_VAL_P + 10);
        check_increment();
        check_decrement();
        $display("counter_tb passed");
        $finish;
    end

endmodule
