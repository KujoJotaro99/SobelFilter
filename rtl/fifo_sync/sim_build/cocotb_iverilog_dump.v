module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/fifo_sync.fst");
    $dumpvars(0, fifo_sync);
end
endmodule
