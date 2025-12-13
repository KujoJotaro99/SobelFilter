`timescale 1ns/1ps

module dff_posedge_sync_tb;

    logic clk_i;
    logic d_i;
    logic rstn_i;
    logic q_o;

    dff_posedge_sync dut (
        .clk_i(clk_i),
        .d_i(d_i),
        .rstn_i(rstn_i),
        .q_o(q_o)
    );

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    initial begin
        rstn_i = 0;
        d_i = 1'b0;
        @(posedge clk_i);
        #1;
        if (q_o !== 0) $fatal(1, "Reset failed expected 0 got %0b", q_o);

        rstn_i = 1;
        d_i = 1'b1;
        @(posedge clk_i);
        #1;
        if (q_o !== 1'b1) $fatal(1, "Sample failed expected 1 got %0b", q_o);

        d_i = 1'b0;
        @(posedge clk_i);
        #1;
        if (q_o !== 1'b0) $fatal(1, "Sample failed expected 0 got %0b", q_o);

        $display("dff_posedge_sync_tb passed");
        $finish;
    end

endmodule
