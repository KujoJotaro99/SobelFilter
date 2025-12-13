`timescale 1ns/1ps

module shift_tb;

    localparam int WIDTH_P = 32;
    localparam int SHAMT_WIDTH_P = $clog2(WIDTH_P);

    logic [WIDTH_P-1:0] data_i;
    logic [SHAMT_WIDTH_P-1:0] shamt_i;
    logic [1:0] op_i;
    logic [WIDTH_P-1:0] shift_o;

    shift #(
        .WIDTH_P(WIDTH_P),
        .SHAMT_WIDTH_P(SHAMT_WIDTH_P)
    ) dut (
        .data_i(data_i),
        .shamt_i(shamt_i),
        .op_i(op_i),
        .shift_o(shift_o)
    );

    task automatic check(input logic [WIDTH_P-1:0] data, input logic [SHAMT_WIDTH_P-1:0] shamt, input logic [1:0] op);
        logic [WIDTH_P-1:0] expected;
        begin
            data_i = data;
            shamt_i = shamt;
            op_i = op;
            #1;
            case (op)
                2'd0: expected = data << shamt;
                2'd1: expected = data >> shamt;
                2'd2: expected = $signed(data) >>> shamt;
                default: expected = data;
            endcase
            if (shift_o !== expected) begin
                $fatal(1, "Shift mismatch op=%0d data=0x%08h shamt=%0d got=0x%08h exp=0x%08h",
                       op, data, shamt, shift_o, expected);
            end
        end
    endtask

    initial begin
        check('0, 0, 0);
        check({WIDTH_P{1'b1}}, 1, 0);
        check({WIDTH_P{1'b1}}, 1, 1);
        check({1'b1,{(WIDTH_P-1){1'b0}}}, WIDTH_P-1, 2);
        check(32'h0123_4567, WIDTH_P/2, 0);
        check(32'hDEAD_BEEF, 5'd4, 1);
        check(32'hDEAD_BEEF, 5'd4, 2);
        check(32'h0000_0001, 5'd0, 3);

        repeat (50) begin
            check($urandom, $urandom_range(0, WIDTH_P-1), 0);
            check($urandom, $urandom_range(0, WIDTH_P-1), 1);
            check($urandom, $urandom_range(0, WIDTH_P-1), 2);
        end

        $display("shift_tb passed");
        $finish;
    end

endmodule
