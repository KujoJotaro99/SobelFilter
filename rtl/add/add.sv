`timescale 1ns/1ps

module add #(
    parameter WIDTH_P = 32
)(
    input logic [WIDTH_P-1:0] a_i,
    input logic [WIDTH_P-1:0] b_i,
    input logic [0:0] cin_i,
    output logic [WIDTH_P-1:0] sum_o,
    output logic [0:0] carry_o
);

  // generate indicates the jth but produces a carry on its own (1 + 1), regardless of carry_in
  // propagate indicates the jth bit will propagate any incoming carry (0 + 1 or 1 + 0) + carry_in
  logic [WIDTH_P-1:0] p, g, P, G, C; // p: bit j propagates a carry, g: bit j generates a carry, P: block 0 to j propagates a carry, G: block 0 to j generates a carry, C: carry

  // bit level propagate carry and generate
  genvar i;
  generate
    for (i = 0; i < WIDTH_P; i++) begin : propagate_generate
      // assign p[i] = a_i[i]^b_i[i]; // if either a OR b is 1, any incoming carry_in propagate a carry out
      // assign g[i] = a_i[i]&b_i[i]; // this will definitely generate a carry out
      half_add ha_inst (
          .a_i(a_i[i]),
          .b_i(b_i[i]),
          .sum_o(p[i]),
          .carry_o(g[i])
      );
    end
  endgenerate

  // range level propagate carry and generate
  genvar j;
  generate
    for (j = 0; j < WIDTH_P; j++) begin : range_carry
      if (j == 0) begin
        assign G[j] = g[0];
        assign P[j] = p[0];
      end else begin
        assign G[j] = g[j] | (p[j] & G[j-1]); // if current bit generates a carry, OR current bit propagates a carry AND previous bit generated a carry , then this bit will generate a carry
        assign P[j] = p[j] & P[j-1]; // if current bit propagates a carry AND previous bit propagates a carry, this bit will also propagate a carry
      end
    end
  endgenerate

  // carry logic
  genvar k;
  generate
      for (k = 0; k < WIDTH_P; k++) begin : carry_logic
          if (k == 0) begin
              assign C[k] = g[0] | (p[0] & cin_i);
          end else begin
              assign C[k] = g[k] | (p[k] & C[k-1]); // if current bit generates a carry, OR current bit propagates a carry and there is an incoming carry, then this bit will have a carry out
          end
      end
  endgenerate

  assign carry_o = C[WIDTH_P-1]; // final carry out is just final bit

  // sum logic
  genvar m;
  generate
      for (m = 0; m < WIDTH_P; m++) begin : sum_logic
          assign sum_o[m] = p[m] ^ ((m == 0) ? cin_i : C[m-1]); // sum is bit propagate XOR carry in, basically the original full adder sum logic a ^ b ^ cin
      end
  endgenerate

endmodule


