module conv2d #(
    parameter WIDTH_P = 8,
    parameter DEPTH_P = 16
)(
    input  logic clk_i,
    input  logic rstn_i,
    input  logic valid_i,
    input  logic ready_i,
    input  logic [WIDTH_P-1:0] data_i,
    output logic valid_o,
    output logic ready_o,
    output logic signed [(2*WIDTH_P)-1:0] gx_o,
    output logic signed [(2*WIDTH_P)-1:0] gy_o
);

    logic advance;
    assign advance = valid_i & ready_o;

    logic [WIDTH_P-1:0] ram_row0, ram_row1;

    ramdelaybuffer #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(2*DEPTH_P),
        .DELAY_A_P(2*DEPTH_P),
        .DELAY_B_P(DEPTH_P)
    ) line_buffer (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i),
        .ready_i(ready_i),
        .valid_o(valid_o),
        .ready_o(ready_o),
        .data_i(data_i),
        .data_a_o(ram_row0),
        .data_b_o(ram_row1)
    );

    // convolution sliding window
    logic [WIDTH_P-1:0] conv_window [2:0][2:0];

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            for (int r = 0; r < 3; r++) begin
                for (int c = 0; c < 3; c++) begin
                    conv_window[r][c] <= '0;
                end
            end
        end else if (advance) begin
            // shift data into each row
            for (int r = 0; r < 3; r++) begin
                conv_window[r][0] <= conv_window[r][1];
                conv_window[r][1] <= conv_window[r][2];
            end
            
            // shift corresponding row data into each row
            conv_window[0][2] <= ram_row0; // 2 rows ago
            conv_window[1][2] <= ram_row1; // 1 row ago
            conv_window[2][2] <= data_i; // newest data
        end
    end

    // sobel x and y kernel
    localparam signed [3:0] KX [2:0][2:0] = '{
        '{-1,  0,  1},
        '{-2,  0,  2},
        '{-1,  0,  1}
    };
    
    localparam signed [3:0] KY [2:0][2:0] = '{
        '{-1, -2, -1},
        '{ 0,  0,  0},
        '{ 1,  2,  1}
    };

    logic signed [(2*WIDTH_P)-1:0] gx_sum [0:8];
    logic signed [(2*WIDTH_P)-1:0] gy_sum [0:8];

    assign gx_sum[0] = $signed(conv_window[0][0]) * KX[0][0];
    assign gy_sum[0] = $signed(conv_window[0][0]) * KY[0][0];

    genvar t;
    generate
        for (t = 1; t < 9; t = t + 1) begin
            assign gx_sum[t] = gx_sum[t-1] + ($signed(conv_window[t/3][t%3]) * KX[t/3][t%3]);
            assign gy_sum[t] = gy_sum[t-1] + ($signed(conv_window[t/3][t%3]) * KY[t/3][t%3]);
        end
    endgenerate

    // gradient is sum of all previous values
    assign gx_o = gx_sum[8];
    assign gy_o = gy_sum[8];

endmodule
