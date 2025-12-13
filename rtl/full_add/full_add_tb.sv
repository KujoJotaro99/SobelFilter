`timescale 1ns/1ps

module full_add_tb;

    logic a_i;
    logic b_i;
    logic cin_i;
    wire  sum_o;
    wire  carry_o;

    full_add dut (
        .a_i(a_i),
        .b_i(b_i),
        .cin_i(cin_i),
        .sum_o(sum_o),
        .carry_o(carry_o)
    );

    task automatic check(input logic a, input logic b, input logic cin);
        logic exp_sum;
        logic exp_carry;
        begin
            a_i   = a;
            b_i   = b;
            cin_i = cin;
            #1;
            exp_sum   = a ^ b ^ cin;
            exp_carry = ((a ^ b) & cin) | (a & b);
            if (sum_o !== exp_sum || carry_o !== exp_carry) begin
                $fatal(1,
                    "Mismatch a=%0b b=%0b cin=%0b got sum=%0b carry=%0b exp_sum=%0b exp_carry=%0b",
                    a, b, cin, sum_o, carry_o, exp_sum, exp_carry
                );
            end
        end
    endtask

    // fixed endless simulation, logic is 4 state and needs to be initialized otherwise starts at x
    int i;

    initial begin
        for (i = 0; i < 8; i++) begin
            check(i[2], i[1], i[0]);
            #1;
        end
        $display("full_add_tb passed");
        $finish;
    end


endmodule
