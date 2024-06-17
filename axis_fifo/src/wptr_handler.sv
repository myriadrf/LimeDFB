module wptr_handler #(parameter PTR_WIDTH=3) (
  input wclk, wrst_n, w_en,
  input [PTR_WIDTH:0] g_rptr_sync,
  output reg [PTR_WIDTH:0] b_wptr, g_wptr,
  output reg [PTR_WIDTH:0] usedw,
  output reg full
);

  reg [PTR_WIDTH:0] b_wptr_next;
  reg [PTR_WIDTH:0] g_wptr_next;
  reg [PTR_WIDTH:0] b_rptr_sync;
   
  reg wrap_around;
  wire wfull;
  
  assign b_wptr_next = b_wptr+(w_en & !full);
  assign g_wptr_next = (b_wptr_next >>1)^b_wptr_next;
  
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
   
  // Synchronize the read pointer to the write clock domain and convert it to binary
  always @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      b_rptr_sync <= 0;
    end else begin
      b_rptr_sync <= gray2bin(g_rptr_sync);
    end
  end
  
  always@(posedge wclk or negedge wrst_n) begin
    if(!wrst_n) begin
      b_wptr <= 0; // set default value
      g_wptr <= 0;
    end
    else begin
      b_wptr <= b_wptr_next; // incr binary write pointer
      g_wptr <= g_wptr_next; // incr gray write pointer
    end
  end
  
  always@(posedge wclk or negedge wrst_n) begin
    if(!wrst_n) full <= 0;
    else        full <= wfull;
  end

  //assign wrap_around = (g_wptr_next) ^ g_rptr_sync[PTR_WIDTH]; // To check MSB of write and read pointers are different
  //assign wfull = wrap_around & (g_wptr_next[PTR_WIDTH-1] ^ g_rptr_sync[PTR_WIDTH-1]) & (g_wptr_next[PTR_WIDTH-2:0] == g_rptr_sync[PTR_WIDTH-2:0]);
  assign wfull = (g_wptr_next == {~g_rptr_sync[PTR_WIDTH:PTR_WIDTH-1], g_rptr_sync[PTR_WIDTH-2:0]});
  
  assign usedw = b_wptr - b_rptr_sync;

endmodule