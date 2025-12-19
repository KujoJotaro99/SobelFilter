module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/conv2d.fst");
    $dumpvars(0, conv2d);
end
endmodule
