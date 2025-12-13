module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/half_add.fst");
    $dumpvars(0, half_add);
end
endmodule
