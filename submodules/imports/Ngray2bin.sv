module Ngray2bin #(
    parameter N = 8
)(
    input logic [N-1:0] gray_i,
    output logic [N-1:0] bin_o
);
    integer i;
    always_comb begin
        bin_o[N-1] = gray_i[N-1];
        for (i = N-2; i >= 0; i--) begin
            bin_o[i] = bin_o[i+1] ^ gray_i[i];
        end
    end
endmodule