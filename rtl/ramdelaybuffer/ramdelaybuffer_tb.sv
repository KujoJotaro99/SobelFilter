`timescale 1ns/1ps

module ramdelaybuffer_tb;

    localparam int WIDTH_P = 8;
    localparam int DELAY_P = 12;
    localparam int DELAY_A_P = DELAY_P;
    localparam int DELAY_B_P = (DELAY_P > 1) ? (DELAY_P/2) : DELAY_P;

    logic [0:0] clk_i;
    logic [0:0] rstn_i;
    logic [0:0] valid_i;
    logic [0:0] ready_i;
    logic [0:0] valid_o;
    logic [0:0] ready_o;
    logic [WIDTH_P-1:0] data_i;
    logic [WIDTH_P-1:0] data_a_o;
    logic [WIDTH_P-1:0] data_b_o;
    logic [WIDTH_P-1:0] history [$];

    ramdelaybuffer #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(DELAY_P),
        .DELAY_A_P(DELAY_A_P),
        .DELAY_B_P(DELAY_B_P)
    ) dut (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i),
        .ready_i(ready_i),
        .valid_o(valid_o),
        .ready_o(ready_o),
        .data_i(data_i),
        .data_a_o(data_a_o),
        .data_b_o(data_b_o)
    );

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    task automatic reset_dut;
        begin
            rstn_i = 0;
            valid_i = 0;
            ready_i = 1;
            data_i = '0;
            history.delete();
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
            history.push_back(word);
            check_history_outputs();
        end
    endtask

    task automatic check_history_outputs;
        int hist_sz;
        logic [WIDTH_P-1:0] exp_val;
        begin
            hist_sz = history.size();
            if (hist_sz > DELAY_A_P) begin
                exp_val = history[hist_sz-1-DELAY_A_P];
                if (data_a_o !== exp_val) begin
                    $fatal(1, "Port A mismatch got %0d exp %0d at hist_sz %0d", data_a_o, exp_val, hist_sz);
                end
            end
            if (hist_sz > DELAY_B_P) begin
                exp_val = history[hist_sz-1-DELAY_B_P];
                if (data_b_o !== exp_val) begin
                    $fatal(1, "Port B mismatch got %0d exp %0d at hist_sz %0d", data_b_o, exp_val, hist_sz);
                end
            end
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
            for (int i = 0; i < DELAY_A_P; i++) begin
                push_word('0);
            end

            if (data_a_o !== token) $fatal(1, "Delayed A value mismatch got %0d exp %0d", data_a_o, token);

            reset_dut();
            push_word(token);
            for (int i = 0; i < DELAY_B_P; i++) begin
                push_word('0);
            end
            if (data_b_o !== token) $fatal(1, "Delayed B value mismatch got %0d exp %0d", data_b_o, token);
        end
    endtask

    task automatic check_wraparound;
        localparam int TOTAL = (DELAY_P * 2) + 3;
        logic [WIDTH_P-1:0] sent [0:TOTAL-1];
        logic [WIDTH_P-1:0] observed_a [0:TOTAL-1];
        logic [WIDTH_P-1:0] observed_b [0:TOTAL-1];
        logic [WIDTH_P-1:0] word;
        int obs_idx_a;
        int obs_idx_b;
        begin
            reset_dut();
            for (int i = 0; i < TOTAL; i++) begin
                sent[i] = (i + 1);
            end

            obs_idx_a = 0;
            obs_idx_b = 0;
            for (int i = 0; i < (TOTAL + DELAY_P); i++) begin
                word = (i < TOTAL) ? sent[i] : '0;
                push_word(word);
                if ((i >= DELAY_A_P) && ((i - DELAY_A_P) < TOTAL)) begin
                    observed_a[obs_idx_a] = data_a_o;
                    obs_idx_a++;
                end
                if ((i >= DELAY_B_P) && ((i - DELAY_B_P) < TOTAL)) begin
                    observed_b[obs_idx_b] = data_b_o;
                    obs_idx_b++;
                end
            end

            for (int i = 0; i < TOTAL; i++) begin
                if (observed_a[i] !== sent[i]) begin
                    $fatal(1, "Wraparound ordering mismatch port A idx %0d got %0d exp %0d", i, observed_a[i], sent[i]);
                end
                if (observed_b[i] !== sent[i]) begin
                    $fatal(1, "Wraparound ordering mismatch port B idx %0d got %0d exp %0d", i, observed_b[i], sent[i]);
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

                if (hs > DELAY_A_P) begin
                    exp = hist[hs - 1 - DELAY_A_P];
                    if (data_a_o !== exp) $fatal(1, "Gapped sequence mismatch got %0d exp %0d", data_a_o, exp);
                end
            end

            for (int i = 0; i < DELAY_P; i++) begin
                if (hs >= MAX_SAMPLES) $fatal(1, "Scoreboard overflow (MAX_SAMPLES=%0d)", MAX_SAMPLES);
                hist[hs] = '0;
                hs++;
                push_word('0);
                if (hs > DELAY_A_P) begin
                    exp = hist[hs - 1 - DELAY_A_P];
                    if (data_a_o !== exp) $fatal(1, "Flush mismatch got %0d exp %0d", data_a_o, exp);
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
