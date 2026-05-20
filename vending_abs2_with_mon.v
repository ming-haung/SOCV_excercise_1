/* 
   Stronger abstraction for BDD verification (state-space reduction).
   Keep only the control-flow and arithmetic guards that affect the monitors.
   - Remove internal coin inventory / change-making loop.
   - Reduce itemNumber bit-width to 2.
   - Reduce values to 6-bit.
*/

`define SERVICE_OFF     2'b00
`define SERVICE_ON      2'b01
`define SERVICE_BUSY    2'b10

`define ITEM_A          2'b00
`define ITEM_B          2'b01
`define ITEM_C          2'b10
`define ITEM_D          2'b11

`define COST_ITEM_A     6'd2
`define COST_ITEM_B     6'd3
`define COST_ITEM_C     6'd5
`define COST_ITEM_D     6'd6

module vendingMachineAbs2WithMon(
   clk,
   reset,
   // inputs
   inputValueIn,
   itemTypeIn,
   itemNumberIn,
   forceIn,
   // outputs
   serviceTypeOut,
   itemTypeOut,
   itemNumberOut,
   // monitors
   p_underflow_item,
   p_illegal_service_state
);

input        clk;
input        reset;
input  [5:0] inputValueIn;
input  [1:0] itemTypeIn;
input  [1:0] itemNumberIn;
input        forceIn;

output [1:0] serviceTypeOut;
output [1:0] itemTypeOut;
output [1:0] itemNumberOut;
output       p_underflow_item;
output       p_illegal_service_state;

reg    [1:0] serviceTypeOut;
reg    [1:0] itemTypeOut;
reg    [1:0] itemNumberOut;
reg          forceService;
reg          changeReady;
reg    [5:0] inputValue;
reg    [5:0] serviceValue;

assign p_illegal_service_state = (serviceTypeOut == 2'b11);

assign p_underflow_item =
    (serviceTypeOut == `SERVICE_BUSY) &&
    (!changeReady) &&
    (inputValue < serviceValue) &&
    (forceService) &&
    (itemNumberOut == 2'd0);

function [5:0] cost_mul;
  input [1:0] t;
  input [1:0] n;
  reg [5:0] c;
  begin
    c = (t == `ITEM_A) ? `COST_ITEM_A :
        (t == `ITEM_B) ? `COST_ITEM_B :
        (t == `ITEM_C) ? `COST_ITEM_C :
        (t == `ITEM_D) ? `COST_ITEM_D : 6'd0;
    cost_mul = c * {4'd0, n};
  end
endfunction

always @(posedge clk) begin
  if (!reset) begin
    serviceTypeOut <= `SERVICE_ON;
    itemTypeOut    <= `ITEM_A;
    itemNumberOut  <= 2'd0;
    forceService   <= 1'b0;
    changeReady    <= 1'b0;
    inputValue     <= 6'd0;
    serviceValue   <= 6'd0;
  end else begin
    case (serviceTypeOut)
      `SERVICE_ON: begin
        if (itemNumberIn != 2'd0) begin
          serviceTypeOut <= `SERVICE_BUSY;
          itemTypeOut    <= itemTypeIn;
          itemNumberOut  <= itemNumberIn;
          forceService   <= forceIn;
          changeReady    <= 1'b0;
          inputValue     <= inputValueIn;
          serviceValue   <= cost_mul(itemTypeIn, itemNumberIn);
        end
      end
      `SERVICE_OFF: begin
        serviceTypeOut <= `SERVICE_ON;
      end
      default: begin // BUSY
        if (!changeReady) begin
          if (inputValue < serviceValue) begin
            if (forceService) begin
              itemNumberOut <= itemNumberOut - 2'd1;
              serviceValue  <= serviceValue - cost_mul(itemTypeOut, 2'd1);
            end else begin
              changeReady   <= 1'b1;
              serviceValue  <= inputValue; // refund
              itemNumberOut <= 2'd0;
            end
          end else begin
            changeReady  <= 1'b1;
            serviceValue <= inputValue - serviceValue; // remaining change
          end
        end else begin
          // abstract change-making as one-step completion
          serviceTypeOut <= `SERVICE_OFF;
        end
      end
    endcase
  end
end

endmodule

