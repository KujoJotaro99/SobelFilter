`timescale 1ns/1ps

module half_add_tb;

    logic a_i;
    logic b_i;
    logic sum_o;
    logic carry_o;

    half_add dut (
        .a_i(a_i),
        .b_i(b_i),
        .sum_o(sum_o),
        .carry_o(carry_o)
    );

    task automatic check(input logic a, input logic b);
        logic exp_sum;
        logic exp_carry;
        begin
            a_i = a;
            b_i = b;
            #1;
            exp_sum = a ^ b;
            exp_carry = a & b;
            if (sum_o !== exp_sum || carry_o !== exp_carry) begin
                $fatal(1, "Mismatch a=%0b b=%0b got sum=%0b carry=%0b exp_sum=%0b exp_carry=%0b",
                       a, b, sum_o, carry_o, exp_sum, exp_carry);
            end
        end
    endtask

    initial begin
        check(0, 0);
        check(0, 1);
        check(1, 0);
        check(1, 1);
        $display("half_add_tb passed");
        $finish;
    end

endmodule
