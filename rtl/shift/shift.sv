`timescale 1ns/1ps
    
module shift #(
    parameter WIDTH_P = 32,
    parameter SHAMT_WIDTH_P = $clog2(WIDTH_P) 
) (
    input logic [WIDTH_P-1:0] data_i,
    input logic [SHAMT_WIDTH_P-1:0] shamt_i,
    input logic [1:0] op_i, // 0: SLL, 1: SRL, 2: SRA
    output logic [WIDTH_P-1:0] shift_o
);

    always_comb begin
        shift_o = data_i;
        unique case (op_i)
            2'b00: shift_o = data_i << shamt_i; //SLL
            2'b01: shift_o = data_i >> shamt_i; //SLR
            2'b10: shift_o = $signed(data_i) >>> shamt_i; // sra/srai via manual sign-extend
            // 2'b10: shift_o = ( ( { {WIDTH_P{data_i[WIDTH_P-1]}}, data_i } ) >> shamt_i );  lint and also verilator forbids splicing [WIDTH_P-1:0] after concat expressions
            default: ; // on invalid op do nothing
        endcase
    end

endmodule
