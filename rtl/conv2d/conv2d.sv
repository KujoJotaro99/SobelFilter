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

    // elastic handshake
    elastic #(
        .WIDTH_P(WIDTH_P)
    ) stream_pipe (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i('0),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .valid_o(valid_o),
        .data_o(),
        .ready_i(ready_i)
    );

    // col counter
    logic [$clog2(DEPTH_P)-1:0] pixel_col;

    counter #(
        .WIDTH_P($clog2(DEPTH_P)),
        .MAX_VAL_P(DEPTH_P-1), // unused
        .SATURATE_P(0)
    ) col_counter (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i('0),
        .data_i('0),
        .up_i(valid_i & ready_o),
        .down_i(1'b0),
        .load_i((valid_i & ready_o) && (pixel_col == ($clog2(DEPTH_P))'(DEPTH_P-1))),
        .en_i(1'b1),
        .count_o(pixel_col)
    );

    // circular buffer
    logic [$clog2(3*DEPTH_P)-1:0] wr_addr, rd_addr_a, rd_addr_b;

    // write pointer current position
    counter #(
        .WIDTH_P($clog2(3*DEPTH_P)),
        .MAX_VAL_P(3*DEPTH_P-1), // unused
        .SATURATE_P(0)
    ) wr_ptr_counter (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i('0),
        .data_i('0),
        .up_i(valid_i & ready_o),
        .down_i(1'b0),
        .load_i((valid_i & ready_o) && (wr_addr == ($clog2(3*DEPTH_P))'(3*DEPTH_P-1))),
        .en_i(1'b1),
        .count_o(wr_addr)
    );

    // read pointer a 2 row ago 1*DEPTH_P
    counter #(
        .WIDTH_P($clog2(3*DEPTH_P)),
        .MAX_VAL_P(3*DEPTH_P-1), // unused
        .SATURATE_P(0)
    ) rd_ptr_a_counter (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i(($clog2(3*DEPTH_P))'(DEPTH_P)),
        .data_i('0),
        .up_i(valid_i & ready_o),
        .down_i(1'b0),
        .load_i((valid_i & ready_o) && (rd_addr_a == ($clog2(3*DEPTH_P))'(3*DEPTH_P-1))),
        .en_i(1'b1),
        .count_o(rd_addr_a)
    );

    // read pointer b 1 row ago 2*DEPTH_P
    counter #(
        .WIDTH_P($clog2(3*DEPTH_P)),
        .MAX_VAL_P(3*DEPTH_P-1), // unused
        .SATURATE_P(0)
    ) rd_ptr_b_counter (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i(($clog2(3*DEPTH_P))'(2*DEPTH_P)),
        .data_i('0),
        .up_i(valid_i & ready_o),
        .down_i(1'b0),
        .load_i((valid_i & ready_o) && (rd_addr_b == ($clog2(3*DEPTH_P))'(3*DEPTH_P-1))),
        .en_i(1'b1),
        .count_o(rd_addr_b)
    );

    // line buffers
    logic [WIDTH_P-1:0] ram_row0, ram_row1;

    // dual read port ram since need access to 2 rows
    sync_ram_block #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(3*DEPTH_P)
    ) line_ram (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(data_i),
        .wr_addr_i(wr_addr),
        .rd_addr_a_i(rd_addr_a),
        .rd_addr_b_i(rd_addr_b),
        .wr_en_i(valid_i & ready_o),
        .rd_en_a_i(valid_i & ready_o),
        .rd_en_b_i(valid_i & ready_o),
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
        end else if (valid_i && ready_o) begin
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