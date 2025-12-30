`timescale 1ns/1ps

module rgb2gray_tb;

    localparam int WIDTH_P = 8;

    logic [0:0] clk_i;
    logic [0:0] rstn_i;
    logic [0:0] valid_i;
    logic [0:0] ready_i;
    logic [0:0] valid_o;
    logic [0:0] ready_o;
    logic [WIDTH_P-1:0] red_i;
    logic [WIDTH_P-1:0] blue_i;
    logic [WIDTH_P-1:0] green_i;
    logic [WIDTH_P-1:0] gray_o;
    real sse;
    int n;

    rgb2gray #(
        .WIDTH_P(WIDTH_P)
    ) dut (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i),
        .ready_i(ready_i),
        .valid_o(valid_o),
        .ready_o(ready_o),
        .red_i(red_i),
        .blue_i(blue_i),
        .green_i(green_i),
        .gray_o(gray_o)
    );

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    function automatic [WIDTH_P-1:0] calc_gray(
        input [WIDTH_P-1:0] red,
        input [WIDTH_P-1:0] green,
        input [WIDTH_P-1:0] blue
    );
        real gray;
        begin
            gray = ($itor(red) * 0.299) + ($itor(green) * 0.587) + ($itor(blue) * 0.114);
            calc_gray = $rtoi(gray);
        end
    endfunction

    task automatic reset_dut;
        begin
            rstn_i = 0;
            valid_i = 0;
            ready_i = 1;
            red_i = '0;
            green_i = '0;
            blue_i = '0;
            repeat (2) @(negedge clk_i);
            rstn_i = 1;
            @(negedge clk_i);
        end
    endtask

    task automatic drive_and_check(
        input [WIDTH_P-1:0] red,
        input [WIDTH_P-1:0] green,
        input [WIDTH_P-1:0] blue
    );
        logic [WIDTH_P-1:0] exp;
        integer err;
        begin
            exp = calc_gray(red, green, blue);
            @(negedge clk_i);
            valid_i = 1;
            red_i = red;
            green_i = green;
            blue_i = blue;
            @(negedge clk_i);
            valid_i = 0;
            red_i = '0;
            green_i = '0;
            blue_i = '0;
            if (valid_o !== 1'b1) $fatal(1, "valid_o not asserted");
            err = $signed(gray_o) - $signed(exp);
            sse = sse + (err * err);
            n = n + 1;
        end
    endtask

    task automatic check_reset_hold;
        begin
            reset_dut();
            valid_i = 0;
            repeat (4) begin
                @(negedge clk_i);
                if (valid_o !== 1'b0) $fatal(1, "valid_o should stay low while valid_i is low");
            end
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, rgb2gray_tb);
        sse = 0.0;
        n = 0;

        check_reset_hold();
        drive_and_check('0, '0, '0);
        drive_and_check('1, '1, '1);
        drive_and_check(8'hFF, '0, '0);
        drive_and_check('0, 8'hFF, '0);
        drive_and_check('0, '0, 8'hFF);
        for (int i = 0; i < 10; i++) begin
            drive_and_check($urandom, $urandom, $urandom);
        end

        if (n > 0) begin
            if ($sqrt(sse / n) > 12.0) $fatal(1, "RMS error too high: %0f", $sqrt(sse / n));
        end
        $display("rgb2gray_tb passed");
        $finish;
    end

endmodule
