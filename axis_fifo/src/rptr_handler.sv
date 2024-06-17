module rptr_handler #(parameter PTR_WIDTH=3) (
  input rclk, rrst_n, r_en,
  input [PTR_WIDTH:0] g_wptr_sync,
  output reg [PTR_WIDTH:0] b_rptr, g_rptr,
  output reg [PTR_WIDTH:0] usedw,
  output reg empty
);

  reg [PTR_WIDTH:0] b_rptr_next;
  reg [PTR_WIDTH:0] g_rptr_next;
  reg [PTR_WIDTH:0] b_wptr_sync;

  assign b_rptr_next = b_rptr+(r_en & !empty);
  assign g_rptr_next = (b_rptr_next >>1)^b_rptr_next;
  assign rempty = (g_wptr_sync == g_rptr_next);
  
    // Gray to binary conversion function
  function [PTR_WIDTH:0] gray2bin;
      input [PTR_WIDTH:0] gray;
      integer i;
      reg [PTR_WIDTH:0] bin;
   begin
      bin[PTR_WIDTH] = gray[PTR_WIDTH];
      for (i = PTR_WIDTH-1; i >= 0; i = i - 1) begin
         bin[i] = bin[i+1] ^ gray[i];
      end
      gray2bin = bin;
   end
  endfunction
  
  // Synchronize the write pointer to the read clock domain and convert it to binary
  always @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      b_wptr_sync <= 0;
    end else begin
      b_wptr_sync <= gray2bin(g_wptr_sync);
    end
  end
  
  always@(posedge rclk or negedge rrst_n) begin
    if(!rrst_n) begin
      b_rptr <= 0;
      g_rptr <= 0;
    end
    else begin
      b_rptr <= b_rptr_next;
      g_rptr <= g_rptr_next;
    end
  end
  
  always@(posedge rclk or negedge rrst_n) begin
    if(!rrst_n) empty <= 1;
    else        empty <= rempty;
  end
  
  assign usedw = b_wptr_sync - b_rptr;
  
endmodule