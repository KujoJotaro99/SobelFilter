module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/add.fst");
    $dumpvars(0, add);
end
endmodule
