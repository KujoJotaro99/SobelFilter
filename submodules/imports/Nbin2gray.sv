module Nbin2gray #(
    parameter N=8
)(
    input logic [N-1:0] bin_i,
    output logic [N-1:0] gray_o
);
    integer i;
    always_comb begin
        gray_o[N-1] = bin_i[N-1]; 
        for (i = N-2; i >= 0; i--) begin
            gray_o[i] = bin_i[i+1] ^ bin_i[i];
        end
    end
endmodule