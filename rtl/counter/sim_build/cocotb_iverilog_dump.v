module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/counter.fst");
    $dumpvars(0, counter);
end
endmodule
