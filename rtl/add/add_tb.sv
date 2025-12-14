`timescale 1ns/1ps

module add_tb;

    localparam int WIDTH_P = 32;

    logic [WIDTH_P-1:0] a_i;
    logic [WIDTH_P-1:0] b_i;
    logic [0:0] cin_i;
    logic [WIDTH_P-1:0] sum_o;
    logic [0:0] carry_o;

    add #(.WIDTH_P(WIDTH_P)) dut (
        .a_i(a_i),
        .b_i(b_i),
        .cin_i(cin_i),
        .sum_o(sum_o),
        .carry_o(carry_o)
    );

    task automatic check(input logic [WIDTH_P-1:0] a, input logic [WIDTH_P-1:0] b, input logic cin);
        logic [WIDTH_P:0] total;
        begin
            a_i = a;
            b_i = b;
            cin_i = cin;
            #1;
            total = a + b + cin;
            if (sum_o !== total[WIDTH_P-1:0] || carry_o !== total[WIDTH_P]) begin
                $fatal(1, "Mismatch a=%0d b=%0d cin=%0d got sum=%0d carry=%0d exp_sum=%0d exp_carry=%0d",
                       a, b, cin, sum_o, carry_o, total[WIDTH_P-1:0], total[WIDTH_P]);
            end
        end
    endtask

    initial begin
        // edge cases
        check('0, '0, 0);
        check({WIDTH_P{1'b1}}, '0, 0);
        check({WIDTH_P{1'b1}}, 1, 0);
        check(1 << (WIDTH_P-1), 1 << (WIDTH_P-1), 0);
        check(32'hAAAAAAAA[WIDTH_P-1:0], 32'h55555555[WIDTH_P-1:0], 1);

        // randomized cases
        repeat (100) begin
            check($urandom, $urandom, $urandom_range(0,1));
        end

        $display("add_tb passed");
        $finish;
    end

endmodule
