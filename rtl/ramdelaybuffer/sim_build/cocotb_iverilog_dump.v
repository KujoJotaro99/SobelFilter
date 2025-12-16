module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/ramdelaybuffer.fst");
    $dumpvars(0, ramdelaybuffer);
end
endmodule
