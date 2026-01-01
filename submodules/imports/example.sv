module fifo_1r1w_cdc
 #(parameter [31:0] width_p = 32
  ,parameter [31:0] depth_log2_p = 8
  )
   // To emphasize that the two interfaces are in different clock
   // domains i've annotated the two sides of the fifo with "c" for
   // consumer, and "p" for producer. 
  (input [0:0] cclk_i
  ,input [0:0] creset_i
  ,input [width_p - 1:0] cdata_i
  ,input [0:0] cvalid_i
  ,output [0:0] cready_o 

  ,input [0:0] pclk_i
  ,input [0:0] preset_i
  ,output [0:0] pvalid_o 
  ,output [width_p - 1:0] pdata_o 
  ,input [0:0] pready_i
  );
   
  // signal initilization
  logic [depth_log2_p:0] wr_ptr_l, wr_ptr_l_gray, wr_ptr_l_gray_sync, wr_ptr_l_sync, rd_ptr_l, rd_ptr_l_nxt, rd_ptr_l_gray, rd_ptr_l_gray_sync, rd_ptr_l_sync;

  // write
  always @(posedge cclk_i) begin
    if (creset_i) begin
      wr_ptr_l <= '0;
    end else if (cvalid_i & cready_o) begin
      wr_ptr_l <= wr_ptr_l + 1;
    end
  end

  Nbin2gray #(.N(depth_log2_p+1)) wrgray (.bin_i(wr_ptr_l), .gray_o(wr_ptr_l_gray));
  sync2 #(.width(depth_log2_p+1)) wr_to_rd (.rst_i(preset_i), .clk_sync_i(pclk_i), .sync_i(wr_ptr_l_gray), .sync_o(wr_ptr_l_gray_sync));
  Ngray2bin #(.N(depth_log2_p+1)) wrsync (.bin_o(wr_ptr_l_sync), .gray_i(wr_ptr_l_gray_sync));

  // read 
  always @(posedge pclk_i) begin
    if (preset_i) begin
      rd_ptr_l <= '0;
    end else begin
      rd_ptr_l <= rd_ptr_l_nxt;
    end
  end

  always_comb begin
    if (pvalid_o & pready_i) begin
      rd_ptr_l_nxt = rd_ptr_l + 1;
    end else begin
      rd_ptr_l_nxt = rd_ptr_l;
    end
  end

  Nbin2gray #(.N(depth_log2_p+1)) rdgray (.bin_i(rd_ptr_l), .gray_o(rd_ptr_l_gray));
  sync2 #(.width(depth_log2_p+1)) rd_to_wr (.rst_i(creset_i), .clk_sync_i(cclk_i), .sync_i(rd_ptr_l_gray), .sync_o(rd_ptr_l_gray_sync));
  Ngray2bin #(.N(depth_log2_p+1)) rdsync (.bin_o(rd_ptr_l_sync), .gray_i(rd_ptr_l_gray_sync));

  // async memory
  ram_1r1w_async #(
    .width_p(width_p),
    .depth_p(1<<depth_log2_p)
  ) mem_inst (
    .wr_clk_i(cclk_i),
    .wr_reset_i(creset_i),
    .wr_valid_i(cvalid_i & cready_o),
    .wr_data_i(cdata_i),
    .wr_addr_i(wr_ptr_l[depth_log2_p-1:0]),

    .rd_clk_i(pclk_i),
    .rd_reset_i(preset_i),
    .rd_valid_i(1'b1),
    .rd_addr_i(rd_ptr_l_nxt[depth_log2_p-1:0]),
    .rd_data_o(pdata_o)
  );


  // axi handshake, empty belongs to read domain, full belongs to write domain
  assign pvalid_o = ~(wr_ptr_l_sync[depth_log2_p:0] == rd_ptr_l[depth_log2_p:0]); // not empty
  assign cready_o = ~((wr_ptr_l[depth_log2_p] != rd_ptr_l_sync[depth_log2_p]) & (wr_ptr_l[depth_log2_p-1:0] == rd_ptr_l_sync[depth_log2_p-1:0])); // not full
   
endmodule