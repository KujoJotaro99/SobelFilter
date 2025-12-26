`timescale 1ns/1ps

module counter_tb;

    localparam int WIDTH_P = 8;
    localparam int MAX_VAL_P = 128;

    logic [0:0] clk_i;
    logic [0:0] rstn_i;
    logic [WIDTH_P-1:0] rstn_data_i;
    logic [0:0] up_i;
    logic [0:0] down_i;
    logic [0:0] en_i;
    logic [WIDTH_P-1:0] count_o;

    counter #(
        .WIDTH_P(WIDTH_P),
        .MAX_VAL_P(MAX_VAL_P)
    ) dut (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i(rstn_data_i),
        .up_i(up_i),
        .down_i(down_i),
        .en_i(en_i),
        .count_o(count_o)
    );

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    task automatic reset_dut;
        begin
            rstn_i = 0;
            rstn_data_i = '0;
            en_i = 1;
            up_i = 0;
            down_i = 0;
            repeat (2) @(negedge clk_i);
            rstn_i = 1;
            @(negedge clk_i);
        end
    endtask

    task automatic check_increment;
        logic [WIDTH_P-1:0] exp;
        begin
            rstn_i = 0;
            rstn_data_i = '0;
            @(negedge clk_i);
            rstn_i = 1;
            @(negedge clk_i);
            up_i = 1;
            down_i = 0;
            for (int i = 1; i <= 5; i++) begin
                exp = i[WIDTH_P-1:0];
                @(negedge clk_i);
                if (count_o !== exp) $fatal(1, "Increment step %0d got %0d exp %0d", i, count_o, exp);
            end
            rstn_i = 0;
            rstn_data_i = MAX_VAL_P[WIDTH_P-1:0];
            up_i = 0;
            down_i = 0;
            @(negedge clk_i);
            rstn_i = 1;
            @(negedge clk_i);
            up_i = 1;
            down_i = 0;
            @(negedge clk_i);
            if (count_o !== '0) $fatal(1, "Wrap increment mismatch got %0d exp 0", count_o);
            up_i = 0;
        end
    endtask

    task automatic check_decrement;
        logic [WIDTH_P-1:0] exp;
        begin
            rstn_i = 0;
            rstn_data_i = 5;
            @(negedge clk_i);
            rstn_i = 1;
            @(negedge clk_i);
            up_i = 0;
            down_i = 1;
            for (int i = 4; i >= 0; i--) begin
                exp = i[WIDTH_P-1:0];
                @(negedge clk_i);
                if (count_o !== exp) $fatal(1, "Decrement step %0d got %0d exp %0d", i, count_o, exp);
            end
            @(negedge clk_i);
            if (count_o !== MAX_VAL_P[WIDTH_P-1:0]) $fatal(1, "Wrap decrement mismatch got %0d exp %0d", count_o, MAX_VAL_P);
            down_i = 0;
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, counter_tb);
        reset_dut();
        rstn_data_i = '0;
        check_increment();
        check_decrement();
        $display("counter_tb passed");
        $finish;
    end

endmodule
