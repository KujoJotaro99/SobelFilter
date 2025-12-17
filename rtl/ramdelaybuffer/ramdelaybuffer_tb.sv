`timescale 1ns/1ps

module ramdelaybuffer_tb;

    localparam int WIDTH_P = 8;
    localparam int DELAY_P = 12;

    logic clk_i;
    logic rstn_i;
    logic valid_i;
    logic ready_i;
    logic valid_o;
    logic ready_o;
    logic [WIDTH_P-1:0] data_i;
    logic [WIDTH_P-1:0] data_o;

    ramdelaybuffer #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(DELAY_P)
    ) dut (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i),
        .ready_i(ready_i),
        .valid_o(valid_o),
        .ready_o(ready_o),
        .data_i(data_i),
        .data_o(data_o)
    );

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    task automatic reset_dut;
        begin
            rstn_i = 0;
            valid_i = 0;
            ready_i = 1;
            data_i = '0;
            repeat (3) @(negedge clk_i);
            rstn_i = 1;
            @(negedge clk_i);
        end
    endtask

    task automatic push_word(input logic [WIDTH_P-1:0] word);
        begin
            @(negedge clk_i);
            valid_i = 1;
            data_i = word;
            @(negedge clk_i);
            valid_i = 0;
            data_i = '0;
        end
    endtask

    task automatic check_reset_hold;
        begin
            reset_dut();
            valid_i = 0;
            repeat (DELAY_P + 3) begin
                @(negedge clk_i);
                if (valid_o !== 1'b0) $fatal(1, "valid_o should stay low while valid_i is low");
            end
        end
    endtask

    task automatic check_expected_delay;
        logic [WIDTH_P-1:0] token;
        begin
            reset_dut();
            token = $urandom;
            if (token == '0) token = 'd1;

            push_word(token);
            for (int i = 0; i < DELAY_P; i++) begin
                push_word('0);
            end

            if (data_o !== token) $fatal(1, "Delayed value mismatch got %0d exp %0d", data_o, token);
        end
    endtask

    task automatic check_wraparound;
        localparam int TOTAL = (DELAY_P * 2) + 3;
        logic [WIDTH_P-1:0] sent [0:TOTAL-1];
        logic [WIDTH_P-1:0] observed [0:TOTAL-1];
        logic [WIDTH_P-1:0] word;
        int obs_idx;
        begin
            reset_dut();
            for (int i = 0; i < TOTAL; i++) begin
                sent[i] = (i + 1);
            end

            obs_idx = 0;
            for (int i = 0; i < (TOTAL + DELAY_P); i++) begin
                word = (i < TOTAL) ? sent[i] : '0;
                push_word(word);
                if ((i >= DELAY_P) && ((i - DELAY_P) < TOTAL)) begin
                    observed[obs_idx] = data_o;
                    obs_idx++;
                end
            end

            for (int i = 0; i < TOTAL; i++) begin
                if (observed[i] !== sent[i]) begin
                    $fatal(1, "Wraparound ordering mismatch idx %0d got %0d exp %0d", i, observed[i], sent[i]);
                end
            end
        end
    endtask

    task automatic check_valid_deassert_and_gaps;
        localparam int MAX_SAMPLES = 256;
        logic [WIDTH_P-1:0] hist [0:MAX_SAMPLES-1];
        logic [WIDTH_P-1:0] exp;
        logic [WIDTH_P-1:0] word;
        int idle_cycles;
        int hs;
        begin
            reset_dut();
            hs = 0;

            for (int i = 0; i < 20; i++) begin
                idle_cycles = $urandom_range(0, 3);
                repeat (idle_cycles) begin
                    @(negedge clk_i);
                    valid_i = 0;
                    data_i = '0;
                    if (valid_o !== 1'b0) $fatal(1, "valid_o should deassert when valid_i is low");
                end

                word = $urandom;
                if (hs >= MAX_SAMPLES) $fatal(1, "Scoreboard overflow (MAX_SAMPLES=%0d)", MAX_SAMPLES);
                hist[hs] = word;
                hs++;
                push_word(word);

                if (hs > DELAY_P) begin
                    exp = hist[hs - 1 - DELAY_P];
                    if (data_o !== exp) $fatal(1, "Gapped sequence mismatch got %0d exp %0d", data_o, exp);
                end
            end

            for (int i = 0; i < DELAY_P; i++) begin
                if (hs >= MAX_SAMPLES) $fatal(1, "Scoreboard overflow (MAX_SAMPLES=%0d)", MAX_SAMPLES);
                hist[hs] = '0;
                hs++;
                push_word('0);
                if (hs > DELAY_P) begin
                    exp = hist[hs - 1 - DELAY_P];
                    if (data_o !== exp) $fatal(1, "Flush mismatch got %0d exp %0d", data_o, exp);
                end
            end
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars();

        check_reset_hold();
        check_expected_delay();
        check_wraparound();
        check_valid_deassert_and_gaps();

        $display("ramdelaybuffer_tb passed");
        $finish;
    end

endmodule
